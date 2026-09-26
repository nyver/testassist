// Command server is the Test Assistant HTTPS API server. This package only
// parses flags and dispatches subcommands; everything else lives in internal/.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/nyver/test-assistant/server/internal/app"
	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/identity"
	"github.com/nyver/test-assistant/server/internal/tlscert"
)

// version is the build version, set with -ldflags "-X main.version=...".
var version = "dev"

const (
	exitOK    = 0
	exitError = 1
	exitUsage = 2
)

const usage = `Usage:
  server [serve] [-config FILE]        run the HTTPS API server (default)
  server certificate fingerprint [-config FILE]
                                       print the SHA-256 fingerprint of the configured certificate
  server token show [-config FILE]     print the API token
  server token rotate [-config FILE]   replace the API token (restart the server afterwards)
  server healthcheck [-config FILE]    check /health/ready on the local listener

The configuration file may also be set with APP_CONFIG.
`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	code := run(ctx, os.Args[1:], config.OSEnv, os.Stdout, os.Stderr)
	stop()
	os.Exit(code)
}

// run executes one invocation and returns the process exit code.
func run(ctx context.Context, args []string, getenv config.Env, stdout, stderr io.Writer) int {
	cmd, rest := "serve", args
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		cmd, rest = args[0], args[1:]
	}

	switch cmd {
	case "serve":
		return withConfig(rest, getenv, stderr, "serve", func(cfg *config.Config) int {
			return serve(ctx, cfg, stdout, stderr)
		})
	case "healthcheck":
		return withConfig(rest, getenv, stderr, "healthcheck", func(cfg *config.Config) int {
			if err := app.HealthCheck(ctx, cfg); err != nil {
				return fail(stderr, "healthcheck failed: %v", err)
			}
			_, _ = fmt.Fprintln(stdout, "ok")
			return exitOK
		})
	case "certificate":
		if len(rest) == 0 || rest[0] != "fingerprint" {
			return usageError(stderr, "certificate needs the subcommand: fingerprint")
		}
		return withConfig(rest[1:], getenv, stderr, "certificate fingerprint", func(cfg *config.Config) int {
			// Read-only: never generates a certificate.
			fp, err := tlscert.FingerprintFromFile(cfg.TLS.CertFile)
			if err != nil {
				return fail(stderr, "%v", err)
			}
			_, _ = fmt.Fprintln(stdout, fp)
			return exitOK
		})
	case "token":
		if len(rest) == 0 || (rest[0] != "show" && rest[0] != "rotate") {
			return usageError(stderr, "token needs a subcommand: show or rotate")
		}
		return withConfig(rest[1:], getenv, stderr, "token "+rest[0], func(cfg *config.Config) int {
			return token(rest[0], cfg, stdout, stderr)
		})
	default:
		return usageError(stderr, fmt.Sprintf("unknown command %q", cmd))
	}
}

func usageError(stderr io.Writer, msg string) int {
	_, _ = fmt.Fprintf(stderr, "%s\n\n%s", msg, usage)
	return exitUsage
}

// token implements "token show" and "token rotate".
func token(action string, cfg *config.Config, stdout, stderr io.Writer) int {
	if cfg.Security.AuthToken != "" {
		// AUTH_TOKEN wins over auth.json, so there is nothing to rotate here.
		if action == "rotate" {
			return fail(stderr, "AUTH_TOKEN is set in the environment; change it in your deployment instead of rotating")
		}
		_, _ = fmt.Fprintln(stderr, "note: showing the token from the environment (AUTH_TOKEN); auth.json is ignored")
		_, _ = fmt.Fprintln(stdout, cfg.Security.AuthToken)
		return exitOK
	}

	var (
		value string
		err   error
	)
	if action == "rotate" {
		value, err = identity.RotateToken(cfg.Server.DataDir)
	} else {
		value, err = identity.LoadOrCreateToken(cfg.Server.DataDir)
	}
	if err != nil {
		return fail(stderr, "%v", err)
	}
	if action == "rotate" {
		_, _ = fmt.Fprintln(stderr, "note: restart the server to apply the new token; clients must be updated")
	}
	_, _ = fmt.Fprintln(stdout, value)
	return exitOK
}

// withConfig parses the -config flag of a command, loads the configuration and
// runs fn.
func withConfig(args []string, getenv config.Env, stderr io.Writer, name string, fn func(*config.Config) int) int {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(stderr)
	path := fs.String("config", getenv("APP_CONFIG"), "path of the YAML configuration file")
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return exitOK
		}
		return exitUsage
	}
	if fs.NArg() > 0 {
		_, _ = fmt.Fprintf(stderr, "unexpected argument %q\n\n%s", fs.Arg(0), usage)
		return exitUsage
	}

	cfg, err := config.Load(*path, getenv)
	if err != nil {
		return fail(stderr, "%v", err)
	}
	return fn(cfg)
}

func serve(ctx context.Context, cfg *config.Config, stdout, stderr io.Writer) int {
	logger := slog.New(slog.NewJSONHandler(stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	err := app.Serve(ctx, cfg, app.Options{Version: version, Stdout: stdout, Logger: logger})
	if err != nil {
		logger.Error("server failed", slog.String("error", err.Error()))
		return exitError
	}
	return exitOK
}

func fail(stderr io.Writer, format string, args ...any) int {
	_, _ = fmt.Fprintf(stderr, "error: "+format+"\n", args...)
	return exitError
}
