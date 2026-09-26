package llm

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/nyver/test-assistant/server/internal/config"
)

type fakeProvider struct {
	calls   atomic.Int32
	models  []Model
	err     error
	gate    chan struct{} // when set, ListModels blocks until it is closed
	entered chan struct{} // closed when the first ListModels call starts
	once    sync.Once
}

func (f *fakeProvider) Complete(context.Context, ChatRequest) (ChatResponse, error) {
	return ChatResponse{}, errors.New("not used")
}

func (f *fakeProvider) ListModels(context.Context) ([]Model, error) {
	f.calls.Add(1)
	if f.entered != nil {
		f.once.Do(func() { close(f.entered) })
	}
	if f.gate != nil {
		<-f.gate
	}
	return f.models, f.err
}

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

func boolPtr(b bool) *bool { return &b }

func testConfig(providers ...config.ProviderConfig) *config.Config {
	cfg := config.Default()
	cfg.LLM.Providers = providers
	cfg.LLM.DefaultProvider = providers[0].ID
	cfg.LLM.ModelsCacheTTL = 10 * time.Minute
	return &cfg
}

func provider(id string, enabled bool, models ...config.ModelConfig) config.ProviderConfig {
	return config.ProviderConfig{
		ID: id, Name: id + " name", Type: config.ProviderTypeOpenAICompatible,
		BaseURL: "https://x.example/v1", Enabled: enabled, Models: models,
		DefaultModel: "m-default", StructuredOutput: config.StructuredOutputNone,
	}
}

func newTestRegistry(t *testing.T, cfg *config.Config, fp *fakeProvider) (*Registry, *fakeClock) {
	t.Helper()
	clock := &fakeClock{t: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
	return NewRegistry(cfg, func(config.ProviderConfig) Provider { return fp }, clock.Now), clock
}

func TestProvidersListsOnlyEnabledWithOneDefault(t *testing.T) {
	t.Parallel()

	cfg := testConfig(provider("a", false), provider("b", true), provider("c", true))
	cfg.LLM.DefaultProvider = "a" // disabled: the first enabled provider takes over
	reg, _ := newTestRegistry(t, cfg, &fakeProvider{})

	got := reg.Providers()
	if len(got) != 2 || got[0].ID != "b" || got[1].ID != "c" {
		t.Fatalf("providers = %+v", got)
	}
	if !got[0].IsDefault || got[1].IsDefault {
		t.Errorf("default flags = %v %v, want exactly the first", got[0].IsDefault, got[1].IsDefault)
	}
	if reg.Has("a") || !reg.Has("b") || reg.DefaultProviderID() != "b" || !reg.Enabled() {
		t.Errorf("Has/Default/Enabled mismatch: %v %v %q", reg.Has("a"), reg.Has("b"), reg.DefaultProviderID())
	}
	if reg.DefaultModel("b") != "m-default" || reg.DefaultModel("zzz") != "" {
		t.Errorf("DefaultModel = %q / %q", reg.DefaultModel("b"), reg.DefaultModel("zzz"))
	}
}

func TestNoEnabledProviders(t *testing.T) {
	t.Parallel()

	reg, _ := newTestRegistry(t, testConfig(provider("a", false)), &fakeProvider{})
	if reg.Enabled() || len(reg.Providers()) != 0 || reg.DefaultProviderID() != "" {
		t.Error("registry should be empty")
	}
	if _, err := reg.Models(t.Context(), "a"); err == nil {
		t.Error("Models for a disabled provider must fail")
	}
}

func TestModelsAreCachedWithinTTL(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{models: []Model{{ID: "m1", Name: "M1", Capabilities: Capabilities{Text: true}}}}
	reg, clock := newTestRegistry(t, testConfig(provider("a", true)), fp)

	for range 3 {
		if _, err := reg.Models(t.Context(), "a"); err != nil {
			t.Fatal(err)
		}
	}
	if got := fp.calls.Load(); got != 1 {
		t.Errorf("upstream calls within TTL = %d, want 1", got)
	}

	clock.Advance(10*time.Minute + time.Second)
	if _, err := reg.Models(t.Context(), "a"); err != nil {
		t.Fatal(err)
	}
	if got := fp.calls.Load(); got != 2 {
		t.Errorf("upstream calls after TTL = %d, want 2", got)
	}
}

func TestConcurrentRequestsShareOneFetch(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{
		models:  []Model{{ID: "m1"}},
		gate:    make(chan struct{}),
		entered: make(chan struct{}),
	}
	reg, _ := newTestRegistry(t, testConfig(provider("a", true)), fp)

	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := reg.Models(t.Context(), "a"); err != nil {
				t.Error(err)
			}
		}()
	}
	<-fp.entered
	// Late goroutines hit either the in-flight fetch or the cache: one call.
	close(fp.gate)
	wg.Wait()

	if got := fp.calls.Load(); got != 1 {
		t.Errorf("upstream calls = %d, want 1 (singleflight)", got)
	}
}

func TestStaticModelsMergeAndConfigWinsOverDetectedCapability(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{models: []Model{
		{ID: "x/model", Name: "X", Capabilities: Capabilities{Text: true, Vision: true}},
		{ID: "b/plain", Name: "B", Capabilities: Capabilities{Text: true}},
		{ID: "a/other", Name: "A", Capabilities: Capabilities{Text: true, Vision: true}},
	}}
	cfg := testConfig(provider("a", true,
		config.ModelConfig{ID: "x/model", Vision: boolPtr(false)},                                                                     // overrides detection
		config.ModelConfig{ID: "custom", Name: "Custom", Text: boolPtr(true), Vision: boolPtr(true), StructuredOutput: "json_object"}, // static only
	))
	reg, _ := newTestRegistry(t, cfg, fp)

	models, err := reg.Models(t.Context(), "a")
	if err != nil {
		t.Fatal(err)
	}
	gotIDs := make([]string, len(models))
	for i, m := range models {
		gotIDs[i] = m.ID
	}
	wantIDs := []string{"x/model", "custom", "a/other", "b/plain"} // static first, then upstream sorted by id
	if len(gotIDs) != len(wantIDs) {
		t.Fatalf("ids = %v, want %v", gotIDs, wantIDs)
	}
	for i := range wantIDs {
		if gotIDs[i] != wantIDs[i] {
			t.Fatalf("ids = %v, want %v", gotIDs, wantIDs)
		}
	}

	if m := models[0]; m.Capabilities.Vision || !m.Capabilities.Text || m.Name != "X" {
		t.Errorf("x/model = %+v: config vision=false must win, name from upstream", m)
	}
	if m := models[1]; !m.Capabilities.Vision || m.Name != "Custom" || m.StructuredOutput != "json_object" {
		t.Errorf("custom = %+v", m)
	}
	if m := models[2]; !m.Capabilities.Vision || m.StructuredOutput != config.StructuredOutputNone {
		t.Errorf("a/other = %+v: detected vision and the provider structured-output mode should stay", m)
	}

	found, ok, err := reg.FindModel(t.Context(), "a", "custom")
	if err != nil || !ok || found.ID != "custom" {
		t.Errorf("FindModel(custom) = %+v, %v, %v", found, ok, err)
	}
	if _, ok, _ := reg.FindModel(t.Context(), "a", "nope"); ok {
		t.Error("FindModel must not find an unknown model")
	}
}

func TestListingFailureFallsBackToStaticModels(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{err: errors.New("upstream down")}
	cfg := testConfig(provider("a", true, config.ModelConfig{ID: "static-1"}))
	reg, clock := newTestRegistry(t, cfg, fp)

	models, err := reg.Models(t.Context(), "a")
	if err != nil {
		t.Fatalf("Models must not fail when static models exist: %v", err)
	}
	if len(models) != 1 || models[0].ID != "static-1" || !models[0].Capabilities.Text {
		t.Errorf("models = %+v", models)
	}

	// The failure is remembered only briefly, so recovery is quick.
	if _, err := reg.Models(t.Context(), "a"); err != nil || fp.calls.Load() != 1 {
		t.Errorf("failure result should be cached briefly; calls = %d", fp.calls.Load())
	}
	clock.Advance(failureCacheTTL + time.Second)
	fp.err = nil
	fp.models = []Model{{ID: "live", Capabilities: Capabilities{Text: true}}}
	models, err = reg.Models(t.Context(), "a")
	if err != nil || len(models) != 2 {
		t.Errorf("after recovery models = %+v, %v", models, err)
	}
}

func TestListingFailureKeepsLastGoodListing(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{models: []Model{{ID: "live", Capabilities: Capabilities{Text: true, Vision: true}}}}
	reg, clock := newTestRegistry(t, testConfig(provider("a", true)), fp)
	if _, err := reg.Models(t.Context(), "a"); err != nil {
		t.Fatal(err)
	}

	clock.Advance(time.Hour)
	fp.err = errors.New("down")
	fp.models = nil
	models, err := reg.Models(t.Context(), "a")
	if err != nil || len(models) != 1 || models[0].ID != "live" || !models[0].Capabilities.Vision {
		t.Errorf("models = %+v, %v; want the last good listing", models, err)
	}
}

func TestListingFailureWithoutStaticModelsIsEmptyNotError(t *testing.T) {
	t.Parallel()

	reg, _ := newTestRegistry(t, testConfig(provider("a", true)), &fakeProvider{err: errors.New("down")})
	models, err := reg.Models(t.Context(), "a")
	if err != nil || len(models) != 0 {
		t.Errorf("models = %+v, %v", models, err)
	}
}

func TestErrorFormatting(t *testing.T) {
	t.Parallel()

	err := &Error{Kind: ErrProviderUnavailable, UpstreamStatus: 502, Detail: "network error"}
	if !errors.Is(err, ErrProviderUnavailable) || errors.Is(err, ErrTimeout) {
		t.Error("errors.Is should match only the Kind")
	}
	if got := err.Error(); got != "llm: provider unavailable (upstream status 502): network error" {
		t.Errorf("Error() = %q", got)
	}
}
