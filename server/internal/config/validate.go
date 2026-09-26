package config

import (
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strings"
)

var (
	providerIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)
	envNamePattern    = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
)

func validEnvName(s string) bool { return envNamePattern.MatchString(s) }

// Validate checks the configuration and reports every problem, each naming the
// offending key. Values of secret-bearing keys are never echoed.
func (c *Config) Validate() error {
	var errs []error
	bad := func(format string, args ...any) {
		errs = append(errs, fmt.Errorf("config: "+format, args...))
	}

	if strings.TrimSpace(c.Server.Name) == "" {
		bad("server.name must not be empty")
	}
	if c.Server.Listen == "" {
		bad("server.listen must not be empty")
	}
	if c.Server.DataDir == "" {
		bad("server.data_dir must not be empty")
	}
	if c.TLS.CertFile == "" {
		bad("tls.cert_file must not be empty")
	}
	if c.TLS.KeyFile == "" {
		bad("tls.key_file must not be empty")
	}
	for i, h := range c.TLS.SelfSignedHosts {
		if strings.TrimSpace(h) == "" || strings.ContainsAny(h, " \t/") {
			bad("tls.self_signed_hosts[%d] must be a host name or IP address", i)
		}
	}

	positiveDuration := func(key string, d int64) {
		if d <= 0 {
			bad("%s must be positive", key)
		}
	}
	positiveDuration("timeouts.connect", int64(c.Timeouts.Connect))
	positiveDuration("timeouts.request", int64(c.Timeouts.Request))
	positiveDuration("timeouts.llm", int64(c.Timeouts.LLM))
	positiveDuration("timeouts.read_header", int64(c.Timeouts.ReadHeader))
	positiveDuration("timeouts.read", int64(c.Timeouts.Read))
	positiveDuration("timeouts.idle", int64(c.Timeouts.Idle))
	positiveDuration("timeouts.shutdown", int64(c.Timeouts.Shutdown))
	positiveDuration("llm.models_cache_ttl", int64(c.LLM.ModelsCacheTTL))

	if c.Limits.MaxRequestBytes <= 0 {
		bad("limits.max_request_bytes must be positive")
	}
	if c.Limits.MaxImageBytes <= 0 {
		bad("limits.max_image_bytes must be positive")
	}
	if c.Limits.MaxRequestBytes > 0 && c.Limits.MaxImageBytes > c.Limits.MaxRequestBytes {
		bad("limits.max_image_bytes must not exceed limits.max_request_bytes")
	}
	if c.LLM.MaxTokens <= 0 {
		bad("llm.max_tokens must be positive")
	}
	if c.LLM.MaxUpstreamBodyBytes <= 0 {
		bad("llm.max_upstream_body_bytes must be positive")
	}

	validateRate := func(key string, r RateConfig) {
		if r.RequestsPerMinute <= 0 {
			bad("%s.requests_per_minute must be positive", key)
		}
		if r.Burst <= 0 {
			bad("%s.burst must be positive", key)
		}
	}
	validateRate("rate_limit.general", c.RateLimit.General)
	validateRate("rate_limit.analyze", c.RateLimit.Analyze)

	inRange := func(v float64) bool { return v >= 0 && v <= 1 }
	if !inRange(c.Confidence.High) {
		bad("confidence.high must be between 0.0 and 1.0")
	}
	if !inRange(c.Confidence.Medium) {
		bad("confidence.medium must be between 0.0 and 1.0")
	}
	if c.Confidence.High <= c.Confidence.Medium {
		bad("confidence.high (%v) must be greater than confidence.medium (%v)",
			c.Confidence.High, c.Confidence.Medium)
	}

	errs = append(errs, c.validateProviders()...)
	return errors.Join(errs...)
}

func (c *Config) validateProviders() []error {
	var errs []error
	bad := func(format string, args ...any) {
		errs = append(errs, fmt.Errorf("config: "+format, args...))
	}

	seen := make(map[string]bool, len(c.LLM.Providers))
	for i := range c.LLM.Providers {
		p := &c.LLM.Providers[i]
		key := fmt.Sprintf("llm.providers[%d]", i)
		if !providerIDPattern.MatchString(p.ID) {
			bad("%s.id must match %s", key, providerIDPattern)
			continue
		}
		key = "provider " + p.ID
		if seen[p.ID] {
			bad("%s is declared more than once", key)
		}
		seen[p.ID] = true

		if p.Type != ProviderTypeOpenAICompatible {
			bad("%s: unsupported type %q (supported: %s)", key, p.Type, ProviderTypeOpenAICompatible)
		}
		if u, err := url.Parse(p.BaseURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			bad("%s: base_url must be an absolute http(s) URL", key)
		}
		if p.APIKeyEnv != "" && !validEnvName(p.APIKeyEnv) {
			// Do not echo the value: a pasted API key must not reach the logs.
			bad("%s: api_key_env must be an environment variable name, not a key", key)
		}
		if !validStructuredOutput(p.StructuredOutput) {
			bad("%s: structured_output must be one of none, json_object, json_schema", key)
		}
		modelIDs := make(map[string]bool, len(p.Models))
		for j, m := range p.Models {
			if strings.TrimSpace(m.ID) == "" {
				bad("%s: models[%d].id must not be empty", key, j)
				continue
			}
			if modelIDs[m.ID] {
				bad("%s: model %q is declared more than once", key, m.ID)
			}
			modelIDs[m.ID] = true
			if !validStructuredOutput(m.StructuredOutput) {
				bad("%s: model %q: structured_output must be one of none, json_object, json_schema", key, m.ID)
			}
		}
	}

	if !seen[c.LLM.DefaultProvider] {
		bad("llm.default_provider %q is not a configured provider", c.LLM.DefaultProvider)
	}
	return errs
}

func validStructuredOutput(s string) bool {
	switch s {
	case "", StructuredOutputNone, StructuredOutputJSONObject, StructuredOutputJSONSchema:
		return true
	}
	return false
}
