package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/tlscert"
)

type cliEnv struct {
	dir  string
	vars map[string]string
}

func newCLIEnv(t *testing.T) *cliEnv {
	t.Helper()
	dir := t.TempDir()
	return &cliEnv{dir: dir, vars: map[string]string{
		"DATA_DIR":      filepath.Join(dir, "data"),
		"TLS_CERT_FILE": filepath.Join(dir, "certs", "server.crt"),
		"TLS_KEY_FILE":  filepath.Join(dir, "certs", "server.key"),
	}}
}

func (c *cliEnv) run(t *testing.T, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	var out, errOut bytes.Buffer
	getenv := config.Env(func(k string) string { return c.vars[k] })
	code = run(t.Context(), args, getenv, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestTokenShowAndRotate(t *testing.T) {
	t.Parallel()
	c := newCLIEnv(t)

	code, first, _ := c.run(t, "token", "show")
	if code != exitOK || len(strings.TrimSpace(first)) < 43 {
		t.Fatalf("token show = %d %q", code, first)
	}
	if _, again, _ := c.run(t, "token", "show"); again != first {
		t.Errorf("token changed between shows: %q vs %q", first, again)
	}

	code, rotated, stderr := c.run(t, "token", "rotate")
	if code != exitOK || rotated == first || strings.TrimSpace(rotated) == "" {
		t.Fatalf("token rotate = %d %q (old %q)", code, rotated, first)
	}
	if !strings.Contains(stderr, "restart") {
		t.Errorf("rotate should remind the operator to restart: %q", stderr)
	}
	if _, shown, _ := c.run(t, "token", "show"); shown != rotated {
		t.Errorf("show after rotate = %q, want %q", shown, rotated)
	}
	if strings.Contains(stderr, strings.TrimSpace(rotated)) {
		t.Error("the token must go to stdout only")
	}
}

func TestTokenFromEnvironment(t *testing.T) {
	t.Parallel()
	c := newCLIEnv(t)
	c.vars["AUTH_TOKEN"] = "env-token"

	code, out, _ := c.run(t, "token", "show")
	if code != exitOK || strings.TrimSpace(out) != "env-token" {
		t.Errorf("show = %d %q", code, out)
	}
	if code, _, stderr := c.run(t, "token", "rotate"); code != exitError || !strings.Contains(stderr, "AUTH_TOKEN") {
		t.Errorf("rotate = %d %q, want a failure that mentions AUTH_TOKEN", code, stderr)
	}
	if _, err := os.Stat(filepath.Join(c.vars["DATA_DIR"], "auth.json")); err == nil {
		t.Error("auth.json must not be created when AUTH_TOKEN is set")
	}
}

func TestCertificateFingerprint(t *testing.T) {
	t.Parallel()

	t.Run("prints the fingerprint of the existing certificate", func(t *testing.T) {
		t.Parallel()
		c := newCLIEnv(t)
		res, err := tlscert.LoadOrGenerate(tlscert.Options{CertFile: c.vars["TLS_CERT_FILE"], KeyFile: c.vars["TLS_KEY_FILE"], Name: "x"})
		if err != nil {
			t.Fatal(err)
		}
		code, out, _ := c.run(t, "certificate", "fingerprint")
		if code != exitOK || strings.TrimSpace(out) != res.Fingerprint {
			t.Errorf("got %d %q, want %s", code, out, res.Fingerprint)
		}
	})

	t.Run("without a certificate it fails and generates nothing", func(t *testing.T) {
		t.Parallel()
		c := newCLIEnv(t)
		code, out, stderr := c.run(t, "certificate", "fingerprint")
		if code == exitOK || out != "" || stderr == "" {
			t.Errorf("got %d %q %q", code, out, stderr)
		}
		for _, f := range []string{"TLS_CERT_FILE", "TLS_KEY_FILE"} {
			if _, err := os.Stat(c.vars[f]); err == nil {
				t.Errorf("%s was created", f)
			}
		}
	})
}

func TestUsageErrors(t *testing.T) {
	t.Parallel()
	c := newCLIEnv(t)
	for _, args := range [][]string{
		{"bogus"},
		{"token"},
		{"token", "burn"},
		{"certificate"},
		{"certificate", "bogus"},
		{"serve", "extra-arg"},
		{"-nonexistent-flag"},
	} {
		if code, _, _ := c.run(t, args...); code != exitUsage {
			t.Errorf("run %v = %d, want %d", args, code, exitUsage)
		}
	}
}

func TestConfigErrors(t *testing.T) {
	t.Parallel()
	c := newCLIEnv(t)

	if code, _, stderr := c.run(t, "token", "show", "-config", filepath.Join(c.dir, "absent.yaml")); code != exitError || stderr == "" {
		t.Errorf("missing config file = %d %q", code, stderr)
	}

	bad := filepath.Join(c.dir, "bad.yaml")
	if err := os.WriteFile(bad, []byte("server:\n  lisen: \":1\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code, _, stderr := c.run(t, "serve", "-config", bad)
	if code != exitError || !strings.Contains(stderr, "server.lisen") {
		t.Errorf("unknown key = %d %q, want a failure naming server.lisen", code, stderr)
	}

	// APP_CONFIG is honored when -config is absent.
	c.vars["APP_CONFIG"] = bad
	if code, _, stderr := c.run(t, "serve"); code != exitError || !strings.Contains(stderr, "server.lisen") {
		t.Errorf("APP_CONFIG = %d %q", code, stderr)
	}
}

func TestServeFailsOnBrokenState(t *testing.T) {
	t.Parallel()

	t.Run("corrupted identity file is not overwritten", func(t *testing.T) {
		t.Parallel()
		c := newCLIEnv(t)
		if err := os.MkdirAll(c.vars["DATA_DIR"], 0o750); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(c.vars["DATA_DIR"], "server.json")
		if err := os.WriteFile(path, []byte("{broken"), 0o600); err != nil {
			t.Fatal(err)
		}
		code, _, stderr := c.run(t, "serve")
		if code != exitError || stderr == "" {
			t.Errorf("serve = %d %q", code, stderr)
		}
		if got, _ := os.ReadFile(path); string(got) != "{broken" {
			t.Errorf("server.json was overwritten: %q", got)
		}
	})

	t.Run("partial certificate state", func(t *testing.T) {
		t.Parallel()
		c := newCLIEnv(t)
		if err := os.MkdirAll(filepath.Dir(c.vars["TLS_CERT_FILE"]), 0o750); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(c.vars["TLS_CERT_FILE"], []byte("placeholder"), 0o600); err != nil {
			t.Fatal(err)
		}
		code, _, stderr := c.run(t, "serve")
		if code != exitError || !strings.Contains(stderr, "TLS_CONFIGURATION_ERROR") {
			t.Errorf("serve = %d %q, want TLS_CONFIGURATION_ERROR", code, stderr)
		}
		if _, err := os.Stat(c.vars["TLS_KEY_FILE"]); err == nil {
			t.Error("the key file must not be generated")
		}
	})
}

func TestHealthcheckWithoutServerFails(t *testing.T) {
	t.Parallel()
	c := newCLIEnv(t)
	if _, err := tlscert.LoadOrGenerate(tlscert.Options{CertFile: c.vars["TLS_CERT_FILE"], KeyFile: c.vars["TLS_KEY_FILE"], Name: "x"}); err != nil {
		t.Fatal(err)
	}
	c.vars["APP_LISTEN_ADDR"] = "127.0.0.1:1" // nothing listens here
	if code, _, stderr := c.run(t, "healthcheck"); code != exitError || stderr == "" {
		t.Errorf("healthcheck = %d %q", code, stderr)
	}
}
