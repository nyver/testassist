package llm

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"

	"github.com/nyver/test-assistant/server/internal/config"
)

const (
	// listFetchTimeout bounds one upstream model-list fetch. The fetch is
	// shared between concurrent callers, so it must not depend on any one
	// caller's context.
	listFetchTimeout = 15 * time.Second
	// failureCacheTTL keeps a fallback listing briefly so a failing upstream
	// is not hit by every request.
	failureCacheTTL = 30 * time.Second
)

// ProviderFactory builds the transport for one enabled provider.
type ProviderFactory func(config.ProviderConfig) Provider

// ProviderInfo describes an enabled provider for the API.
type ProviderInfo struct {
	ID        string
	Name      string
	IsDefault bool
}

// Registry holds the enabled providers and serves their merged, cached model
// listings.
type Registry struct {
	order     []*entry
	byID      map[string]*entry
	defaultID string
	ttl       time.Duration
	now       func() time.Time
}

type entry struct {
	id               string
	name             string
	defaultModel     string
	structuredOutput string
	provider         Provider
	static           []config.ModelConfig

	sf singleflight.Group

	mu       sync.Mutex
	cached   []Model
	expires  time.Time
	lastGood []Model // last successful upstream listing, before merging
}

// NewRegistry builds a registry from the enabled providers in cfg. A nil now
// defaults to time.Now.
func NewRegistry(cfg *config.Config, factory ProviderFactory, now func() time.Time) *Registry {
	if now == nil {
		now = time.Now
	}
	r := &Registry{
		byID: make(map[string]*entry),
		ttl:  cfg.LLM.ModelsCacheTTL,
		now:  now,
	}
	for _, p := range cfg.LLM.Providers {
		if !p.Enabled {
			continue
		}
		e := &entry{
			id:               p.ID,
			name:             p.Name,
			defaultModel:     p.DefaultModel,
			structuredOutput: p.StructuredOutput,
			provider:         factory(p),
			static:           p.Models,
		}
		r.order = append(r.order, e)
		r.byID[p.ID] = e
	}
	if def, ok := cfg.DefaultProvider(); ok {
		r.defaultID = def.ID
	}
	return r
}

// Providers lists the enabled providers in configuration order. Exactly one is
// the default unless none is enabled.
func (r *Registry) Providers() []ProviderInfo {
	out := make([]ProviderInfo, 0, len(r.order))
	for _, e := range r.order {
		out = append(out, ProviderInfo{ID: e.id, Name: e.name, IsDefault: e.id == r.defaultID})
	}
	return out
}

// DefaultProviderID returns the id used when a request names no provider, or ""
// when no provider is enabled.
func (r *Registry) DefaultProviderID() string { return r.defaultID }

// Enabled reports whether any provider is enabled.
func (r *Registry) Enabled() bool { return len(r.order) > 0 }

// Has reports whether id names an enabled provider.
func (r *Registry) Has(id string) bool {
	_, ok := r.byID[id]
	return ok
}

// DefaultModel returns the provider's configured default model id, which may
// be empty.
func (r *Registry) DefaultModel(providerID string) string {
	if e, ok := r.byID[providerID]; ok {
		return e.defaultModel
	}
	return ""
}

// Provider returns the transport for an enabled provider.
func (r *Registry) Provider(id string) (Provider, bool) {
	e, ok := r.byID[id]
	if !ok {
		return nil, false
	}
	return e.provider, true
}

// Models returns the merged model list for a provider: the provider's own
// listing overlaid with the configured static models, cached for the
// configured TTL. If the upstream listing fails, the last good listing (or the
// static models) is served instead. The caller must not modify the result.
func (r *Registry) Models(ctx context.Context, providerID string) ([]Model, error) {
	e, ok := r.byID[providerID]
	if !ok {
		return nil, fmt.Errorf("provider %q is not enabled", providerID)
	}
	if models, ok := e.fromCache(r.now()); ok {
		return models, nil
	}

	// Shared fetch: detached from this caller's cancellation but still bounded.
	v, _, _ := e.sf.Do("models", func() (any, error) {
		fetchCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), listFetchTimeout)
		defer cancel()
		return e.refresh(fetchCtx, r.now, r.ttl), nil
	})
	models, _ := v.([]Model)
	return models, nil
}

// FindModel returns one model of a provider, or false if the merged listing
// does not contain it.
func (r *Registry) FindModel(ctx context.Context, providerID, modelID string) (Model, bool, error) {
	models, err := r.Models(ctx, providerID)
	if err != nil {
		return Model{}, false, err
	}
	for _, m := range models {
		if m.ID == modelID {
			return m, true, nil
		}
	}
	return Model{}, false, nil
}

func (e *entry) fromCache(now time.Time) ([]Model, bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.cached != nil && now.Before(e.expires) {
		return e.cached, true
	}
	return nil, false
}

// refresh fetches the upstream listing and updates the cache. It never fails:
// a failed fetch falls back to the last good listing or the static models.
func (e *entry) refresh(ctx context.Context, now func() time.Time, ttl time.Duration) []Model {
	upstream, err := e.provider.ListModels(ctx)

	e.mu.Lock()
	defer e.mu.Unlock()
	if err == nil {
		e.lastGood = upstream
	}
	merged := mergeModels(e.lastGood, e.static, e.structuredOutput)
	e.cached = merged
	if err == nil {
		e.expires = now().Add(ttl)
	} else {
		e.expires = now().Add(min(ttl, failureCacheTTL))
	}
	return merged
}

// mergeModels overlays the static models on the upstream ones. Static models
// come first in configuration order; the remaining upstream models follow,
// sorted by id. Capabilities set in configuration take precedence over the
// upstream ones.
func mergeModels(upstream []Model, static []config.ModelConfig, providerStructured string) []Model {
	byID := make(map[string]Model, len(upstream))
	for _, m := range upstream {
		m.StructuredOutput = providerStructured
		byID[m.ID] = m
	}

	out := make([]Model, 0, len(upstream)+len(static))
	seen := make(map[string]bool, len(static))
	for _, s := range static {
		m, found := byID[s.ID]
		if !found {
			m = Model{ID: s.ID, Name: s.ID, Capabilities: Capabilities{Text: true}, StructuredOutput: providerStructured}
		}
		if s.Name != "" {
			m.Name = s.Name
		}
		if s.Text != nil {
			m.Capabilities.Text = *s.Text
		}
		if s.Vision != nil {
			m.Capabilities.Vision = *s.Vision
		}
		if s.StructuredOutput != "" {
			m.StructuredOutput = s.StructuredOutput
		}
		out = append(out, m)
		seen[s.ID] = true
	}

	rest := make([]Model, 0, len(byID))
	for id, m := range byID {
		if !seen[id] {
			rest = append(rest, m)
		}
	}
	slices.SortFunc(rest, func(a, b Model) int { return strings.Compare(a.ID, b.ID) })
	return append(out, rest...)
}
