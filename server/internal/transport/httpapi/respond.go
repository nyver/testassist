package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/nyver/test-assistant/server/internal/apierr"
)

// requestState is per-request data shared between middleware and handlers. It
// is written by one goroutine, the one serving the request.
type requestState struct {
	id       string
	provider string
	model    string
	errCode  apierr.Code
	errCause error
}

type stateKey struct{}

func stateFrom(ctx context.Context) *requestState {
	if s, ok := ctx.Value(stateKey{}).(*requestState); ok {
		return s
	}
	return &requestState{} // outside the middleware chain; discarded
}

// RequestID returns the id of the request being served, or "".
func RequestID(ctx context.Context) string { return stateFrom(ctx).id }

// errorEnvelope is the uniform body of every non-2xx API response.
type errorEnvelope struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code      apierr.Code `json:"code"`
	Message   string      `json:"message"`
	RequestID string      `json:"requestId"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		// Only our own types are encoded, so this is a programming error.
		http.Error(w, `{"error":{"code":"INTERNAL_ERROR","message":"Internal server error.","requestId":""}}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(append(body, '\n'))
}

// toAPIError classifies any error returned by a handler. Errors that are not
// API errors are internal: their text never reaches the client.
func toAPIError(err error) *apierr.Error {
	if e, ok := apierr.As(err); ok {
		return e
	}
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		return apierr.Wrap(apierr.ImageTooLarge, "Request body exceeds the maximum allowed size.", err)
	}
	return apierr.Wrap(apierr.Internal, "Internal server error.", err)
}

// writeError writes the error envelope and records the error in the request
// state so the access log can report it.
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	e := toAPIError(err)
	st := stateFrom(r.Context())
	st.errCode = e.Code
	st.errCause = e.Cause

	if e.RetryAfter > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(retryAfterSeconds(e.RetryAfter)))
	}
	writeJSON(w, e.Code.Status(), errorEnvelope{Error: errorBody{
		Code:      e.Code,
		Message:   e.Message,
		RequestID: st.id,
	}})
}

// retryAfterSeconds rounds up to whole seconds, with a minimum of one.
func retryAfterSeconds(d time.Duration) int {
	secs := int((d + time.Second - 1) / time.Second)
	return max(secs, 1)
}

// handlerFunc is an API handler that reports failures by returning them.
type handlerFunc func(w http.ResponseWriter, r *http.Request) error

// handle adapts a handlerFunc: a returned error becomes the error envelope,
// except a cancelled request, whose client is gone.
func handle(h handlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			if errors.Is(err, context.Canceled) && r.Context().Err() != nil {
				return
			}
			writeError(w, r, err)
		}
	})
}
