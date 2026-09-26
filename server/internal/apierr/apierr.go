// Package apierr defines the stable error codes of the HTTP API and the typed
// error that carries a code from the use-case layer to the transport layer.
package apierr

import (
	"errors"
	"net/http"
	"time"
)

// Code is a stable, machine-readable API error code.
type Code string

// API error codes. NotFound is not in the specification's table; it is the code
// of the 404 envelope for unknown routes, for which the table has none.
const (
	InvalidRequest            Code = "INVALID_REQUEST"
	Unauthorized              Code = "UNAUTHORIZED"
	NotFound                  Code = "NOT_FOUND"
	ProviderNotFound          Code = "PROVIDER_NOT_FOUND"
	ModelNotFound             Code = "MODEL_NOT_FOUND"
	ImageTooLarge             Code = "IMAGE_TOO_LARGE"
	UnsupportedImageType      Code = "UNSUPPORTED_IMAGE_TYPE"
	ModelDoesNotSupportVision Code = "MODEL_DOES_NOT_SUPPORT_VISION"
	RateLimited               Code = "RATE_LIMITED"
	Internal                  Code = "INTERNAL_ERROR"
	LLMProviderUnavailable    Code = "LLM_PROVIDER_UNAVAILABLE"
	LLMInvalidResponse        Code = "LLM_INVALID_RESPONSE"
	LLMTimeout                Code = "LLM_TIMEOUT"
)

// Status returns the HTTP status for the code.
func (c Code) Status() int {
	switch c {
	case InvalidRequest:
		return http.StatusBadRequest
	case Unauthorized:
		return http.StatusUnauthorized
	case NotFound, ProviderNotFound, ModelNotFound:
		return http.StatusNotFound
	case ImageTooLarge:
		return http.StatusRequestEntityTooLarge
	case UnsupportedImageType:
		return http.StatusUnsupportedMediaType
	case ModelDoesNotSupportVision:
		return http.StatusUnprocessableEntity
	case RateLimited:
		return http.StatusTooManyRequests
	case Internal:
		return http.StatusInternalServerError
	case LLMProviderUnavailable, LLMInvalidResponse:
		return http.StatusBadGateway
	case LLMTimeout:
		return http.StatusGatewayTimeout
	default:
		return http.StatusInternalServerError
	}
}

// All lists every code, in the order of the specification.
func All() []Code {
	return []Code{
		InvalidRequest, Unauthorized, NotFound, ProviderNotFound, ModelNotFound, ImageTooLarge,
		UnsupportedImageType, ModelDoesNotSupportVision, RateLimited, Internal,
		LLMProviderUnavailable, LLMInvalidResponse, LLMTimeout,
	}
}

// Error is an API-level failure. Message is safe to show to clients: it is
// English text without secrets, upstream bodies or user content. Cause carries
// the underlying error for logging and is never sent to clients.
type Error struct {
	Code    Code
	Message string
	// RetryAfter, when positive, becomes the Retry-After response header.
	RetryAfter time.Duration
	Cause      error
}

func (e *Error) Error() string {
	if e.Cause != nil {
		return string(e.Code) + ": " + e.Message + ": " + e.Cause.Error()
	}
	return string(e.Code) + ": " + e.Message
}

// Unwrap exposes the cause to errors.Is and errors.As.
func (e *Error) Unwrap() error { return e.Cause }

// New returns an Error without a cause.
func New(code Code, message string) *Error {
	return &Error{Code: code, Message: message}
}

// Wrap returns an Error that records the underlying cause for logging.
func Wrap(code Code, message string, cause error) *Error {
	return &Error{Code: code, Message: message, Cause: cause}
}

// As extracts an *Error from err's chain.
func As(err error) (*Error, bool) {
	var e *Error
	if errors.As(err, &e) {
		return e, true
	}
	return nil, false
}
