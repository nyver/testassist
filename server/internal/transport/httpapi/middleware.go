package httpapi

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"runtime/debug"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/nyver/test-assistant/server/internal/apierr"
)

// statusClientClosedRequest is logged when the client disconnects before the
// server answers. It is never sent on the wire.
const statusClientClosedRequest = 499

// maxLoggedPath bounds the logged path, which is attacker-controlled on 404s.
const maxLoggedPath = 200

var requestIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// statusWriter records the status code and whether the response has started.
type statusWriter struct {
	http.ResponseWriter
	status  int
	written bool
}

func (w *statusWriter) WriteHeader(code int) {
	if !w.written {
		w.status = code
		w.written = true
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if !w.written {
		w.status = http.StatusOK
		w.written = true
	}
	return w.ResponseWriter.Write(b)
}

// Unwrap lets http.ResponseController reach the underlying writer.
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// requestIDMiddleware assigns the request id, accepting a client-supplied one
// only if it is at most 64 characters of [A-Za-z0-9_-], and returns it in the
// X-Request-ID response header.
func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if !requestIDPattern.MatchString(id) {
			id = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", id)
		ctx := context.WithValue(r.Context(), stateKey{}, &requestState{id: id})
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// accessLogMiddleware writes exactly one structured log entry per request,
// after it completes. It logs only allow-listed fields: never headers, query
// strings, bodies, tokens or user content.
func accessLogMiddleware(log *slog.Logger, now func() time.Time, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)

		st := stateFrom(r.Context())
		status := sw.status
		if !sw.written && r.Context().Err() != nil {
			status = statusClientClosedRequest
		}

		attrs := []slog.Attr{
			slog.String("request_id", st.id),
			slog.String("method", r.Method),
			slog.String("path", loggedPath(r)),
			slog.Int("status", status),
			slog.Int64("duration_ms", now().Sub(start).Milliseconds()),
		}
		if st.provider != "" {
			attrs = append(attrs, slog.String("provider", st.provider))
		}
		if st.model != "" {
			attrs = append(attrs, slog.String("model", st.model))
		}
		if st.errCode != "" {
			attrs = append(attrs, slog.String("error_code", string(st.errCode)))
		}
		if st.errCause != nil {
			attrs = append(attrs, slog.String("error", st.errCause.Error()))
		}
		log.LogAttrs(r.Context(), levelFor(status), "request", attrs...)
	})
}

func levelFor(status int) slog.Level {
	switch {
	case status == http.StatusInternalServerError:
		return slog.LevelError
	case status >= http.StatusInternalServerError:
		return slog.LevelWarn
	default:
		return slog.LevelInfo
	}
}

func loggedPath(r *http.Request) string {
	p := r.URL.Path
	if len(p) > maxLoggedPath {
		p = p[:maxLoggedPath]
	}
	return p
}

// recoverMiddleware turns a panic into a 500 error envelope. It sits below the
// request-id and access-log middleware so the response carries the request id
// and the failure is logged exactly once.
func recoverMiddleware(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer recoverPanic(log, w, r)
		next.ServeHTTP(w, r)
	})
}

// recoverPanic must be deferred directly: recover only works there.
func recoverPanic(log *slog.Logger, w http.ResponseWriter, r *http.Request) {
	rec := recover()
	if rec == nil {
		return
	}
	if rec == http.ErrAbortHandler {
		panic(rec)
	}
	log.ErrorContext(r.Context(), "panic while serving request",
		slog.String("request_id", RequestID(r.Context())),
		slog.Any("panic", rec),
		slog.String("stack", string(debug.Stack())))
	if sw, ok := w.(*statusWriter); ok && sw.written {
		return // too late to change the response
	}
	writeError(w, r, apierr.New(apierr.Internal, "Internal server error."))
}

// authMiddleware requires "Authorization: Bearer <token>". Tokens are compared
// in constant time by comparing fixed-length digests.
func authMiddleware(token string, next http.Handler) http.Handler {
	want := sha256.Sum256([]byte(token))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got, ok := bearerToken(r)
		gotSum := sha256.Sum256([]byte(got))
		if !ok || subtle.ConstantTimeCompare(gotSum[:], want[:]) != 1 {
			w.Header().Set("WWW-Authenticate", `Bearer realm="test-assistant"`)
			writeError(w, r, apierr.New(apierr.Unauthorized, "Missing or invalid bearer token."))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const prefix = "bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return "", false
	}
	return strings.TrimSpace(h[len(prefix):]), true
}

// bodyLimitMiddleware caps the request body. A declared oversized length is
// rejected before anything is read; otherwise reading stops at the limit.
func bodyLimitMiddleware(maxBytes int64, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ContentLength > maxBytes {
			writeError(w, r, apierr.New(apierr.ImageTooLarge, "Request body exceeds the maximum allowed size."))
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
		next.ServeHTTP(w, r)
	})
}

// timeoutMiddleware bounds the handler with the request timeout.
func timeoutMiddleware(d time.Duration, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), d)
		defer cancel()
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// isMaxBytes reports whether err comes from exceeding the body limit.
func isMaxBytes(err error) bool {
	var mbe *http.MaxBytesError
	return errors.As(err, &mbe)
}
