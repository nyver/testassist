package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nyver/test-assistant/server/internal/analysis"
	"github.com/nyver/test-assistant/server/internal/apierr"
	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/identity"
	"github.com/nyver/test-assistant/server/internal/llm"
)

const (
	testToken    = "test-token-0123456789abcdef"
	fixtureDir   = "../../../../protocol/fixtures/api"
	defaultModel = "openai/gpt-4o-mini"
	textOnly     = "meta-llama/llama-3.1-8b-instruct"
)

// A minimal PNG signature followed by filler is enough for content sniffing.
var (
	pngBytes  = append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte{0x11}, 64)...)
	jpegBytes = append([]byte("\xff\xd8\xff\xe0\x00\x10JFIF\x00"), bytes.Repeat([]byte{0x22}, 64)...)
	gifBytes  = append([]byte("GIF89a"), bytes.Repeat([]byte{0x33}, 64)...)
)

// fakeLLM is an llm.Provider that records calls.
type fakeLLM struct {
	mu        sync.Mutex
	completes []llm.ChatRequest
	lists     int
	reply     string
	block     bool // Complete blocks until its context is done
	panicNow  bool
}

func (f *fakeLLM) Complete(ctx context.Context, req llm.ChatRequest) (llm.ChatResponse, error) {
	f.mu.Lock()
	f.completes = append(f.completes, req)
	reply, block, doPanic := f.reply, f.block, f.panicNow
	f.mu.Unlock()
	if doPanic {
		panic("simulated failure inside the provider")
	}
	if block {
		<-ctx.Done()
		return llm.ChatResponse{}, ctx.Err()
	}
	return llm.ChatResponse{Content: reply}, nil
}

func (f *fakeLLM) ListModels(context.Context) ([]llm.Model, error) {
	f.mu.Lock()
	f.lists++
	f.mu.Unlock()
	return nil, errors.New("no upstream listing in tests")
}

func (f *fakeLLM) completeCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.completes)
}

func (f *fakeLLM) listCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.lists
}

type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

type testEnv struct {
	t       *testing.T
	server  *Server
	handler http.Handler
	llm     *fakeLLM
	clock   *fakeClock
	logs    *bytes.Buffer
	dataDir string
	cfg     *config.Config
}

type envOptions struct {
	mutateConfig func(*config.Config)
	noProviders  bool
	noCert       bool
	authOff      bool
}

func boolPtr(b bool) *bool { return &b }

func newEnv(t *testing.T, opts ...func(*envOptions)) *testEnv {
	t.Helper()
	var o envOptions
	for _, f := range opts {
		f(&o)
	}

	cfg := config.Default()
	cfg.Server.DataDir = t.TempDir()
	cfg.Security.AuthEnabled = !o.authOff
	models := []config.ModelConfig{
		{ID: defaultModel, Name: "GPT-4o mini", Text: boolPtr(true), Vision: boolPtr(true)},
		{ID: textOnly, Name: "Llama 3.1 8B Instruct", Text: boolPtr(true), Vision: boolPtr(false)},
	}
	cfg.LLM.Providers = []config.ProviderConfig{
		{ID: "openrouter", Name: "OpenRouter", Type: config.ProviderTypeOpenAICompatible, BaseURL: "https://a.example/v1", Enabled: !o.noProviders, DefaultModel: defaultModel, Models: models},
		{ID: "routerai", Name: "RouterAI", Type: config.ProviderTypeOpenAICompatible, BaseURL: "https://b.example/v1", Enabled: !o.noProviders, DefaultModel: defaultModel, Models: models},
	}
	cfg.LLM.DefaultProvider = "openrouter"
	if o.mutateConfig != nil {
		o.mutateConfig(&cfg)
	}

	clock := &fakeClock{t: time.Date(2026, 3, 4, 5, 6, 7, 0, time.UTC)}
	fp := &fakeLLM{reply: `{"status":"answered","correctOptionIds":["B"],"explanation":"HTTPS wraps HTTP in TLS, which encrypts and authenticates the traffic.","details":"HTTP alone sends data in plaintext, TLS is only a layer and SSH is a remote shell protocol.","confidence":0.96,"warnings":[]}`}
	reg := llm.NewRegistry(&cfg, func(config.ProviderConfig) llm.Provider { return fp }, clock.Now)
	svc := analysis.NewService(reg, analysis.Settings{Timeout: cfg.Timeouts.LLM, MaxTokens: cfg.LLM.MaxTokens, Confidence: cfg.Confidence})

	logs := &bytes.Buffer{}
	srv := New(Deps{
		Config:     &cfg,
		Identity:   identity.Info{ServerID: "019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77", Name: "Home Assistant Server"},
		Version:    "0.1.0",
		Token:      testToken,
		CertLoaded: !o.noCert,
		Registry:   reg,
		Analysis:   svc,
		Logger:     slog.New(slog.NewJSONHandler(&syncWriter{w: logs}, &slog.HandlerOptions{Level: slog.LevelDebug})),
		Now:        clock.Now,
	})
	return &testEnv{t: t, server: srv, handler: srv.Handler(), llm: fp, clock: clock, logs: logs, dataDir: cfg.Server.DataDir, cfg: &cfg}
}

type syncWriter struct {
	mu sync.Mutex
	w  io.Writer
}

func (s *syncWriter) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.w.Write(p)
}

// call sends a request from a fixed client address.
func (e *testEnv) call(req *http.Request) *httptest.ResponseRecorder {
	if req.RemoteAddr == "" {
		req.RemoteAddr = "192.0.2.10:40000"
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

func (e *testEnv) get(path string, auth bool) *httptest.ResponseRecorder {
	req := httptest.NewRequestWithContext(e.t.Context(), http.MethodGet, path, nil)
	if auth {
		req.Header.Set("Authorization", "Bearer "+testToken)
	}
	return e.call(req)
}

type formField struct{ name, value string }

type formImage struct {
	data        []byte
	declaredCT  string
	filename    string
	overrideKey string
}

func multipartBody(t *testing.T, fields []formField, img *formImage) (io.Reader, string) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, f := range fields {
		if err := mw.WriteField(f.name, f.value); err != nil {
			t.Fatal(err)
		}
	}
	if img != nil {
		key := img.overrideKey
		if key == "" {
			key = "image"
		}
		h := make(textproto.MIMEHeader)
		h.Set("Content-Disposition", `form-data; name="`+key+`"; filename="`+img.filename+`"`)
		h.Set("Content-Type", img.declaredCT)
		part, err := mw.CreatePart(h)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := part.Write(img.data); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return &buf, mw.FormDataContentType()
}

const optionsABCD = `[{"id":"A","text":"HTTP"},{"id":"B","text":"HTTPS"},{"id":"C","text":"TLS"},{"id":"D","text":"SSH"}]`

func baseFields() []formField {
	return []formField{
		{"question", "Which protocol encrypts web traffic?"},
		{"options", optionsABCD},
		{"language", "en"},
	}
}

func (e *testEnv) analyze(t *testing.T, fields []formField, img *formImage) *httptest.ResponseRecorder {
	t.Helper()
	body, ct := multipartBody(t, fields, img)
	req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/api/v1/questions/analyze", body)
	req.Header.Set("Content-Type", ct)
	req.Header.Set("Authorization", "Bearer "+testToken)
	return e.call(req)
}

func decode(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &m); err != nil {
		t.Fatalf("body is not a JSON object: %v\n%s", err, rec.Body.String())
	}
	return m
}

func errorCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	body := decode(t, rec)
	errObj, ok := body["error"].(map[string]any)
	if !ok {
		t.Fatalf("no error object in %s", rec.Body.String())
	}
	return errObj["code"].(string)
}

func assertError(t *testing.T, rec *httptest.ResponseRecorder, status int, code apierr.Code) {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("status = %d, want %d; body: %s", rec.Code, status, rec.Body.String())
	}
	if got := errorCode(t, rec); got != string(code) {
		t.Fatalf("code = %s, want %s", got, code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q", ct)
	}
	errObj := decode(t, rec)["error"].(map[string]any)
	if msg, _ := errObj["message"].(string); msg == "" {
		t.Error("error message is empty")
	}
	if errObj["requestId"] == "" || errObj["requestId"] != rec.Header().Get("X-Request-ID") {
		t.Errorf("requestId %v must equal the X-Request-ID header %q", errObj["requestId"], rec.Header().Get("X-Request-ID"))
	}
}

// assertMatchesFixture compares a JSON response with a shared fixture. The
// request id is dynamic, so it is normalized before the comparison.
func assertMatchesFixture(t *testing.T, rec *httptest.ResponseRecorder, fixture string) {
	t.Helper()
	want, err := os.ReadFile(filepath.Join(fixtureDir, fixture))
	if err != nil {
		t.Fatal(err)
	}
	var wantV, gotV any
	if err := json.Unmarshal(want, &wantV); err != nil {
		t.Fatalf("fixture %s: %v", fixture, err)
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &gotV); err != nil {
		t.Fatalf("response is not JSON: %v\n%s", err, rec.Body.String())
	}
	normalizeRequestID(wantV)
	normalizeRequestID(gotV)
	if !reflect.DeepEqual(wantV, gotV) {
		t.Errorf("response differs from fixture %s\n got: %s\nwant: %s", fixture, rec.Body.String(), want)
	}
}

func normalizeRequestID(v any) {
	m, ok := v.(map[string]any)
	if !ok {
		return
	}
	if _, has := m["requestId"]; has {
		m["requestId"] = "<id>"
	}
	if inner, ok := m["error"].(map[string]any); ok {
		if _, has := inner["requestId"]; has {
			inner["requestId"] = "<id>"
		}
		delete(inner, "message") // wording may evolve; the code is the contract
	}
}

// ---------- authentication, envelope, request id ----------

func TestAuthentication(t *testing.T) {
	t.Parallel()
	e := newEnv(t, func(o *envOptions) {
		o.mutateConfig = func(c *config.Config) { c.RateLimit.General = config.RateConfig{RequestsPerMinute: 6000, Burst: 1000} }
	})

	paths := []string{
		"/api/v1/server/info", "/api/v1/llm/providers", "/api/v1/llm/models", "/api/v1/nope",
	}
	for _, p := range paths {
		t.Run("missing token "+p, func(t *testing.T) {
			t.Parallel()
			assertError(t, e.get(p, false), 401, apierr.Unauthorized)
		})
	}

	tests := []struct {
		name   string
		header string
	}{
		{"wrong token", "Bearer wrong"},
		{"wrong scheme", "Basic " + testToken},
		{"bare token", testToken},
		{"empty bearer", "Bearer "},
		{"token with suffix", "Bearer " + testToken + "x"},
		{"token prefix", "Bearer " + testToken[:len(testToken)-1]},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/v1/server/info", nil)
			req.Header.Set("Authorization", tt.header)
			assertError(t, e.call(req), 401, apierr.Unauthorized)
		})
	}

	t.Run("scheme is case-insensitive", func(t *testing.T) {
		t.Parallel()
		req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/v1/server/info", nil)
		req.Header.Set("Authorization", "bearer "+testToken)
		if rec := e.call(req); rec.Code != 200 {
			t.Errorf("status = %d", rec.Code)
		}
	})

	t.Run("health needs no token", func(t *testing.T) {
		t.Parallel()
		if rec := e.get("/health/live", false); rec.Code != 200 {
			t.Errorf("live status = %d", rec.Code)
		}
		if rec := e.get("/health/ready", false); rec.Code != 200 {
			t.Errorf("ready status = %d", rec.Code)
		}
	})

	t.Run("auth disabled", func(t *testing.T) {
		t.Parallel()
		off := newEnv(t, func(o *envOptions) { o.authOff = true })
		if rec := off.get("/api/v1/llm/providers", false); rec.Code != 200 {
			t.Errorf("status = %d, want 200 without a token", rec.Code)
		}
	})
}

func TestUnknownRouteUsesErrorEnvelope(t *testing.T) {
	t.Parallel()
	e := newEnv(t)
	assertError(t, e.get("/api/v1/does/not/exist", true), 404, apierr.NotFound)
	assertError(t, e.get("/elsewhere", false), 404, apierr.NotFound)

	// A known path with the wrong method is also a plain 404 envelope.
	req := httptest.NewRequestWithContext(t.Context(), http.MethodDelete, "/api/v1/llm/providers", nil)
	req.Header.Set("Authorization", "Bearer "+testToken)
	assertError(t, e.call(req), 404, apierr.NotFound)
}

func TestRequestIDHandling(t *testing.T) {
	t.Parallel()
	e := newEnv(t)

	t.Run("generated", func(t *testing.T) {
		t.Parallel()
		id := e.get("/health/live", false).Header().Get("X-Request-ID")
		if id == "" || !requestIDPattern.MatchString(id) {
			t.Errorf("generated id = %q", id)
		}
	})

	tests := []struct {
		name     string
		supplied string
		keep     bool
	}{
		{"valid client id is kept", "client-id_123", true},
		{"64 characters are kept", strings.Repeat("a", 64), true},
		{"200 characters are replaced", strings.Repeat("a", 200), false},
		{"65 characters are replaced", strings.Repeat("a", 65), false},
		{"invalid characters are replaced", "bad id!", false},
		{"newline-like characters are replaced", "a\tb", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/health/live", nil)
			req.Header.Set("X-Request-ID", tt.supplied)
			got := e.call(req).Header().Get("X-Request-ID")
			if tt.keep && got != tt.supplied {
				t.Errorf("id = %q, want the supplied one", got)
			}
			if !tt.keep && (got == tt.supplied || !requestIDPattern.MatchString(got)) {
				t.Errorf("id = %q, want a fresh valid id", got)
			}
		})
	}

	t.Run("error body carries the client id", func(t *testing.T) {
		t.Parallel()
		req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/v1/server/info", nil)
		req.Header.Set("X-Request-ID", "trace-42")
		rec := e.call(req)
		assertError(t, rec, 401, apierr.Unauthorized)
		if rec.Header().Get("X-Request-ID") != "trace-42" {
			t.Errorf("id = %q", rec.Header().Get("X-Request-ID"))
		}
	})
}

func TestErrorCodeStatusTable(t *testing.T) {
	t.Parallel()

	// The table from the http-api specification, plus NOT_FOUND for unknown routes.
	want := map[apierr.Code]int{
		"INVALID_REQUEST": 400, "UNAUTHORIZED": 401, "NOT_FOUND": 404, "PROVIDER_NOT_FOUND": 404,
		"MODEL_NOT_FOUND": 404, "IMAGE_TOO_LARGE": 413, "UNSUPPORTED_IMAGE_TYPE": 415,
		"MODEL_DOES_NOT_SUPPORT_VISION": 422, "RATE_LIMITED": 429, "INTERNAL_ERROR": 500,
		"LLM_PROVIDER_UNAVAILABLE": 502, "LLM_INVALID_RESPONSE": 502, "LLM_TIMEOUT": 504,
	}
	all := apierr.All()
	if len(all) != len(want) {
		t.Fatalf("apierr.All has %d codes, table has %d", len(all), len(want))
	}
	for _, c := range all {
		if got := c.Status(); got != want[c] {
			t.Errorf("%s status = %d, want %d", c, got, want[c])
		}
	}
}

func TestErrorFixturesAreConsistent(t *testing.T) {
	t.Parallel()

	files, err := filepath.Glob(filepath.Join(fixtureDir, "error_*.json"))
	if err != nil || len(files) < len(apierr.All()) {
		t.Fatalf("found %d error fixtures for %d codes (%v)", len(files), len(apierr.All()), err)
	}
	known := map[string]bool{}
	for _, c := range apierr.All() {
		known[string(c)] = true
	}
	covered := map[string]bool{}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		var env errorEnvelope
		if err := json.Unmarshal(data, &env); err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		if !known[string(env.Error.Code)] || env.Error.Message == "" || env.Error.RequestID == "" {
			t.Errorf("%s is not a valid envelope for a known code: %+v", f, env)
		}
		covered[string(env.Error.Code)] = true
	}
	for c := range known {
		if !covered[c] {
			t.Errorf("no fixture for error code %s", c)
		}
	}
}

// ---------- info, providers, models ----------

func TestServerInfoMatchesFixture(t *testing.T) {
	t.Parallel()
	rec := newEnv(t).get("/api/v1/server/info", true)
	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	assertMatchesFixture(t, rec, "server_info.json")
	if rec.Header().Get("X-Request-ID") == "" {
		t.Error("missing X-Request-ID")
	}
}

func TestProviders(t *testing.T) {
	t.Parallel()

	t.Run("both providers match the fixture", func(t *testing.T) {
		t.Parallel()
		rec := newEnv(t).get("/api/v1/llm/providers", true)
		assertMatchesFixture(t, rec, "providers.json")
	})

	t.Run("provider without key is not listed", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.LLM.Providers[1].Enabled = false }
		})
		var got []map[string]any
		if err := json.Unmarshal(e.get("/api/v1/llm/providers", true).Body.Bytes(), &got); err != nil {
			t.Fatal(err)
		}
		if len(got) != 1 || got[0]["id"] != "openrouter" || got[0]["isDefault"] != true {
			t.Errorf("providers = %v", got)
		}
	})

	t.Run("no providers encodes as an empty array", func(t *testing.T) {
		t.Parallel()
		rec := newEnv(t, func(o *envOptions) { o.noProviders = true }).get("/api/v1/llm/providers", true)
		if strings.TrimSpace(rec.Body.String()) != "[]" {
			t.Errorf("body = %q", rec.Body.String())
		}
	})
}

func TestModels(t *testing.T) {
	t.Parallel()

	t.Run("explicit provider matches the fixture", func(t *testing.T) {
		t.Parallel()
		rec := newEnv(t).get("/api/v1/llm/models?provider=openrouter", true)
		assertMatchesFixture(t, rec, "models.json")
	})

	t.Run("default provider is used when omitted", func(t *testing.T) {
		t.Parallel()
		rec := newEnv(t).get("/api/v1/llm/models", true)
		assertMatchesFixture(t, rec, "models.json")
	})

	t.Run("unknown provider", func(t *testing.T) {
		t.Parallel()
		assertError(t, newEnv(t).get("/api/v1/llm/models?provider=unknown", true), 404, apierr.ProviderNotFound)
	})

	t.Run("no enabled provider", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) { o.noProviders = true })
		assertError(t, e.get("/api/v1/llm/models", true), 404, apierr.ProviderNotFound)
	})
}

// ---------- analyze ----------

func TestAnalyzeSuccessMatchesFixtures(t *testing.T) {
	t.Parallel()

	t.Run("answered", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), nil)
		if rec.Code != 200 {
			t.Fatalf("status = %d; %s", rec.Code, rec.Body.String())
		}
		assertMatchesFixture(t, rec, "analyze_answered.json")
		if got := decode(t, rec)["requestId"]; got != rec.Header().Get("X-Request-ID") {
			t.Errorf("requestId %v != header %q", got, rec.Header().Get("X-Request-ID"))
		}
		if e.llm.completeCount() != 1 {
			t.Errorf("provider calls = %d", e.llm.completeCount())
		}
	})

	t.Run("multiple answers", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		e.llm.reply = `{"status":"answered","correctOptionIds":["A","C"],"explanation":"Both options are valid parts of a secure web stack.","details":null,"confidence":0.72,"warnings":[]}`
		assertMatchesFixture(t, e.analyze(t, baseFields(), nil), "analyze_multi.json")
	})

	t.Run("uncertain", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		e.llm.reply = `{"status":"uncertain","correctOptionIds":[],"explanation":null,"details":null,"confidence":0.31,"warnings":["Option C is not readable"]}`
		fields := append(baseFields(), formField{"provider", "routerai"})
		assertMatchesFixture(t, e.analyze(t, fields, nil), "analyze_uncertain.json")
	})
}

func TestAnalyzeRequestValidation(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		fields []formField
		status int
		code   apierr.Code
	}{
		{"duplicate option ids", []formField{{"question", "Q?"}, {"options", `[{"id":"B","text":"x"},{"id":"B","text":"y"}]`}}, 400, apierr.InvalidRequest},
		{"malformed options json", []formField{{"question", "Q?"}, {"options", `{not json`}}, 400, apierr.InvalidRequest},
		{"options is not an array", []formField{{"question", "Q?"}, {"options", `{"id":"A"}`}}, 400, apierr.InvalidRequest},
		{"one option", []formField{{"question", "Q?"}, {"options", `[{"id":"A","text":"x"}]`}}, 400, apierr.InvalidRequest},
		{"missing question", []formField{{"options", optionsABCD}}, 400, apierr.InvalidRequest},
		{"blank question", []formField{{"question", "   "}, {"options", optionsABCD}}, 400, apierr.InvalidRequest},
		{"missing options", []formField{{"question", "Q?"}}, 400, apierr.InvalidRequest},
		{"repeated field", []formField{{"question", "Q?"}, {"question", "Q2?"}, {"options", optionsABCD}}, 400, apierr.InvalidRequest},
		{"bad language", append(baseFields()[:2:2], formField{"language", "not a tag"}), 400, apierr.InvalidRequest},
		{"oversized text field", []formField{{"question", strings.Repeat("x", maxFieldBytes+1)}, {"options", optionsABCD}}, 400, apierr.InvalidRequest},
		{"unknown provider", append(baseFields(), formField{"provider", "nope"}), 404, apierr.ProviderNotFound},
		{"unknown model", append(baseFields(), formField{"model", "vendor/absent"}), 404, apierr.ModelNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			assertError(t, e.analyze(t, tt.fields, nil), tt.status, tt.code)
			if e.llm.completeCount() != 0 {
				t.Error("no provider may be called for an invalid request")
			}
		})
	}

	t.Run("wrong content type", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/api/v1/questions/analyze", strings.NewReader(`{"question":"x"}`))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+testToken)
		assertError(t, e.call(req), 400, apierr.InvalidRequest)
	})

	t.Run("unknown form fields are ignored", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, append(baseFields(), formField{"surprise", "value"}), nil)
		if rec.Code != 200 {
			t.Errorf("status = %d; %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAnalyzeLLMFailuresMapToCodes(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name   string
		reply  string
		status int
		code   apierr.Code
	}{
		{"prose reply", "The answer is B.", 502, apierr.LLMInvalidResponse},
		{"invented option", `{"status":"answered","correctOptionIds":["E"],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`, 502, apierr.LLMInvalidResponse},
		{"answered without ids", `{"status":"answered","correctOptionIds":[],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`, 502, apierr.LLMInvalidResponse},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := newEnv(t)
			e.llm.reply = tt.reply
			assertError(t, e.analyze(t, baseFields(), nil), tt.status, tt.code)
		})
	}

	t.Run("request timeout becomes LLM_TIMEOUT", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.Timeouts.Request = 50 * time.Millisecond }
		})
		e.llm.block = true
		assertError(t, e.analyze(t, baseFields(), nil), 504, apierr.LLMTimeout)
	})
}

func TestAnalyzeImageHandling(t *testing.T) {
	t.Parallel()

	t.Run("png with a vision model", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), &formImage{data: pngBytes, declaredCT: "image/png", filename: "q.png"})
		if rec.Code != 200 {
			t.Fatalf("status = %d; %s", rec.Code, rec.Body.String())
		}
		sent := e.llm.completes[0].Image
		if sent == nil || sent.MIME != "image/png" || !bytes.Equal(sent.Data, pngBytes) {
			t.Errorf("image was not forwarded intact: %+v", sent)
		}
	})

	t.Run("jpeg is accepted", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), &formImage{data: jpegBytes, declaredCT: "application/octet-stream", filename: "q.bin"})
		if rec.Code != 200 || e.llm.completes[0].Image.MIME != "image/jpeg" {
			t.Errorf("status = %d", rec.Code)
		}
	})

	t.Run("image with a text-only model is rejected before any call", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		fields := append(baseFields(), formField{"model", textOnly})
		rec := e.analyze(t, fields, &formImage{data: pngBytes, declaredCT: "image/png", filename: "q.png"})
		assertError(t, rec, 422, apierr.ModelDoesNotSupportVision)
		if e.llm.completeCount() != 0 {
			t.Error("provider was called")
		}
	})

	t.Run("disguised gif", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), &formImage{data: gifBytes, declaredCT: "image/jpeg", filename: "q.jpg"})
		assertError(t, rec, 415, apierr.UnsupportedImageType)
		if e.llm.completeCount() != 0 {
			t.Error("provider was called")
		}
	})

	t.Run("text file declared as image", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), &formImage{data: []byte("just some text here"), declaredCT: "image/png", filename: "q.png"})
		assertError(t, rec, 415, apierr.UnsupportedImageType)
	})

	t.Run("empty image part", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, baseFields(), &formImage{data: nil, declaredCT: "image/png", filename: "q.png"})
		assertError(t, rec, 400, apierr.InvalidRequest)
	})

	t.Run("image larger than the limit", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.Limits.MaxImageBytes = 1024; c.Limits.MaxRequestBytes = 1 << 20 }
		})
		big := append(append([]byte{}, pngBytes...), bytes.Repeat([]byte{0x44}, 2048)...)
		rec := e.analyze(t, baseFields(), &formImage{data: big, declaredCT: "image/png", filename: "q.png"})
		assertError(t, rec, 413, apierr.ImageTooLarge)
		if e.llm.completeCount() != 0 {
			t.Error("provider was called")
		}
	})

	t.Run("image exactly at the limit is accepted", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.Limits.MaxImageBytes = int64(len(pngBytes)) }
		})
		rec := e.analyze(t, baseFields(), &formImage{data: pngBytes, declaredCT: "image/png", filename: "q.png"})
		if rec.Code != 200 {
			t.Errorf("status = %d; %s", rec.Code, rec.Body.String())
		}
	})
}

func TestAnalyzeImageOnly(t *testing.T) {
	t.Parallel()

	png := &formImage{data: pngBytes, declaredCT: "image/png", filename: "q.png"}
	const reply = `{"status":"answered","question":"Which protocol encrypts HTTP?","options":[{"id":"A","text":"FTP"},{"id":"B","text":"HTTPS"}],"correctOptionIds":["B"],"explanation":"TLS.","details":null,"confidence":0.9,"warnings":[]}`

	t.Run("an image without text is analyzed", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		e.llm.reply = reply
		rec := e.analyze(t, nil, png)
		if rec.Code != 200 {
			t.Fatalf("status = %d; %s", rec.Code, rec.Body.String())
		}
		body := decode(t, rec)
		if body["recognizedQuestion"] != "Which protocol encrypts HTTP?" || body["answerText"] != "HTTPS" {
			t.Errorf("body = %v", body)
		}
		if opts, _ := body["recognizedOptions"].([]any); len(opts) != 2 {
			t.Errorf("recognizedOptions = %v", body["recognizedOptions"])
		}
		if e.llm.completes[0].Image == nil {
			t.Error("the image was not forwarded")
		}
	})

	t.Run("a request with text does not report recognized fields", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		body := decode(t, e.analyze(t, baseFields(), png))
		if _, ok := body["recognizedQuestion"]; ok {
			t.Errorf("unexpected recognizedQuestion: %v", body)
		}
		if _, ok := body["recognizedOptions"]; ok {
			t.Errorf("unexpected recognizedOptions: %v", body)
		}
	})

	t.Run("no text and no image", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		assertError(t, e.analyze(t, nil, nil), 400, apierr.InvalidRequest)
		if e.llm.completeCount() != 0 {
			t.Error("the provider was called")
		}
	})

	t.Run("only one of question and options", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		assertError(t, e.analyze(t, []formField{{"question", "Q?"}}, png), 400, apierr.InvalidRequest)
		assertError(t, e.analyze(t, []formField{{"options", optionsABCD}}, png), 400, apierr.InvalidRequest)
		if e.llm.completeCount() != 0 {
			t.Error("the provider was called")
		}
	})

	t.Run("a text-only model is rejected", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		rec := e.analyze(t, []formField{{"model", textOnly}}, png)
		assertError(t, rec, 422, apierr.ModelDoesNotSupportVision)
		if e.llm.completeCount() != 0 {
			t.Error("the provider was called")
		}
	})
}

func TestBodyLimit(t *testing.T) {
	t.Parallel()

	newSmall := func(t *testing.T) *testEnv {
		return newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.Limits.MaxRequestBytes = 2048; c.Limits.MaxImageBytes = 1024 }
		})
	}

	t.Run("declared length above the limit", func(t *testing.T) {
		t.Parallel()
		e := newSmall(t)
		body, ct := multipartBody(t, append(baseFields(), formField{"model", strings.Repeat("m", 5000)}), nil)
		req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/api/v1/questions/analyze", body)
		req.Header.Set("Content-Type", ct)
		req.Header.Set("Authorization", "Bearer "+testToken)
		assertError(t, e.call(req), 413, apierr.ImageTooLarge)
		if e.llm.completeCount() != 0 {
			t.Error("provider was called")
		}
	})

	t.Run("undeclared length is cut off while reading", func(t *testing.T) {
		t.Parallel()
		e := newSmall(t)
		body, ct := multipartBody(t, append(baseFields(), formField{"model", strings.Repeat("m", 5000)}), nil)
		req := httptest.NewRequestWithContext(t.Context(), http.MethodPost, "/api/v1/questions/analyze", io.MultiReader(body)) // hides the length
		req.ContentLength = -1
		req.Header.Set("Content-Type", ct)
		req.Header.Set("Authorization", "Bearer "+testToken)
		assertError(t, e.call(req), 413, apierr.ImageTooLarge)
	})
}

// ---------- rate limiting ----------

func TestAnalyzeRateLimit(t *testing.T) {
	t.Parallel()
	e := newEnv(t)

	statuses := make([]int, 0, 4)
	var limited *httptest.ResponseRecorder
	for range 4 {
		rec := e.analyze(t, baseFields(), nil)
		statuses = append(statuses, rec.Code)
		if rec.Code == 429 {
			limited = rec
		}
	}
	if limited == nil {
		t.Fatalf("no request was rate limited: %v", statuses)
	}
	assertError(t, limited, 429, apierr.RateLimited)
	if ra := limited.Header().Get("Retry-After"); ra == "" || ra == "0" {
		t.Errorf("Retry-After = %q", ra)
	}
	if statuses[0] != 200 || statuses[2] != 200 || statuses[3] != 429 {
		t.Errorf("statuses = %v, want burst of 3 then 429", statuses)
	}

	t.Run("a rejected request does not consume tokens and the bucket refills", func(t *testing.T) {
		// 10 per minute: one token every 6 s.
		e.clock.Advance(7 * time.Second)
		if rec := e.analyze(t, baseFields(), nil); rec.Code != 200 {
			t.Errorf("status after refill = %d", rec.Code)
		}
		if rec := e.analyze(t, baseFields(), nil); rec.Code != 429 {
			t.Errorf("second request right after = %d, want 429", rec.Code)
		}
	})
}

func TestRateLimitIsPerClient(t *testing.T) {
	t.Parallel()
	e := newEnv(t, func(o *envOptions) {
		o.mutateConfig = func(c *config.Config) { c.RateLimit.General = config.RateConfig{RequestsPerMinute: 1, Burst: 1} }
	})
	from := func(addr string) int {
		req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/v1/server/info", nil)
		req.RemoteAddr = addr
		req.Header.Set("Authorization", "Bearer "+testToken)
		return e.call(req).Code
	}
	if from("198.51.100.1:1000") != 200 {
		t.Fatal("first request from X must pass")
	}
	if got := from("198.51.100.1:2000"); got != 429 { // same IP, different port
		t.Errorf("second request from X = %d, want 429", got)
	}
	if got := from("198.51.100.2:1000"); got != 200 {
		t.Errorf("request from Y = %d, want 200 (independent clients)", got)
	}
}

func TestHealthIsNotRateLimited(t *testing.T) {
	t.Parallel()
	e := newEnv(t, func(o *envOptions) {
		o.mutateConfig = func(c *config.Config) { c.RateLimit.General = config.RateConfig{RequestsPerMinute: 1, Burst: 1} }
	})
	for range 20 {
		if rec := e.get("/health/live", false); rec.Code != 200 {
			t.Fatalf("health status = %d", rec.Code)
		}
	}
}

func TestLimiterEvictsIdleClients(t *testing.T) {
	t.Parallel()
	clock := &fakeClock{t: time.Unix(1_700_000_000, 0)}
	l := newIPLimiter(config.RateConfig{RequestsPerMinute: 60, Burst: 5}, clock.Now)

	for _, ip := range []string{"1.1.1.1", "2.2.2.2", "3.3.3.3"} {
		l.allow(ip)
	}
	clock.Advance(9 * time.Minute)
	l.allow("3.3.3.3") // stays active
	clock.Advance(2 * time.Minute)
	l.evict()
	if got := l.size(); got != 1 {
		t.Errorf("clients after eviction = %d, want only the active one", got)
	}
}

func TestServerRunStopsWithContext(t *testing.T) {
	t.Parallel()
	e := newEnv(t)
	ctx, cancel := context.WithCancel(t.Context())
	done := make(chan struct{})
	go func() {
		e.server.Run(ctx)
		close(done)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after its context was cancelled")
	}
}

// ---------- health ----------

func TestHealth(t *testing.T) {
	t.Parallel()

	t.Run("ready", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t)
		if rec := e.get("/health/ready", false); rec.Code != 200 {
			t.Errorf("status = %d; %s", rec.Code, rec.Body.String())
		}
		if e.llm.listCount() != 0 || e.llm.completeCount() != 0 {
			t.Errorf("readiness called the LLM provider: lists=%d completes=%d", e.llm.listCount(), e.llm.completeCount())
		}
		entries, _ := os.ReadDir(e.dataDir)
		if len(entries) != 0 {
			t.Errorf("readiness left files in the data dir: %v", entries)
		}
	})

	t.Run("no providers", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) { o.noProviders = true })
		rec := e.get("/health/ready", false)
		if rec.Code != 503 || !strings.Contains(rec.Body.String(), "providers") {
			t.Errorf("ready = %d %s", rec.Code, rec.Body.String())
		}
		if live := e.get("/health/live", false); live.Code != 200 {
			t.Errorf("live = %d, want 200", live.Code)
		}
	})

	t.Run("certificate not loaded", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) { o.noCert = true })
		if rec := e.get("/health/ready", false); rec.Code != 503 {
			t.Errorf("status = %d", rec.Code)
		}
	})

	t.Run("data directory not writable", func(t *testing.T) {
		t.Parallel()
		e := newEnv(t, func(o *envOptions) {
			o.mutateConfig = func(c *config.Config) { c.Server.DataDir = filepath.Join(c.Server.DataDir, "missing", "dir") }
		})
		rec := e.get("/health/ready", false)
		if rec.Code != 503 || !strings.Contains(rec.Body.String(), "data_dir") {
			t.Errorf("ready = %d %s", rec.Code, rec.Body.String())
		}
	})
}

// ---------- recovery and logging ----------

func TestPanicIsRecovered(t *testing.T) {
	t.Parallel()
	e := newEnv(t)
	e.llm.panicNow = true

	rec := e.analyze(t, baseFields(), nil)
	assertError(t, rec, 500, apierr.Internal)
	if strings.Contains(rec.Body.String(), "simulated failure") {
		t.Error("the panic value leaked to the client")
	}
	if got := strings.Count(e.logs.String(), `"msg":"request"`); got != 1 {
		t.Errorf("access log entries = %d, want exactly 1\n%s", got, e.logs.String())
	}
	if !strings.Contains(e.logs.String(), "panic while serving request") {
		t.Error("the panic was not logged")
	}
}

func logLines(t *testing.T, buf *bytes.Buffer) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("log line is not JSON: %v\n%s", err, line)
		}
		out = append(out, m)
	}
	return out
}

// TestLoggingAndPrivacy is not parallel: it redirects the process temp
// directory to prove that no file is created while analyzing.
func TestLoggingAndPrivacy(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	t.Setenv("TEMP", tmp)
	t.Setenv("TMP", tmp)

	e := newEnv(t)
	certDir := t.TempDir()
	e.llm.reply = `{"status":"answered","correctOptionIds":["B"],"explanation":"MODEL-OUTPUT-EXPLANATION-XYZ","details":null,"confidence":0.9,"warnings":[]}`

	const (
		question = "SECRET-QUESTION-TEXT-12345"
		optText  = "SECRET-OPTION-TEXT-67890"
	)
	imageMarker := []byte("IMAGE-BYTES-MARKER-ABCDEF")
	img := append(append([]byte{}, pngBytes...), imageMarker...)
	fields := []formField{
		{"question", question},
		{"options", `[{"id":"A","text":"` + optText + `"},{"id":"B","text":"other"}]`},
		{"language", "en"},
	}

	rec := e.analyze(t, fields, &formImage{data: img, declaredCT: "image/png", filename: "q.png"})
	if rec.Code != 200 {
		t.Fatalf("status = %d; %s", rec.Code, rec.Body.String())
	}
	// A failing request and an unauthenticated one, to cover error logging.
	e.llm.reply = "prose"
	e.analyze(t, fields, nil)
	e.get("/api/v1/server/info", false)

	lines := logLines(t, e.logs)
	if len(lines) != 3 {
		t.Fatalf("log lines = %d, want exactly one per request:\n%s", len(lines), e.logs.String())
	}
	first := lines[0]
	for _, key := range []string{"request_id", "method", "path", "status", "duration_ms", "provider", "model"} {
		if _, ok := first[key]; !ok {
			t.Errorf("access log lacks %q: %v", key, first)
		}
	}
	if first["method"] != "POST" || first["path"] != "/api/v1/questions/analyze" || first["status"] != float64(200) ||
		first["provider"] != "openrouter" || first["model"] != defaultModel {
		t.Errorf("unexpected fields: %v", first)
	}
	if lines[1]["error_code"] != "LLM_INVALID_RESPONSE" || lines[1]["status"] != float64(502) {
		t.Errorf("failed analysis log = %v", lines[1])
	}
	if lines[2]["error_code"] != "UNAUTHORIZED" {
		t.Errorf("unauthenticated log = %v", lines[2])
	}

	all := e.logs.String()
	for _, secret := range []string{
		testToken, "Bearer", "Authorization", question, optText, string(imageMarker),
		"MODEL-OUTPUT-EXPLANATION-XYZ", "prose", "Which protocol",
	} {
		if strings.Contains(all, secret) {
			t.Errorf("logs contain %q:\n%s", secret, all)
		}
	}

	for _, dir := range []string{tmp, e.dataDir, certDir} {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatal(err)
		}
		if len(entries) != 0 {
			names := make([]string, 0, len(entries))
			for _, en := range entries {
				names = append(names, en.Name())
			}
			t.Errorf("files were created in %s during analysis: %v", dir, names)
		}
	}
}

func TestLogsNeverContainTokenAcrossLevels(t *testing.T) {
	t.Parallel()
	e := newEnv(t)
	req := httptest.NewRequestWithContext(t.Context(), http.MethodGet, "/api/v1/llm/providers?token="+testToken, nil)
	req.Header.Set("Authorization", "Bearer "+testToken)
	e.call(req)
	if strings.Contains(e.logs.String(), testToken) {
		t.Errorf("logs contain the token:\n%s", e.logs.String())
	}
}
