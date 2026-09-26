// Package llm defines the provider-independent types used to talk to LLM
// backends, the error vocabulary adapters return, and the registry that turns
// configuration into usable providers with cached model listings.
package llm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// Capabilities describes what a model accepts as input.
type Capabilities struct {
	Text   bool
	Vision bool
}

// Model is one selectable model of a provider.
type Model struct {
	ID           string
	Name         string
	Capabilities Capabilities
	// StructuredOutput is the resolved response_format mode for this model:
	// none, json_object or json_schema.
	StructuredOutput string
}

// Image is an image attached to the user message.
type Image struct {
	// MIME is the sniffed content type, for example "image/jpeg".
	MIME string
	Data []byte
}

// ChatRequest is a single-turn chat completion: one system message and one
// user message that may carry an image.
type ChatRequest struct {
	Model  string
	System string
	User   string
	Image  *Image

	MaxTokens int
	// StructuredOutput selects the response_format sent upstream. Empty and
	// "none" send none.
	StructuredOutput string
	// ResponseSchema is the JSON schema used when StructuredOutput is
	// "json_schema".
	ResponseSchema json.RawMessage
}

// ChatResponse is the model's raw text reply. It is untrusted until the
// analysis layer has validated it.
type ChatResponse struct {
	Content string
}

// Provider is the transport to one LLM backend.
type Provider interface {
	Complete(ctx context.Context, req ChatRequest) (ChatResponse, error)
	ListModels(ctx context.Context) ([]Model, error)
}

// Error kinds. Adapters return an *Error whose Kind is one of these, so callers
// can classify failures with errors.Is and map them to API error codes.
var (
	// ErrTimeout means the deadline elapsed before the provider answered.
	ErrTimeout = errors.New("llm: request timed out")
	// ErrProviderUnavailable covers authentication failures, exhausted
	// retries, rejected requests and network errors.
	ErrProviderUnavailable = errors.New("llm: provider unavailable")
	// ErrModelNotFound means the provider does not know the model.
	ErrModelNotFound = errors.New("llm: model not found")
	// ErrInvalidResponse means the reply was malformed, empty or oversized.
	ErrInvalidResponse = errors.New("llm: invalid provider response")
)

// Error is a classified upstream failure. It never carries upstream response
// bodies or credentials, so it is safe to log.
type Error struct {
	Kind error
	// UpstreamStatus is the HTTP status of the provider's reply, or 0.
	UpstreamStatus int
	// Detail is a short, non-sensitive description.
	Detail string
	// Transient marks failures without an HTTP status that are worth retrying,
	// such as a connection reset.
	Transient bool
}

func (e *Error) Error() string {
	msg := e.Kind.Error()
	if e.UpstreamStatus != 0 {
		msg = fmt.Sprintf("%s (upstream status %d)", msg, e.UpstreamStatus)
	}
	if e.Detail != "" {
		msg += ": " + e.Detail
	}
	return msg
}

// Unwrap lets errors.Is match the Kind.
func (e *Error) Unwrap() error { return e.Kind }
