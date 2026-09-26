package app

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/tlscert"
)

const testToken = "integration-test-token"

const answerJSON = `{"status":"answered","correctOptionIds":["B"],"explanation":"because","details":null,"confidence":0.9,"warnings":[]}`

// lockedBuffer is a bytes.Buffer safe for concurrent use.
type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *lockedBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

type harness struct {
	cfg      *config.Config
	baseURL  string
	client   *http.Client
	stdout   *lockedBuffer
	logs     *lockedBuffer
	done     chan error
	cancel   context.CancelFunc
	upstream *fakeUpstream
}

// fakeUpstream is a plain-HTTP OpenAI-compatible endpoint.
type fakeUpstream struct {
	srv      *httptest.Server
	requests atomic.Int32
	entered  chan struct{} // receives one value per chat request
	release  chan struct{} // chat requests block until it is closed
}

func newFakeUpstream(t *testing.T) *fakeUpstream {
	t.Helper()
	u := &fakeUpstream{entered: make(chan struct{}, 8), release: make(chan struct{})}
	u.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u.requests.Add(1)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.HasSuffix(r.URL.Path, "/chat/completions"):
			u.entered <- struct{}{}
			<-u.release
			out, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{"message": map[string]any{"content": answerJSON}}}})
			_, _ = w.Write(out)
		default: // /models
			_, _ = io.WriteString(w, `{"data":[]}`)
		}
	}))
	t.Cleanup(u.srv.Close)
	return u
}

func startServer(t *testing.T) *harness {
	t.Helper()
	dir := t.TempDir()
	up := newFakeUpstream(t)

	cfg := config.Default()
	cfg.Server.DataDir = filepath.Join(dir, "data")
	cfg.TLS.CertFile = filepath.Join(dir, "certs", "server.crt")
	cfg.TLS.KeyFile = filepath.Join(dir, "certs", "server.key")
	cfg.Security.AuthToken = testToken
	cfg.Timeouts.Shutdown = 10 * time.Second
	cfg.LLM.Providers = []config.ProviderConfig{{
		ID: "fake", Name: "Fake", Type: config.ProviderTypeOpenAICompatible, BaseURL: up.srv.URL,
		Enabled: true, DefaultModel: "test/model",
		Models: []config.ModelConfig{{ID: "test/model", Vision: new(bool)}},
	}}
	cfg.LLM.DefaultProvider = "fake"

	ln, err := (&net.ListenConfig{}).Listen(t.Context(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	cfg.Server.Listen = ln.Addr().String()

	h := &harness{cfg: &cfg, stdout: &lockedBuffer{}, logs: &lockedBuffer{}, done: make(chan error, 1), upstream: up}
	ready := make(chan struct{})
	ctx, cancel := context.WithCancel(t.Context())
	h.cancel = cancel
	go func() {
		h.done <- Serve(ctx, &cfg, Options{
			Version:  "test",
			Stdout:   h.stdout,
			Logger:   slog.New(slog.NewJSONHandler(h.logs, nil)),
			Listener: ln,
			Ready:    func() { close(ready) },
		})
	}()
	select {
	case <-ready:
	case err := <-h.done:
		t.Fatalf("Serve returned before it was ready: %v", err)
	case <-time.After(20 * time.Second):
		t.Fatal("server did not become ready")
	}
	t.Cleanup(func() {
		cancel()
		select {
		case <-h.done:
		default:
			// Already collected by the test, or still stopping; either is fine.
		}
	})

	// Pin trust to the certificate the server generated: the only trust anchor.
	pemBytes, err := os.ReadFile(cfg.TLS.CertFile)
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pemBytes) {
		t.Fatal("could not parse the generated certificate")
	}
	h.baseURL = "https://" + ln.Addr().String()
	h.client = &http.Client{
		Timeout:   30 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
	}
	t.Cleanup(h.client.CloseIdleConnections)
	return h
}

func (h *harness) do(t *testing.T, method, path string, body io.Reader, header http.Header) *http.Response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), method, h.baseURL+path, body)
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range header {
		req.Header[k] = v
	}
	resp, err := h.client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	return resp
}

func analyzeRequest(t *testing.T) (io.Reader, http.Header) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	_ = mw.WriteField("question", "Which one?")
	_ = mw.WriteField("options", `[{"id":"A","text":"one"},{"id":"B","text":"two"}]`)
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return &buf, http.Header{
		"Content-Type":  {mw.FormDataContentType()},
		"Authorization": {"Bearer " + testToken},
	}
}

func TestServeOverPinnedHTTPS(t *testing.T) {
	t.Parallel()
	h := startServer(t)

	resp := h.do(t, http.MethodGet, "/health/live", nil, nil)
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("live = %d", resp.StatusCode)
	}
	if resp.TLS == nil || resp.TLS.Version < tls.VersionTLS12 {
		t.Errorf("connection is not TLS 1.2 or newer: %+v", resp.TLS)
	}

	resp = h.do(t, http.MethodGet, "/api/v1/server/info", nil, http.Header{"Authorization": {"Bearer " + testToken}})
	var info map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != 200 || info["version"] != "test" || info["serverId"] == "" || info["name"] != "Test Assistant" {
		t.Errorf("info = %d %v", resp.StatusCode, info)
	}

	// Startup output required by the specification.
	fp, err := tlscert.FingerprintFromFile(h.cfg.TLS.CertFile)
	if err != nil {
		t.Fatal(err)
	}
	out := h.stdout.String()
	if !strings.Contains(out, "HTTPS listening on "+h.cfg.Server.Listen) ||
		!strings.Contains(out, "Certificate SHA-256 fingerprint: "+fp) {
		t.Errorf("startup output = %q", out)
	}
	if strings.Contains(h.logs.String(), testToken) {
		t.Error("the token appears in the logs")
	}
}

func TestPlaintextHTTPIsNotServed(t *testing.T) {
	t.Parallel()
	h := startServer(t)

	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, "http://"+strings.TrimPrefix(h.baseURL, "https://")+"/health/live", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		return // the connection was dropped: not served either
	}
	defer func() { _ = resp.Body.Close() }()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusOK || resp.Header.Get("X-Request-ID") != "" || strings.Contains(string(body), `"ok"`) {
		t.Errorf("a plaintext request reached the API: %d %q", resp.StatusCode, body)
	}
}

func TestHealthCheckAgainstRunningServer(t *testing.T) {
	t.Parallel()
	h := startServer(t)

	// The configured provider has no API key requirement, so the server is ready.
	if err := HealthCheck(t.Context(), h.cfg); err != nil {
		t.Fatalf("HealthCheck: %v", err)
	}

	t.Run("a different certificate is not trusted", func(t *testing.T) {
		other := *h.cfg
		other.TLS.CertFile = filepath.Join(t.TempDir(), "other.crt")
		other.TLS.KeyFile = filepath.Join(t.TempDir(), "other.key")
		if _, err := tlscert.LoadOrGenerate(tlscert.Options{CertFile: other.TLS.CertFile, KeyFile: other.TLS.KeyFile, Name: "other"}); err != nil {
			t.Fatal(err)
		}
		if err := HealthCheck(t.Context(), &other); err == nil {
			t.Error("HealthCheck must fail when the served certificate does not match the configured one")
		}
	})

	t.Run("missing certificate file", func(t *testing.T) {
		other := *h.cfg
		other.TLS.CertFile = filepath.Join(t.TempDir(), "absent.crt")
		if err := HealthCheck(t.Context(), &other); err == nil {
			t.Error("expected an error")
		}
	})
}

func TestGracefulShutdownFinishesInFlightRequest(t *testing.T) {
	t.Parallel()
	h := startServer(t)

	type result struct {
		status int
		body   string
		err    error
	}
	got := make(chan result, 1)
	go func() {
		body, header := analyzeRequest(t)
		req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, h.baseURL+"/api/v1/questions/analyze", body)
		if err != nil {
			got <- result{err: err}
			return
		}
		req.Header = header
		resp, err := h.client.Do(req)
		if err != nil {
			got <- result{err: err}
			return
		}
		defer func() { _ = resp.Body.Close() }()
		b, _ := io.ReadAll(resp.Body)
		got <- result{status: resp.StatusCode, body: string(b)}
	}()

	<-h.upstream.entered // the request is now being served
	h.cancel()           // SIGTERM equivalent

	select {
	case err := <-h.done:
		t.Fatalf("Serve returned while a request was in flight: %v", err)
	case <-time.After(150 * time.Millisecond):
	}

	close(h.upstream.release) // let the "LLM" answer
	r := <-got
	if r.err != nil || r.status != http.StatusOK || !strings.Contains(r.body, `"answered"`) {
		t.Fatalf("in-flight request = %+v", r)
	}
	select {
	case err := <-h.done:
		if err != nil {
			t.Errorf("Serve = %v, want nil after a clean shutdown", err)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("Serve did not return after the in-flight request finished")
	}

	// The listener is closed: nothing accepts connections any more.
	conn, err := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(t.Context(), "tcp", h.cfg.Server.Listen)
	if err == nil {
		_ = conn.Close()
		t.Error("the listener still accepts connections after shutdown")
	}
}

func TestServeRestartKeepsIdentityAndCertificate(t *testing.T) {
	t.Parallel()
	first := startServer(t)
	fp1, err := tlscert.FingerprintFromFile(first.cfg.TLS.CertFile)
	if err != nil {
		t.Fatal(err)
	}
	info1 := readInfo(t, first)
	first.cancel()
	close(first.upstream.release)
	if err := <-first.done; err != nil {
		t.Fatalf("first server: %v", err)
	}

	// Start again on the same directories.
	ln, err := (&net.ListenConfig{}).Listen(t.Context(), "tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	cfg := *first.cfg
	cfg.Server.Listen = ln.Addr().String()
	ready := make(chan struct{})
	ctx, cancel := context.WithCancel(t.Context())
	done := make(chan error, 1)
	go func() {
		done <- Serve(ctx, &cfg, Options{Version: "test", Stdout: io.Discard, Logger: slog.New(slog.NewJSONHandler(io.Discard, nil)), Listener: ln, Ready: func() { close(ready) }})
	}()
	<-ready
	defer func() {
		cancel()
		if err := <-done; err != nil && !errors.Is(err, context.Canceled) {
			t.Errorf("second server: %v", err)
		}
	}()

	fp2, err := tlscert.FingerprintFromFile(cfg.TLS.CertFile)
	if err != nil {
		t.Fatal(err)
	}
	if fp1 != fp2 {
		t.Errorf("fingerprint changed across restart: %s -> %s", fp1, fp2)
	}
	second := &harness{cfg: &cfg, baseURL: "https://" + ln.Addr().String(), client: first.client}
	if info2 := readInfo(t, second); info2 != info1 {
		t.Errorf("serverId changed across restart: %s -> %s", info1, info2)
	}
}

func readInfo(t *testing.T, h *harness) string {
	t.Helper()
	resp := h.do(t, http.MethodGet, "/api/v1/server/info", nil, http.Header{"Authorization": {"Bearer " + testToken}})
	defer func() { _ = resp.Body.Close() }()
	var info map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		t.Fatal(err)
	}
	return info["serverId"]
}
