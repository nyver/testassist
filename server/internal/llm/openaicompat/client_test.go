package openaicompat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/llm"
)

const testKey = "sk-test-very-secret-key"

type fakeUpstream struct {
	srv      *httptest.Server
	requests atomic.Int32

	mu     sync.Mutex
	bodies []string
	header []http.Header
	paths  []string
}

func newUpstream(t *testing.T, handler func(n int, w http.ResponseWriter, r *http.Request)) *fakeUpstream {
	t.Helper()
	f := &fakeUpstream{}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := int(f.requests.Add(1))
		body, _ := io.ReadAll(r.Body)
		f.mu.Lock()
		f.bodies = append(f.bodies, string(body))
		f.header = append(f.header, r.Header.Clone())
		f.paths = append(f.paths, r.URL.Path)
		f.mu.Unlock()
		handler(n, w, r)
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeUpstream) count() int { return int(f.requests.Load()) }

func (f *fakeUpstream) body(i int) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.bodies[i]
}

// newClient returns a client whose sleeps are recorded instead of performed.
func newClient(t *testing.T, f *fakeUpstream, mutate ...func(*Options)) (*Client, *[]time.Duration) {
	t.Helper()
	opts := Options{
		BaseURL:        f.srv.URL,
		APIKey:         testKey,
		Headers:        map[string]string{"X-Title": "Test Assistant"},
		ConnectTimeout: 2 * time.Second,
		MaxBodyBytes:   1 << 20,
	}
	for _, m := range mutate {
		m(&opts)
	}
	c := New(opts)
	var sleeps []time.Duration
	c.sleep = func(_ context.Context, d time.Duration) error {
		sleeps = append(sleeps, d)
		return nil
	}
	c.jitter = func() float64 { return 0 }
	t.Cleanup(c.http.CloseIdleConnections)
	return c, &sleeps
}

func okReply(content string) string {
	b, _ := json.Marshal(map[string]any{
		"choices": []any{map[string]any{"message": map[string]any{"role": "assistant", "content": content}}},
	})
	return string(b)
}

func writeJSON(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = io.WriteString(w, body)
}

func basicRequest() llm.ChatRequest {
	return llm.ChatRequest{Model: "vendor/model", System: "sys", User: "usr", MaxTokens: 256}
}

func TestCompleteSuccessSendsExpectedRequest(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, okReply("hello")) })
	c, _ := newClient(t, up)

	resp, err := c.Complete(t.Context(), basicRequest())
	if err != nil {
		t.Fatalf("Complete: %v", err)
	}
	if resp.Content != "hello" {
		t.Errorf("content = %q", resp.Content)
	}

	if up.paths[0] != "/chat/completions" {
		t.Errorf("path = %q", up.paths[0])
	}
	h := up.header[0]
	if h.Get("Authorization") != "Bearer "+testKey || h.Get("X-Title") != "Test Assistant" || h.Get("Content-Type") != "application/json" {
		t.Errorf("headers = %v", h)
	}

	var got map[string]any
	if err := json.Unmarshal([]byte(up.body(0)), &got); err != nil {
		t.Fatal(err)
	}
	if got["model"] != "vendor/model" || got["max_tokens"] != float64(256) {
		t.Errorf("body = %v", got)
	}
	if _, has := got["response_format"]; has {
		t.Error("response_format must be absent by default")
	}
	msgs := got["messages"].([]any)
	if len(msgs) != 2 || msgs[0].(map[string]any)["content"] != "sys" || msgs[1].(map[string]any)["content"] != "usr" {
		t.Errorf("messages = %v", msgs)
	}
}

func TestCompleteWithoutAPIKeySendsNoAuthorization(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, okReply("x")) })
	c, _ := newClient(t, up, func(o *Options) { o.APIKey = "" })
	if _, err := c.Complete(t.Context(), basicRequest()); err != nil {
		t.Fatal(err)
	}
	if got := up.header[0].Get("Authorization"); got != "" {
		t.Errorf("Authorization = %q, want none", got)
	}
}

func TestCompleteImagePart(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, okReply("x")) })
	c, _ := newClient(t, up)
	req := basicRequest()
	req.Image = &llm.Image{MIME: "image/png", Data: []byte{1, 2, 3}}
	if _, err := c.Complete(t.Context(), req); err != nil {
		t.Fatal(err)
	}

	var got struct {
		Messages []struct {
			Content json.RawMessage `json:"content"`
		} `json:"messages"`
	}
	if err := json.Unmarshal([]byte(up.body(0)), &got); err != nil {
		t.Fatal(err)
	}
	var parts []struct {
		Type     string `json:"type"`
		Text     string `json:"text"`
		ImageURL struct {
			URL string `json:"url"`
		} `json:"image_url"`
	}
	if err := json.Unmarshal(got.Messages[1].Content, &parts); err != nil {
		t.Fatalf("user content is not a parts array: %s", got.Messages[1].Content)
	}
	if len(parts) != 2 || parts[0].Type != "text" || parts[0].Text != "usr" || parts[1].Type != "image_url" {
		t.Fatalf("parts = %+v", parts)
	}
	if parts[1].ImageURL.URL != "data:image/png;base64,AQID" {
		t.Errorf("image url = %q", parts[1].ImageURL.URL)
	}
}

func TestCompleteResponseFormat(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		mode string
		want string // substring of the request body, "" means absent
	}{
		{"none", config.StructuredOutputNone, ""},
		{"json object", config.StructuredOutputJSONObject, `"response_format":{"type":"json_object"}`},
		{"json schema", config.StructuredOutputJSONSchema, `"response_format":{"type":"json_schema","json_schema":{"name":"answer","strict":true,"schema":{"type":"object"}}}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, okReply("x")) })
			c, _ := newClient(t, up)
			req := basicRequest()
			req.StructuredOutput = tt.mode
			req.ResponseSchema = json.RawMessage(`{"type":"object"}`)
			if _, err := c.Complete(t.Context(), req); err != nil {
				t.Fatal(err)
			}
			body := up.body(0)
			if tt.want == "" && strings.Contains(body, "response_format") {
				t.Errorf("unexpected response_format in %s", body)
			}
			if tt.want != "" && !strings.Contains(body, tt.want) {
				t.Errorf("body %s lacks %s", body, tt.want)
			}
		})
	}
}

func TestCompleteReplyShapes(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		body    string
		want    string
		wantErr error
	}{
		{"string content", okReply("plain"), "plain", nil},
		{"parts content", `{"choices":[{"message":{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]}}]}`, "ab", nil},
		{"not json", `<html>`, "", llm.ErrInvalidResponse},
		{"no choices", `{"choices":[]}`, "", llm.ErrInvalidResponse},
		{"empty content", okReply("   "), "", llm.ErrInvalidResponse},
		{"null content", `{"choices":[{"message":{"content":null}}]}`, "", llm.ErrInvalidResponse},
		{"wrong content type", `{"choices":[{"message":{"content":42}}]}`, "", llm.ErrInvalidResponse},
		{"200 with error object", `{"error":{"message":"boom","code":500}}`, "", llm.ErrProviderUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, tt.body) })
			c, _ := newClient(t, up)
			resp, err := c.Complete(t.Context(), basicRequest())
			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Fatalf("err = %v, want %v", err, tt.wantErr)
				}
				return
			}
			if err != nil || resp.Content != tt.want {
				t.Errorf("got %q, %v; want %q", resp.Content, err, tt.want)
			}
		})
	}
}

func TestRetryTransientThenSuccess(t *testing.T) {
	t.Parallel()

	for _, status := range []int{429, 502, 503, 504} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			t.Parallel()
			up := newUpstream(t, func(n int, w http.ResponseWriter, _ *http.Request) {
				if n == 1 {
					writeJSON(w, status, `{"error":"try later"}`)
					return
				}
				writeJSON(w, 200, okReply("done"))
			})
			c, sleeps := newClient(t, up)

			resp, err := c.Complete(t.Context(), basicRequest())
			if err != nil || resp.Content != "done" {
				t.Fatalf("got %q, %v", resp.Content, err)
			}
			if up.count() != 2 {
				t.Errorf("upstream requests = %d, want exactly 2", up.count())
			}
			if len(*sleeps) != 1 || (*sleeps)[0] != 500*time.Millisecond {
				t.Errorf("sleeps = %v, want [500ms]", *sleeps)
			}
		})
	}
}

func TestRetryPersistentFailureStopsAtThreeAttempts(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 502, `{"detail":"bad gateway"}`) })
	c, sleeps := newClient(t, up)

	_, err := c.Complete(t.Context(), basicRequest())
	if !errors.Is(err, llm.ErrProviderUnavailable) {
		t.Fatalf("err = %v, want ErrProviderUnavailable", err)
	}
	if up.count() != 3 {
		t.Errorf("upstream requests = %d, want exactly 3", up.count())
	}
	if len(*sleeps) != 2 || (*sleeps)[0] != 500*time.Millisecond || (*sleeps)[1] != 1500*time.Millisecond {
		t.Errorf("sleeps = %v, want [500ms 1.5s]", *sleeps)
	}
	var apiErr *llm.Error
	if !errors.As(err, &apiErr) || apiErr.UpstreamStatus != 502 {
		t.Errorf("upstream status not recorded: %v", err)
	}
	if strings.Contains(err.Error(), "bad gateway") {
		t.Errorf("error leaks the upstream body: %v", err)
	}
}

func TestRetryJitterStaysWithinTwentyPercent(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 503, "{}") })
	for _, j := range []float64{-1, 1} {
		c, sleeps := newClient(t, up)
		c.jitter = func() float64 { return j }
		_, _ = c.Complete(t.Context(), basicRequest())
		lo, hi := time.Duration(float64(500*time.Millisecond)*0.8), time.Duration(float64(500*time.Millisecond)*1.2)
		if d := (*sleeps)[0]; d < lo || d > hi {
			t.Errorf("jitter %v: first delay %v outside [%v, %v]", j, d, lo, hi)
		}
	}
}

func TestRetryAfterHeader(t *testing.T) {
	t.Parallel()

	t.Run("honored when it fits", func(t *testing.T) {
		t.Parallel()
		up := newUpstream(t, func(n int, w http.ResponseWriter, _ *http.Request) {
			if n == 1 {
				w.Header().Set("Retry-After", "2")
				writeJSON(w, 429, "{}")
				return
			}
			writeJSON(w, 200, okReply("ok"))
		})
		c, sleeps := newClient(t, up)
		ctx, cancel := context.WithTimeout(t.Context(), time.Minute)
		defer cancel()
		if _, err := c.Complete(ctx, basicRequest()); err != nil {
			t.Fatal(err)
		}
		if len(*sleeps) != 1 || (*sleeps)[0] != 2*time.Second {
			t.Errorf("sleeps = %v, want [2s]", *sleeps)
		}
	})

	t.Run("not retried when it exceeds the remaining budget", func(t *testing.T) {
		t.Parallel()
		up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Retry-After", "120")
			writeJSON(w, 429, "{}")
		})
		c, sleeps := newClient(t, up)
		ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
		defer cancel()
		_, err := c.Complete(ctx, basicRequest())
		if !errors.Is(err, llm.ErrProviderUnavailable) {
			t.Fatalf("err = %v", err)
		}
		if up.count() != 1 || len(*sleeps) != 0 {
			t.Errorf("requests = %d sleeps = %v; want 1 request and no sleep", up.count(), *sleeps)
		}
	})
}

func TestRetryConnectionReset(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(n int, w http.ResponseWriter, _ *http.Request) {
		if n == 1 {
			conn, _, err := w.(http.Hijacker).Hijack()
			if err == nil {
				_ = conn.Close()
			}
			return
		}
		writeJSON(w, 200, okReply("recovered"))
	})
	c, _ := newClient(t, up)
	resp, err := c.Complete(t.Context(), basicRequest())
	if err != nil || resp.Content != "recovered" {
		t.Fatalf("got %q, %v", resp.Content, err)
	}
	if up.count() != 2 {
		t.Errorf("upstream requests = %d, want 2", up.count())
	}
}

func TestNonRetryableFailures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		status int
		body   string
		want   error
	}{
		{"400 bad request", 400, `{"error":"bad"}`, llm.ErrProviderUnavailable},
		{"400 unknown model", 400, `{"error":{"message":"openai/x is not a valid model ID"}}`, llm.ErrModelNotFound},
		{"401 invalid key", 401, `{"error":"invalid key ` + testKey + `"}`, llm.ErrProviderUnavailable},
		{"403 forbidden", 403, "{}", llm.ErrProviderUnavailable},
		{"404 not found", 404, "{}", llm.ErrModelNotFound},
		{"402 payment required", 402, "{}", llm.ErrProviderUnavailable},
		{"500 internal error", 500, "{}", llm.ErrProviderUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, tt.status, tt.body) })
			c, sleeps := newClient(t, up)

			_, err := c.Complete(t.Context(), basicRequest())
			if !errors.Is(err, tt.want) {
				t.Fatalf("err = %v, want %v", err, tt.want)
			}
			if up.count() != 1 || len(*sleeps) != 0 {
				t.Errorf("requests = %d sleeps = %v; want exactly one request", up.count(), *sleeps)
			}
			if strings.Contains(err.Error(), testKey) || strings.Contains(err.Error(), "invalid key") {
				t.Errorf("error leaks upstream body or key: %v", err)
			}
		})
	}
}

func TestRedirectIsNotFollowed(t *testing.T) {
	t.Parallel()

	target := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, okReply("elsewhere")) })
	up := newUpstream(t, func(_ int, w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.srv.URL+"/chat/completions", http.StatusTemporaryRedirect)
	})
	c, _ := newClient(t, up)
	if _, err := c.Complete(t.Context(), basicRequest()); !errors.Is(err, llm.ErrProviderUnavailable) {
		t.Errorf("err = %v, want ErrProviderUnavailable", err)
	}
	if target.count() != 0 {
		t.Error("the redirect target was contacted")
	}
}

func TestTimeout(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, _ http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	c, _ := newClient(t, up)
	ctx, cancel := context.WithTimeout(t.Context(), 100*time.Millisecond)
	defer cancel()

	_, err := c.Complete(ctx, basicRequest())
	if !errors.Is(err, llm.ErrTimeout) {
		t.Fatalf("err = %v, want ErrTimeout", err)
	}
	if up.count() != 1 {
		t.Errorf("a timed-out request must not be retried; got %d requests", up.count())
	}
}

func TestResponseHeaderTimeout(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, _ http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	c, _ := newClient(t, up, func(o *Options) { o.ResponseHeaderTimeout = 100 * time.Millisecond })
	if _, err := c.Complete(t.Context(), basicRequest()); !errors.Is(err, llm.ErrTimeout) {
		t.Fatalf("err = %v, want ErrTimeout", err)
	}
}

func TestCancellationCancelsUpstreamRequest(t *testing.T) {
	t.Parallel()

	arrived := make(chan struct{})
	upstreamCancelled := make(chan struct{})
	up := newUpstream(t, func(_ int, _ http.ResponseWriter, r *http.Request) {
		close(arrived)
		<-r.Context().Done()
		close(upstreamCancelled)
	})
	c, _ := newClient(t, up)

	ctx, cancel := context.WithCancel(t.Context())
	errCh := make(chan error, 1)
	go func() {
		_, err := c.Complete(ctx, basicRequest())
		errCh <- err
	}()

	<-arrived
	cancel()

	if err := <-errCh; !errors.Is(err, context.Canceled) {
		t.Errorf("err = %v, want context.Canceled", err)
	}
	select {
	case <-upstreamCancelled:
	case <-time.After(5 * time.Second):
		t.Error("the upstream request was not cancelled")
	}
}

func TestCancellationDuringBackoffStopsRetrying(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 503, "{}") })
	c, _ := newClient(t, up)
	ctx, cancel := context.WithCancel(t.Context())
	c.sleep = func(ctx context.Context, _ time.Duration) error {
		cancel()
		return ctx.Err()
	}
	if _, err := c.Complete(ctx, basicRequest()); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	if up.count() != 1 {
		t.Errorf("requests = %d, want 1", up.count())
	}
}

func TestOversizedBody(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(200)
		_, _ = io.WriteString(w, `{"choices":[{"message":{"content":"`)
		chunk := strings.Repeat("a", 64<<10)
		for range 80 { // about 5 MiB
			if _, err := io.WriteString(w, chunk); err != nil {
				return // the client stopped reading
			}
		}
		_, _ = io.WriteString(w, `"}}]}`)
	})
	c, _ := newClient(t, up, func(o *Options) { o.MaxBodyBytes = 1 << 20 })

	_, err := c.Complete(t.Context(), basicRequest())
	if !errors.Is(err, llm.ErrInvalidResponse) {
		t.Fatalf("err = %v, want ErrInvalidResponse", err)
	}
	if up.count() != 1 {
		t.Errorf("an oversized reply must not be retried; requests = %d", up.count())
	}
}

func TestListModelsOpenRouterModalities(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, `{"data":[
			{"id":"openai/gpt-4o-mini","name":"GPT-4o mini","architecture":{"input_modalities":["text","image"]}},
			{"id":"meta/llama","name":"Llama","architecture":{"input_modalities":["text"]}},
			{"id":"no-arch/model"},
			{"id":""}
		]}`)
	})
	c, _ := newClient(t, up)

	models, err := c.ListModels(t.Context())
	if err != nil {
		t.Fatalf("ListModels: %v", err)
	}
	if up.paths[0] != "/models" || up.header[0].Get("Authorization") != "Bearer "+testKey {
		t.Errorf("request = %v %v", up.paths[0], up.header[0])
	}
	want := map[string]bool{"openai/gpt-4o-mini": true, "meta/llama": false, "no-arch/model": false}
	if len(models) != len(want) {
		t.Fatalf("models = %+v", models)
	}
	for _, m := range models {
		vision, ok := want[m.ID]
		if !ok || m.Capabilities.Vision != vision || !m.Capabilities.Text {
			t.Errorf("model %+v: want vision=%v text=true", m, vision)
		}
	}
	if models[0].Name != "GPT-4o mini" || models[2].Name != "no-arch/model" {
		t.Errorf("names = %q, %q", models[0].Name, models[2].Name)
	}
}

func TestListModelsRouterAIFormatWithoutModalities(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, 200, `{"object":"list","data":[{"id":"gpt-4o","object":"model","owned_by":"openai"}]}`)
	})
	c, _ := newClient(t, up)
	models, err := c.ListModels(t.Context())
	if err != nil || len(models) != 1 {
		t.Fatalf("ListModels = %+v, %v", models, err)
	}
	if models[0].Capabilities.Vision {
		t.Error("vision must default to false when modalities are not declared")
	}
}

func TestListModelsErrors(t *testing.T) {
	t.Parallel()

	up := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 401, "{}") })
	c, _ := newClient(t, up)
	if _, err := c.ListModels(t.Context()); !errors.Is(err, llm.ErrProviderUnavailable) {
		t.Errorf("err = %v, want ErrProviderUnavailable", err)
	}

	bad := newUpstream(t, func(_ int, w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, "nope") })
	c, _ = newClient(t, bad)
	if _, err := c.ListModels(t.Context()); !errors.Is(err, llm.ErrInvalidResponse) {
		t.Errorf("err = %v, want ErrInvalidResponse", err)
	}
}

func TestClientStringDoesNotExposeKey(t *testing.T) {
	t.Parallel()

	c := New(Options{BaseURL: "https://example.test/v1/", APIKey: testKey})
	if s := fmt.Sprint(c); strings.Contains(s, testKey) {
		t.Errorf("String() leaks the key: %s", s)
	}
}
