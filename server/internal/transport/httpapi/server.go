// Package httpapi is the HTTP transport: routing, middleware, the error
// envelope and the handlers of the v1 API and the health endpoints.
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/nyver/test-assistant/server/internal/analysis"
	"github.com/nyver/test-assistant/server/internal/apierr"
	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/identity"
	"github.com/nyver/test-assistant/server/internal/llm"
)

// Deps are the collaborators of the API server.
type Deps struct {
	Config   *config.Config
	Identity identity.Info
	// Version is the server build version reported by /api/v1/server/info.
	Version string
	// Token is the Bearer token to require. Ignored when auth is disabled.
	Token string
	// CertLoaded reports that a TLS certificate is loaded, for readiness.
	CertLoaded bool

	Registry *llm.Registry
	Analysis *analysis.Service
	Logger   *slog.Logger
	// Now defaults to time.Now. Tests inject a fake clock.
	Now func() time.Time
}

// Server serves the API. Build it with New and call Run in a goroutine that the
// caller owns.
type Server struct {
	deps    Deps
	general *ipLimiter
	analyze *ipLimiter
	handler http.Handler
}

// New wires the routes and middleware.
func New(deps Deps) *Server {
	if deps.Now == nil {
		deps.Now = time.Now
	}
	s := &Server{
		deps:    deps,
		general: newIPLimiter(deps.Config.RateLimit.General, deps.Now),
		analyze: newIPLimiter(deps.Config.RateLimit.Analyze, deps.Now),
	}
	s.handler = s.routes()
	return s
}

// Handler returns the root handler to serve over HTTPS.
func (s *Server) Handler() http.Handler { return s.handler }

// Run runs the background workers (limiter janitors) until ctx is done, then
// returns. It is the only goroutine the Server needs and its caller owns it.
func (s *Server) Run(ctx context.Context) {
	var wg sync.WaitGroup
	for _, l := range []*ipLimiter{s.general, s.analyze} {
		wg.Add(1)
		go func() {
			defer wg.Done()
			l.run(ctx)
		}()
	}
	wg.Wait()
}

func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()

	// Health endpoints: no authentication and no rate limit, so orchestrators
	// can always probe them.
	mux.HandleFunc("GET /health/live", s.healthLive)
	mux.HandleFunc("GET /health/ready", s.healthReady)

	mux.Handle("GET /api/v1/server/info", s.api(handle(s.serverInfo), false))
	mux.Handle("GET /api/v1/llm/providers", s.api(handle(s.listProviders), false))
	mux.Handle("GET /api/v1/llm/models", s.api(handle(s.listModels), false))
	mux.Handle("POST /api/v1/questions/analyze", s.api(handle(s.analyzeQuestion), true))

	// Anything else under /api/v1/ is a 404 in the error envelope. It still
	// requires authentication, so unauthenticated callers cannot probe routes.
	mux.Handle("/api/v1/", s.api(handle(notFound), false))
	mux.Handle("/", handle(notFound))

	var h http.Handler = mux
	h = recoverMiddleware(s.deps.Logger, h)
	h = accessLogMiddleware(s.deps.Logger, s.deps.Now, h)
	return requestIDMiddleware(h)
}

// api wraps an /api/v1 handler with rate limiting, authentication, the body
// limit and the request timeout, in that order. Analyze endpoints get their own
// limiter after authentication.
func (s *Server) api(h http.Handler, isAnalyze bool) http.Handler {
	cfg := s.deps.Config
	h = timeoutMiddleware(cfg.Timeouts.Request, h)
	h = bodyLimitMiddleware(cfg.Limits.MaxRequestBytes, h)
	if isAnalyze {
		h = s.analyze.middleware(h)
	}
	if cfg.Security.AuthEnabled {
		h = authMiddleware(s.deps.Token, h)
	}
	return s.general.middleware(h)
}

func notFound(http.ResponseWriter, *http.Request) error {
	return apierr.New(apierr.NotFound, "Not found.")
}
