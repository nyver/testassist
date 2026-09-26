package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"go.yaml.in/yaml/v3"
)

// Environment variable names that override configuration values.
const (
	EnvListenAddr = "APP_LISTEN_ADDR"
	EnvTLSCert    = "TLS_CERT_FILE"
	EnvTLSKey     = "TLS_KEY_FILE"
	EnvDataDir    = "DATA_DIR"
	EnvServerName = "SERVER_NAME"
	EnvAuthToken  = "AUTH_TOKEN"
)

// Env is the source of environment variables. Tests inject a map-backed one.
type Env func(key string) string

// OSEnv reads the real process environment.
func OSEnv(key string) string { return os.Getenv(key) }

// Load builds the configuration from defaults, the optional YAML file at path
// (empty means none) and the environment, then validates it.
func Load(path string, getenv Env) (*Config, error) {
	cfg := Default()
	builtin := cfg.LLM.Providers
	cfg.LLM.Providers = nil

	if path != "" {
		if err := loadFile(path, &cfg); err != nil {
			return nil, err
		}
	}
	cfg.LLM.Providers = mergeProviders(builtin, cfg.LLM.Providers)

	if err := applyEnv(&cfg, getenv); err != nil {
		return nil, err
	}
	normalize(&cfg)
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func loadFile(path string, cfg *Config) error {
	data, err := os.ReadFile(path) // #nosec G304 -- the operator chooses the config path.
	if err != nil {
		return fmt.Errorf("config: read %s: %w", path, err)
	}

	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return fmt.Errorf("config: parse %s: %w", path, err)
	}
	if unknown := unknownKeys(&doc, cfg); len(unknown) > 0 {
		return fmt.Errorf("config: unknown key(s) in %s: %s", path, strings.Join(unknown, ", "))
	}

	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(cfg); err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("config: parse %s: %w", path, err)
	}
	return nil
}

// mergeProviders overlays file-declared providers on the built-in ones by id.
// Non-zero fields of a matching entry replace the built-in values, and entries
// with a new id are appended.
func mergeProviders(builtin, declared []ProviderConfig) []ProviderConfig {
	merged := append([]ProviderConfig(nil), builtin...)
	for _, d := range declared {
		idx := -1
		for i := range merged {
			if merged[i].ID == d.ID {
				idx = i
				break
			}
		}
		if idx < 0 {
			merged = append(merged, d)
			continue
		}
		overlayProvider(&merged[idx], d)
	}
	return merged
}

func overlayProvider(dst *ProviderConfig, src ProviderConfig) {
	if src.Name != "" {
		dst.Name = src.Name
	}
	if src.Type != "" {
		dst.Type = src.Type
	}
	if src.BaseURL != "" {
		dst.BaseURL = src.BaseURL
	}
	if src.APIKeyEnv != "" {
		dst.APIKeyEnv = src.APIKeyEnv
	}
	if src.Headers != nil {
		dst.Headers = src.Headers
	}
	if src.DefaultModel != "" {
		dst.DefaultModel = src.DefaultModel
	}
	if src.StructuredOutput != "" {
		dst.StructuredOutput = src.StructuredOutput
	}
	if src.Models != nil {
		dst.Models = src.Models
	}
}

func applyEnv(cfg *Config, getenv Env) error {
	if v := getenv(EnvListenAddr); v != "" {
		cfg.Server.Listen = v
	}
	if v := getenv(EnvTLSCert); v != "" {
		cfg.TLS.CertFile = v
	}
	if v := getenv(EnvTLSKey); v != "" {
		cfg.TLS.KeyFile = v
	}
	if v := getenv(EnvDataDir); v != "" {
		cfg.Server.DataDir = v
	}
	if v := getenv(EnvServerName); v != "" {
		cfg.Server.Name = v
	}

	token, err := ResolveSecret(getenv, EnvAuthToken)
	if err != nil {
		return err
	}
	cfg.Security.AuthToken = token

	for i := range cfg.LLM.Providers {
		p := &cfg.LLM.Providers[i]
		if !validEnvName(p.APIKeyEnv) && p.APIKeyEnv != "" {
			// Skipped here; Validate reports it without echoing the value,
			// which may be a pasted secret.
			continue
		}
		if p.APIKeyEnv == "" {
			p.Enabled = true
			continue
		}
		key, err := ResolveSecret(getenv, p.APIKeyEnv)
		if err != nil {
			return err
		}
		p.APIKey = key
		p.Enabled = key != ""
	}
	return nil
}

// ResolveSecret returns the value of NAME or, when that is empty, the trimmed
// content of the file named by NAME_FILE (Docker secrets). It returns an empty
// string when neither is set.
func ResolveSecret(getenv Env, name string) (string, error) {
	if v := getenv(name); v != "" {
		return v, nil
	}
	fileVar := name + "_FILE"
	path := getenv(fileVar)
	if path == "" {
		return "", nil
	}
	data, err := os.ReadFile(path) // #nosec G304 -- path comes from the operator's environment.
	if err != nil {
		return "", fmt.Errorf("config: read secret file named by %s: %w", fileVar, err)
	}
	return strings.TrimSpace(string(data)), nil
}

func normalize(cfg *Config) {
	for i := range cfg.LLM.Providers {
		p := &cfg.LLM.Providers[i]
		p.BaseURL = strings.TrimRight(p.BaseURL, "/")
		if p.Name == "" {
			p.Name = p.ID
		}
		if p.StructuredOutput == "" {
			p.StructuredOutput = StructuredOutputNone
		}
	}
}

// DefaultProvider returns the provider used when a request names none: the
// configured default when it is enabled, otherwise the first enabled provider.
// The boolean is false when no provider is enabled.
func (c *Config) DefaultProvider() (ProviderConfig, bool) {
	var first *ProviderConfig
	for i := range c.LLM.Providers {
		p := &c.LLM.Providers[i]
		if !p.Enabled {
			continue
		}
		if p.ID == c.LLM.DefaultProvider {
			return *p, true
		}
		if first == nil {
			first = p
		}
	}
	if first != nil {
		return *first, true
	}
	return ProviderConfig{}, false
}
