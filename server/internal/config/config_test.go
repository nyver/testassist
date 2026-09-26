package config

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func mapEnv(m map[string]string) Env {
	return func(k string) string { return m[k] }
}

func writeFile(t *testing.T, name, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func providerByID(t *testing.T, c *Config, id string) ProviderConfig {
	t.Helper()
	for _, p := range c.LLM.Providers {
		if p.ID == id {
			return p
		}
	}
	t.Fatalf("provider %q not found", id)
	return ProviderConfig{}
}

func TestLoadDefaultsWithoutFile(t *testing.T) {
	t.Parallel()

	cfg, err := Load("", mapEnv(map[string]string{
		"OPENROUTER_API_KEY": "or-key",
		"ROUTERAI_API_KEY":   "ra-key",
	}))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.Server.Listen; got != ":8447" {
		t.Errorf("listen = %q, want :8447", got)
	}
	if cfg.Timeouts.Connect != 10*time.Second || cfg.Timeouts.Request != 60*time.Second || cfg.Timeouts.LLM != 45*time.Second {
		t.Errorf("unexpected default timeouts: %+v", cfg.Timeouts)
	}
	if cfg.Limits.MaxRequestBytes != 8<<20 || cfg.Limits.MaxImageBytes != 5<<20 {
		t.Errorf("unexpected default limits: %+v", cfg.Limits)
	}
	for _, id := range []string{"openrouter", "routerai"} {
		p := providerByID(t, cfg, id)
		if !p.Enabled || p.APIKey == "" {
			t.Errorf("provider %s should be enabled with its key", id)
		}
	}
	if def, ok := cfg.DefaultProvider(); !ok || def.ID != "openrouter" {
		t.Errorf("default provider = %q, %v", def.ID, ok)
	}
}

func TestLoadPrecedence(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		yaml string
		env  map[string]string
		want func(*testing.T, *Config)
	}{
		{
			name: "environment overrides file",
			yaml: "server:\n  listen: \":9443\"\n",
			env:  map[string]string{"APP_LISTEN_ADDR": ":8444"},
			want: func(t *testing.T, c *Config) {
				if c.Server.Listen != ":8444" {
					t.Errorf("listen = %q, want :8444", c.Server.Listen)
				}
			},
		},
		{
			name: "file overrides default",
			yaml: "server:\n  listen: \":9443\"\n",
			want: func(t *testing.T, c *Config) {
				if c.Server.Listen != ":9443" {
					t.Errorf("listen = %q, want :9443", c.Server.Listen)
				}
			},
		},
		{
			name: "all environment overrides",
			env: map[string]string{
				"TLS_CERT_FILE": "/c/a.crt",
				"TLS_KEY_FILE":  "/c/a.key",
				"DATA_DIR":      "/var/ta",
				"SERVER_NAME":   "Lab",
				"AUTH_TOKEN":    "tok",
			},
			want: func(t *testing.T, c *Config) {
				if c.TLS.CertFile != "/c/a.crt" || c.TLS.KeyFile != "/c/a.key" ||
					c.Server.DataDir != "/var/ta" || c.Server.Name != "Lab" || c.Security.AuthToken != "tok" {
					t.Errorf("env overrides not applied: %+v", c)
				}
			},
		},
		{
			name: "durations and limits from file",
			yaml: "timeouts:\n  llm: 90s\nlimits:\n  max_image_bytes: 1048576\n",
			want: func(t *testing.T, c *Config) {
				if c.Timeouts.LLM != 90*time.Second || c.Limits.MaxImageBytes != 1<<20 {
					t.Errorf("file values not applied: %+v %+v", c.Timeouts, c.Limits)
				}
			},
		},
		{
			name: "file partially overrides a built-in provider",
			yaml: "llm:\n  providers:\n    - id: openrouter\n      default_model: vendor/model\n",
			env:  map[string]string{"OPENROUTER_API_KEY": "k"},
			want: func(t *testing.T, c *Config) {
				p := providerByID(t, c, "openrouter")
				if p.DefaultModel != "vendor/model" {
					t.Errorf("default model = %q", p.DefaultModel)
				}
				if p.BaseURL != "https://openrouter.ai/api/v1" || p.Type != ProviderTypeOpenAICompatible {
					t.Errorf("built-in fields were lost: %+v", p)
				}
				if len(c.LLM.Providers) != 2 {
					t.Errorf("provider count = %d, want 2", len(c.LLM.Providers))
				}
			},
		},
		{
			name: "custom provider without key is enabled",
			yaml: "llm:\n  providers:\n    - id: local\n      type: openai-compatible\n      base_url: http://ollama:11434/v1/\n      models:\n        - id: llama3\n          vision: false\n",
			want: func(t *testing.T, c *Config) {
				p := providerByID(t, c, "local")
				if !p.Enabled {
					t.Error("provider without api_key_env should be enabled")
				}
				if p.BaseURL != "http://ollama:11434/v1" {
					t.Errorf("base URL not normalized: %q", p.BaseURL)
				}
				if p.Name != "local" {
					t.Errorf("name should default to id, got %q", p.Name)
				}
				if len(p.Models) != 1 || p.Models[0].Vision == nil || *p.Models[0].Vision {
					t.Errorf("static model not parsed: %+v", p.Models)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			path := ""
			if tt.yaml != "" {
				path = writeFile(t, "config.yaml", tt.yaml)
			}
			cfg, err := Load(path, mapEnv(tt.env))
			if err != nil {
				t.Fatalf("Load: %v", err)
			}
			tt.want(t, cfg)
		})
	}
}

func TestLoadRejectsUnknownKeys(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		yaml string
		want string
	}{
		{"top-level section", "servr:\n  name: x\n", "servr"},
		{"nested key", "server:\n  lisen: \":9443\"\n", "server.lisen"},
		{"provider key", "llm:\n  providers:\n    - id: local\n      api_key: secret\n", "llm.providers[0].api_key"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Load(writeFile(t, "config.yaml", tt.yaml), mapEnv(nil))
			if err == nil {
				t.Fatal("expected an error")
			}
			if !strings.Contains(err.Error(), tt.want) {
				t.Errorf("error %q does not name %q", err, tt.want)
			}
			if strings.Contains(err.Error(), "secret") {
				t.Errorf("error leaks the value: %q", err)
			}
		})
	}
}

func TestLoadMissingFile(t *testing.T) {
	t.Parallel()
	if _, err := Load(filepath.Join(t.TempDir(), "absent.yaml"), mapEnv(nil)); err == nil {
		t.Fatal("expected an error for a missing config file")
	}
}

func TestSecretFiles(t *testing.T) {
	t.Parallel()

	t.Run("key from file", func(t *testing.T) {
		t.Parallel()
		keyFile := writeFile(t, "key", "file-key\r\n")
		cfg, err := Load("", mapEnv(map[string]string{"OPENROUTER_API_KEY_FILE": keyFile}))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		p := providerByID(t, cfg, "openrouter")
		if p.APIKey != "file-key" || !p.Enabled {
			t.Errorf("key = %q enabled = %v", p.APIKey, p.Enabled)
		}
	})

	t.Run("plain variable wins over file", func(t *testing.T) {
		t.Parallel()
		keyFile := writeFile(t, "key", "file-key")
		cfg, err := Load("", mapEnv(map[string]string{
			"OPENROUTER_API_KEY":      "env-key",
			"OPENROUTER_API_KEY_FILE": keyFile,
		}))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if got := providerByID(t, cfg, "openrouter").APIKey; got != "env-key" {
			t.Errorf("key = %q, want env-key", got)
		}
	})

	t.Run("auth token from file", func(t *testing.T) {
		t.Parallel()
		tokFile := writeFile(t, "tok", "abc\n")
		cfg, err := Load("", mapEnv(map[string]string{"AUTH_TOKEN_FILE": tokFile}))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if cfg.Security.AuthToken != "abc" {
			t.Errorf("token = %q", cfg.Security.AuthToken)
		}
	})

	t.Run("unreadable secret file", func(t *testing.T) {
		t.Parallel()
		missing := filepath.Join(t.TempDir(), "absent")
		_, err := Load("", mapEnv(map[string]string{"OPENROUTER_API_KEY_FILE": missing}))
		if err == nil || !strings.Contains(err.Error(), "OPENROUTER_API_KEY_FILE") {
			t.Errorf("error = %v, want mention of OPENROUTER_API_KEY_FILE", err)
		}
	})
}

func TestDisabledProviders(t *testing.T) {
	t.Parallel()

	t.Run("missing key disables provider", func(t *testing.T) {
		t.Parallel()
		cfg, err := Load("", mapEnv(map[string]string{"OPENROUTER_API_KEY": "k"}))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if providerByID(t, cfg, "routerai").Enabled {
			t.Error("routerai should be disabled without a key")
		}
	})

	t.Run("default falls back to first enabled provider", func(t *testing.T) {
		t.Parallel()
		cfg, err := Load("", mapEnv(map[string]string{"ROUTERAI_API_KEY": "k"}))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if def, ok := cfg.DefaultProvider(); !ok || def.ID != "routerai" {
			t.Errorf("default = %q, %v; want routerai", def.ID, ok)
		}
	})

	t.Run("no provider enabled is not a config error", func(t *testing.T) {
		t.Parallel()
		cfg, err := Load("", mapEnv(nil))
		if err != nil {
			t.Fatalf("Load: %v", err)
		}
		if _, ok := cfg.DefaultProvider(); ok {
			t.Error("expected no default provider")
		}
	})
}

func TestValidationErrors(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		yaml string
		want string
	}{
		{"unsupported provider type", "llm:\n  providers:\n    - id: native\n      type: anthropic-native\n      base_url: https://x.example/v1\n", "provider native: unsupported type"},
		{"default provider missing", "llm:\n  default_provider: nope\n", "llm.default_provider"},
		{"threshold order", "confidence:\n  high: 0.5\n  medium: 0.6\n", "confidence.high"},
		{"equal thresholds", "confidence:\n  high: 0.6\n  medium: 0.6\n", "confidence.high"},
		{"threshold range", "confidence:\n  high: 1.5\n", "confidence.high must be between"},
		{"negative timeout", "timeouts:\n  llm: -1s\n", "timeouts.llm"},
		{"zero request limit", "limits:\n  max_request_bytes: 0\n", "limits.max_request_bytes"},
		{"image larger than request", "limits:\n  max_request_bytes: 1000\n  max_image_bytes: 2000\n", "limits.max_image_bytes"},
		{"zero burst", "rate_limit:\n  analyze:\n    burst: 0\n", "rate_limit.analyze.burst"},
		{"bad base url", "llm:\n  providers:\n    - id: bad\n      type: openai-compatible\n      base_url: not-a-url\n", "provider bad: base_url"},
		{"bad structured output", "llm:\n  providers:\n    - id: openrouter\n      structured_output: xml\n", "structured_output"},
		{"bad provider id", "llm:\n  providers:\n    - id: Bad Id\n      type: openai-compatible\n      base_url: https://x.example\n", "llm.providers[2].id"},
		{"duplicate static model", "llm:\n  providers:\n    - id: openrouter\n      models:\n        - id: m\n        - id: m\n", "declared more than once"},
		{"bad self signed host", "tls:\n  self_signed_hosts: [\"a b\"]\n", "tls.self_signed_hosts[0]"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Load(writeFile(t, "config.yaml", tt.yaml), mapEnv(nil))
			if err == nil {
				t.Fatal("expected a validation error")
			}
			if !strings.Contains(err.Error(), tt.want) {
				t.Errorf("error %q does not contain %q", err, tt.want)
			}
		})
	}
}

func TestAPIKeyEnvPastedSecretIsNotEchoed(t *testing.T) {
	t.Parallel()

	const pasted = "sk-or-v1-supersecretvalue"
	yamlDoc := "llm:\n  providers:\n    - id: openrouter\n      api_key_env: " + pasted + "\n"
	_, err := Load(writeFile(t, "config.yaml", yamlDoc), mapEnv(nil))
	if err == nil {
		t.Fatal("expected a validation error")
	}
	if strings.Contains(err.Error(), pasted) {
		t.Errorf("error echoes the pasted secret: %v", err)
	}
	if !strings.Contains(err.Error(), "api_key_env") {
		t.Errorf("error should name api_key_env: %v", err)
	}
}

func TestEmptyFileUsesDefaults(t *testing.T) {
	t.Parallel()
	cfg, err := Load(writeFile(t, "config.yaml", ""), mapEnv(nil))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.Server.Listen != ":8447" {
		t.Errorf("listen = %q", cfg.Server.Listen)
	}
}

func TestExampleConfigMatchesDefaults(t *testing.T) {
	t.Parallel()

	got, err := Load(filepath.Join("..", "..", "..", "config.example.yaml"), mapEnv(nil))
	if err != nil {
		t.Fatalf("Load example: %v", err)
	}
	want, err := Load("", mapEnv(nil))
	if err != nil {
		t.Fatalf("Load defaults: %v", err)
	}
	// Empty-vs-nil slices and maps are irrelevant differences.
	if len(got.TLS.SelfSignedHosts) == 0 {
		got.TLS.SelfSignedHosts = nil
	}
	for i := range got.LLM.Providers {
		got.LLM.Providers[i].Models = nil
		if len(got.LLM.Providers[i].Headers) == 0 {
			got.LLM.Providers[i].Headers = nil
		}
	}
	for i := range want.LLM.Providers {
		want.LLM.Providers[i].Models = nil
		if len(want.LLM.Providers[i].Headers) == 0 {
			want.LLM.Providers[i].Headers = nil
		}
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("config.example.yaml drifted from the built-in defaults:\n got: %+v\nwant: %+v", got, want)
	}
}
