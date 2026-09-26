// Package config loads and validates the server configuration.
//
// Values are applied in this order: built-in defaults, an optional YAML file,
// then environment variables. Secrets are never stored in the YAML file; it
// only names the environment variable that holds them.
package config

import "time"

// Supported provider types and structured-output modes.
const (
	ProviderTypeOpenAICompatible = "openai-compatible"

	StructuredOutputNone       = "none"
	StructuredOutputJSONObject = "json_object"
	StructuredOutputJSONSchema = "json_schema"
)

// Config is the complete server configuration.
type Config struct {
	Server     ServerConfig     `yaml:"server"`
	TLS        TLSConfig        `yaml:"tls"`
	Security   SecurityConfig   `yaml:"security"`
	Timeouts   TimeoutsConfig   `yaml:"timeouts"`
	Limits     LimitsConfig     `yaml:"limits"`
	RateLimit  RateLimitConfig  `yaml:"rate_limit"`
	Confidence ConfidenceConfig `yaml:"confidence"`
	LLM        LLMConfig        `yaml:"llm"`
}

// ServerConfig holds identity and listener settings.
type ServerConfig struct {
	Name    string `yaml:"name"`
	Listen  string `yaml:"listen"`
	DataDir string `yaml:"data_dir"`
}

// TLSConfig points at the certificate files. When both are absent the server
// generates a self-signed certificate that covers SelfSignedHosts.
type TLSConfig struct {
	CertFile        string   `yaml:"cert_file"`
	KeyFile         string   `yaml:"key_file"`
	SelfSignedHosts []string `yaml:"self_signed_hosts"`
}

// SecurityConfig controls API authentication.
type SecurityConfig struct {
	AuthEnabled bool `yaml:"auth_enabled"`

	// AuthToken comes only from AUTH_TOKEN or AUTH_TOKEN_FILE. When set it
	// replaces the persisted token.
	AuthToken string `yaml:"-"`
}

// TimeoutsConfig groups every timeout the server applies.
type TimeoutsConfig struct {
	Connect    time.Duration `yaml:"connect"`
	Request    time.Duration `yaml:"request"`
	LLM        time.Duration `yaml:"llm"`
	ReadHeader time.Duration `yaml:"read_header"`
	Read       time.Duration `yaml:"read"`
	Idle       time.Duration `yaml:"idle"`
	Shutdown   time.Duration `yaml:"shutdown"`
}

// LimitsConfig bounds request sizes.
type LimitsConfig struct {
	MaxRequestBytes int64 `yaml:"max_request_bytes"`
	MaxImageBytes   int64 `yaml:"max_image_bytes"`
}

// RateLimitConfig holds the per-client-IP limits.
type RateLimitConfig struct {
	General RateConfig `yaml:"general"`
	Analyze RateConfig `yaml:"analyze"`
}

// RateConfig is one token bucket.
type RateConfig struct {
	RequestsPerMinute float64 `yaml:"requests_per_minute"`
	Burst             int     `yaml:"burst"`
}

// ConfidenceConfig holds the thresholds that map a numeric confidence to a
// level: at least High is "high", at least Medium is "medium", else "low".
type ConfidenceConfig struct {
	High   float64 `yaml:"high"`
	Medium float64 `yaml:"medium"`
}

// LLMConfig holds provider-independent LLM settings and the provider list.
type LLMConfig struct {
	DefaultProvider      string           `yaml:"default_provider"`
	MaxTokens            int              `yaml:"max_tokens"`
	MaxUpstreamBodyBytes int64            `yaml:"max_upstream_body_bytes"`
	ModelsCacheTTL       time.Duration    `yaml:"models_cache_ttl"`
	Providers            []ProviderConfig `yaml:"providers"`
}

// ProviderConfig describes one LLM provider.
type ProviderConfig struct {
	ID               string            `yaml:"id"`
	Name             string            `yaml:"name"`
	Type             string            `yaml:"type"`
	BaseURL          string            `yaml:"base_url"`
	APIKeyEnv        string            `yaml:"api_key_env"`
	Headers          map[string]string `yaml:"headers"`
	DefaultModel     string            `yaml:"default_model"`
	StructuredOutput string            `yaml:"structured_output"`
	Models           []ModelConfig     `yaml:"models"`

	// APIKey is resolved from the environment and never appears in YAML.
	APIKey string `yaml:"-"`
	// Enabled is false when APIKeyEnv is set but no key was found. A provider
	// without APIKeyEnv (for example a local Ollama) needs no key.
	Enabled bool `yaml:"-"`
}

// ModelConfig is a statically declared model. Capability fields left nil do
// not override what the provider's model listing reports.
type ModelConfig struct {
	ID               string `yaml:"id"`
	Name             string `yaml:"name"`
	Text             *bool  `yaml:"text"`
	Vision           *bool  `yaml:"vision"`
	StructuredOutput string `yaml:"structured_output"`
}

// Default returns the built-in configuration, which already contains the
// OpenRouter and RouterAI providers.
func Default() Config {
	return Config{
		Server: ServerConfig{
			Name:    "Test Assistant",
			Listen:  ":8447",
			DataDir: "/data",
		},
		TLS: TLSConfig{
			CertFile: "/certs/server.crt",
			KeyFile:  "/certs/server.key",
		},
		Security: SecurityConfig{AuthEnabled: true},
		Timeouts: TimeoutsConfig{
			Connect:    10 * time.Second,
			Request:    60 * time.Second,
			LLM:        45 * time.Second,
			ReadHeader: 10 * time.Second,
			Read:       60 * time.Second,
			Idle:       120 * time.Second,
			Shutdown:   30 * time.Second,
		},
		Limits: LimitsConfig{
			MaxRequestBytes: 8 << 20,
			MaxImageBytes:   5 << 20,
		},
		RateLimit: RateLimitConfig{
			General: RateConfig{RequestsPerMinute: 30, Burst: 10},
			Analyze: RateConfig{RequestsPerMinute: 10, Burst: 3},
		},
		Confidence: ConfidenceConfig{High: 0.85, Medium: 0.60},
		LLM: LLMConfig{
			DefaultProvider:      "openrouter",
			MaxTokens:            1024,
			MaxUpstreamBodyBytes: 1 << 20,
			ModelsCacheTTL:       10 * time.Minute,
			Providers:            defaultProviders(),
		},
	}
}

// NOTE: the default model ids are unverified against the live RouterAI
// catalog. Operators can override them with a provider entry of the same id.
// #nosec G101 -- these are environment variable names, not credentials.
func defaultProviders() []ProviderConfig {
	return []ProviderConfig{
		{
			ID:               "openrouter",
			Name:             "OpenRouter",
			Type:             ProviderTypeOpenAICompatible,
			BaseURL:          "https://openrouter.ai/api/v1",
			APIKeyEnv:        "OPENROUTER_API_KEY",
			Headers:          map[string]string{"X-Title": "Test Assistant"},
			DefaultModel:     "openai/gpt-4o-mini",
			StructuredOutput: StructuredOutputNone,
		},
		{
			ID:               "routerai",
			Name:             "RouterAI",
			Type:             ProviderTypeOpenAICompatible,
			BaseURL:          "https://routerai.ru/api/v1",
			APIKeyEnv:        "ROUTERAI_API_KEY",
			DefaultModel:     "openai/gpt-4o-mini",
			StructuredOutput: StructuredOutputNone,
		},
	}
}
