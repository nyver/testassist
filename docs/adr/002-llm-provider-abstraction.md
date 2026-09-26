# 002. LLM provider abstraction

## Status

Accepted.

## Context

The product needs OpenRouter and RouterAI now and should let an operator add other OpenAI-compatible endpoints (Ollama, vLLM, LM Studio, OpenAI itself) without code changes. Prompt building and validation of the model's answer must not depend on a particular provider. `AGENTS.md` asks for small consumer-side interfaces and no speculative layers.

## Decision

- `internal/analysis` depends on a consumer-side interface with two methods: `Complete(ctx, ChatRequest) (ChatResponse, error)` and `ListModels(ctx) ([]Model, error)`.
- The adapter is a thin chat-level transport. Prompt construction, vision gating, JSON validation and confidence mapping live once in `internal/analysis`, so adding a provider never duplicates them. This deliberately differs from the product specification's `AnalyzeQuestion` adapter method.
- `internal/llm/openaicompat` is the only implementation. It talks to `POST {base_url}/chat/completions` and `GET {base_url}/models`.
- Providers are declared in configuration: id, display name, type (`openai-compatible`), base URL, name of the API-key environment variable, extra headers, default model, optional static models with capabilities and an optional `structured_output` mode. OpenRouter and RouterAI are part of the built-in defaults.
- A provider without an API key is disabled and not listed. A key is only ever read from the environment or a `<NAME>_FILE` secret file.
- Model capabilities come from the provider's `/models` listing (OpenRouter's `architecture.input_modalities`) and are overridden by configuration. Listings are cached with a TTL and fall back to the static models when the upstream call fails.
- Only transient failures (429, 502, 503, 504, connection reset) are retried, at most 3 attempts in total, with jittered backoff, all inside the single LLM timeout.
- Upstream errors are mapped to stable API error codes. Upstream bodies and keys are never forwarded to clients or logs.

## Consequences

- A new OpenAI-compatible provider is a configuration entry.
- A provider with a different wire format needs a new adapter behind the same interface, and nothing else changes.
- Providers differ in support for `response_format`, so structured output is an opt-in per provider or model. Strict server-side validation of the output is the real guarantee.
- Model fallback between providers is not implemented in this change.
