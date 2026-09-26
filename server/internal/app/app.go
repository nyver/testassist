// Package app wires the server together: configuration, identity, TLS,
// providers and the HTTP API, and runs them until shutdown.
package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/nyver/test-assistant/server/internal/analysis"
	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/identity"
	"github.com/nyver/test-assistant/server/internal/llm"
	"github.com/nyver/test-assistant/server/internal/llm/openaicompat"
	"github.com/nyver/test-assistant/server/internal/tlscert"
	"github.com/nyver/test-assistant/server/internal/transport/httpapi"
)

const (
	// writeTimeoutMargin lets a response be written after the request timeout
	// has expired, so timeouts are reported as errors instead of dropped.
	writeTimeoutMargin = 10 * time.Second
	maxHeaderBytes     = 64 << 10
)

// Options are the inputs of Serve besides the configuration.
type Options struct {
	Version string
	// Stdout receives the human-readable startup lines.
	Stdout io.Writer
	Logger *slog.Logger
	// Listener, when set, replaces listening on the configured address. Tests
	// use it to bind a random port.
	Listener net.Listener
	// ProviderFactory replaces the OpenAI-compatible adapter in tests.
	ProviderFactory llm.ProviderFactory
	// Ready, when set, is called once the certificate is loaded and the
	// listener is bound, right before requests are served.
	Ready func()
}

// Serve runs the server until ctx is cancelled, then shuts down gracefully: it
// stops accepting connections, lets in-flight requests finish within the
// configured shutdown timeout and stops the background workers. It returns nil
// after a clean shutdown.
func Serve(ctx context.Context, cfg *config.Config, opts Options) error {
	log := opts.Logger

	info, err := identity.LoadOrCreateServer(cfg.Server.DataDir, cfg.Server.Name)
	if err != nil {
		return fmt.Errorf("load server identity: %w", err)
	}

	token := ""
	if cfg.Security.AuthEnabled {
		if token, err = identity.ResolveToken(cfg.Server.DataDir, cfg.Security.AuthToken); err != nil {
			return fmt.Errorf("load API token: %w", err)
		}
	} else {
		log.Warn("authentication is disabled: every /api/v1/ endpoint is open to anyone who can reach the server")
	}

	cert, err := tlscert.LoadOrGenerate(tlscert.Options{
		CertFile: cfg.TLS.CertFile,
		KeyFile:  cfg.TLS.KeyFile,
		Name:     cfg.Server.Name,
		Hosts:    cfg.TLS.SelfSignedHosts,
	})
	if err != nil {
		return err
	}
	if cert.Generated {
		log.Info("generated a self-signed TLS certificate", slog.String("cert_file", cfg.TLS.CertFile))
	}

	factory := opts.ProviderFactory
	if factory == nil {
		factory = func(p config.ProviderConfig) llm.Provider {
			return openaicompat.New(openaicompat.OptionsFromConfig(p, cfg))
		}
	}
	for _, p := range cfg.LLM.Providers {
		if !p.Enabled {
			log.Warn("provider disabled: no API key found", slog.String("provider", p.ID), slog.String("api_key_env", p.APIKeyEnv))
		}
	}
	registry := llm.NewRegistry(cfg, factory, nil)
	if !registry.Enabled() {
		log.Warn("no LLM provider is enabled; /health/ready will report not ready")
	}

	api := httpapi.New(httpapi.Deps{
		Config:     cfg,
		Identity:   info,
		Version:    opts.Version,
		Token:      token,
		CertLoaded: true,
		Registry:   registry,
		Analysis: analysis.NewService(registry, analysis.Settings{
			Timeout:    cfg.Timeouts.LLM,
			MaxTokens:  cfg.LLM.MaxTokens,
			Confidence: cfg.Confidence,
		}),
		Logger: log,
	})

	srv := &http.Server{
		Handler:           api.Handler(),
		TLSConfig:         cert.TLSConfig(),
		ReadHeaderTimeout: cfg.Timeouts.ReadHeader,
		ReadTimeout:       cfg.Timeouts.Read,
		WriteTimeout:      cfg.Timeouts.Request + writeTimeoutMargin,
		IdleTimeout:       cfg.Timeouts.Idle,
		MaxHeaderBytes:    maxHeaderBytes,
		// Handshake errors, for example plaintext HTTP sent to this port, are
		// logged at warn level through the structured logger.
		ErrorLog: slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}

	ln := opts.Listener
	listenAddr := cfg.Server.Listen
	if ln == nil {
		lc := net.ListenConfig{}
		if ln, err = lc.Listen(ctx, "tcp", cfg.Server.Listen); err != nil {
			return fmt.Errorf("listen on %s: %w", cfg.Server.Listen, err)
		}
	} else {
		listenAddr = ln.Addr().String()
	}

	_, _ = fmt.Fprintf(opts.Stdout, "HTTPS listening on %s\n", listenAddr)
	_, _ = fmt.Fprintf(opts.Stdout, "Certificate SHA-256 fingerprint: %s\n", cert.Fingerprint)
	log.Info("server started", slog.String("version", opts.Version), slog.String("server_id", info.ServerID),
		slog.String("prompt_version", analysis.PromptVersion))

	// The workers stop when workersCtx is cancelled, after the HTTP server has
	// drained. Serve owns and waits for both goroutines.
	workersCtx, stopWorkers := context.WithCancel(context.WithoutCancel(ctx))
	defer stopWorkers()
	workersDone := make(chan struct{})
	go func() {
		defer close(workersDone)
		api.Run(workersCtx)
	}()

	serveErr := make(chan error, 1)
	go func() {
		// The certificate comes from TLSConfig, hence the empty file names.
		err := srv.ServeTLS(ln, "", "")
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
		serveErr <- err
	}()

	if opts.Ready != nil {
		opts.Ready()
	}

	select {
	case err := <-serveErr:
		stopWorkers()
		<-workersDone
		if err == nil {
			err = errors.New("listener stopped unexpectedly")
		}
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}

	log.Info("shutting down", slog.String("timeout", cfg.Timeouts.Shutdown.String()))
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), cfg.Timeouts.Shutdown)
	defer cancel()
	shutdownErr := srv.Shutdown(shutdownCtx)
	if shutdownErr != nil {
		_ = srv.Close() // force-close what is left after the timeout
	}
	stopWorkers()
	<-workersDone
	if err := <-serveErr; err != nil {
		return fmt.Errorf("serve: %w", err)
	}
	if shutdownErr != nil {
		return fmt.Errorf("graceful shutdown: %w", shutdownErr)
	}
	log.Info("server stopped")
	return nil
}
