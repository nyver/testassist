// Package openaicompat implements llm.Provider for APIs that follow the OpenAI
// chat-completions and models conventions, such as OpenRouter, RouterAI,
// Ollama and vLLM.
package openaicompat

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net"
	"net/http"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/llm"
)

const (
	maxAttempts = 3
	// jitterFraction spreads retry delays by ±20%.
	jitterFraction = 0.2
	// errorBodyLimit bounds how much of a failing reply is read for
	// classification. The bytes are never returned or logged.
	errorBodyLimit = 64 << 10
	// wsaeconnreset is WSAECONNRESET, which Go does not map to
	// syscall.ECONNRESET on Windows.
	wsaeconnreset = syscall.Errno(10054)
)

// backoff holds the delays before the second and third attempt.
var backoff = [maxAttempts - 1]time.Duration{500 * time.Millisecond, 1500 * time.Millisecond}

// Options configures a Client.
type Options struct {
	BaseURL string
	// APIKey is sent as a Bearer token. Empty means no Authorization header.
	APIKey string
	// Headers are extra request headers, for example OpenRouter's X-Title.
	Headers map[string]string
	// ConnectTimeout bounds dialing. The total time of a call comes from the
	// caller's context, which covers every retry.
	ConnectTimeout time.Duration
	// ResponseHeaderTimeout bounds waiting for response headers. Zero disables it.
	ResponseHeaderTimeout time.Duration
	// MaxBodyBytes bounds the upstream response body that is read.
	MaxBodyBytes int64
}

// OptionsFromConfig derives client options from a provider's configuration and
// the shared timeouts and limits.
func OptionsFromConfig(p config.ProviderConfig, cfg *config.Config) Options {
	return Options{
		BaseURL:               p.BaseURL,
		APIKey:                p.APIKey,
		Headers:               p.Headers,
		ConnectTimeout:        cfg.Timeouts.Connect,
		ResponseHeaderTimeout: cfg.Timeouts.LLM,
		MaxBodyBytes:          cfg.LLM.MaxUpstreamBodyBytes,
	}
}

// Client talks to one OpenAI-compatible endpoint.
type Client struct {
	baseURL  string
	apiKey   string
	headers  map[string]string
	maxBody  int64
	http     *http.Client
	sleep    func(ctx context.Context, d time.Duration) error
	jitter   func() float64 // returns a value in [-1, 1)
	attempts int
}

var _ llm.Provider = (*Client)(nil)

// New builds a client with its own transport and no client-level total timeout.
func New(opts Options) *Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.DialContext = (&net.Dialer{Timeout: opts.ConnectTimeout, KeepAlive: 30 * time.Second}).DialContext
	transport.TLSHandshakeTimeout = opts.ConnectTimeout
	transport.ResponseHeaderTimeout = opts.ResponseHeaderTimeout

	return &Client{
		baseURL: strings.TrimRight(opts.BaseURL, "/"),
		apiKey:  opts.APIKey,
		headers: opts.Headers,
		maxBody: opts.MaxBodyBytes,
		http: &http.Client{
			Transport: transport,
			// A redirect would carry the request to an unexpected host.
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		},
		sleep:    sleepContext,
		jitter:   func() float64 { return rand.Float64()*2 - 1 }, // #nosec G404 -- jitter is not security relevant.
		attempts: maxAttempts,
	}
}

func sleepContext(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// Complete sends one chat-completion request and returns the model's text.
func (c *Client) Complete(ctx context.Context, req llm.ChatRequest) (llm.ChatResponse, error) {
	body, err := buildRequestBody(req)
	if err != nil {
		return llm.ChatResponse{}, &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "encode request"}
	}
	raw, err := c.do(ctx, http.MethodPost, "/chat/completions", body)
	if err != nil {
		return llm.ChatResponse{}, err
	}
	content, err := parseCompletion(raw)
	if err != nil {
		return llm.ChatResponse{}, err
	}
	return llm.ChatResponse{Content: content}, nil
}

// ListModels fetches the provider's model listing. When an entry declares
// input modalities (OpenRouter), vision is true only if "image" is listed;
// entries without modalities default to text-only.
func (c *Client) ListModels(ctx context.Context) ([]llm.Model, error) {
	raw, err := c.do(ctx, http.MethodGet, "/models", nil)
	if err != nil {
		return nil, err
	}
	return parseModels(raw)
}

// do performs a request with the retry policy: only 429, 502, 503, 504 and
// connection resets are retried, at most c.attempts times in total, within the
// deadline of ctx.
func (c *Client) do(ctx context.Context, method, path string, body []byte) ([]byte, error) {
	var lastErr *llm.Error
	for attempt := 1; attempt <= c.attempts; attempt++ {
		raw, retryAfter, err := c.once(ctx, method, path, body)
		if err == nil {
			return raw, nil
		}
		var apiErr *llm.Error
		if !errors.As(err, &apiErr) {
			return nil, err // context cancellation by the caller
		}
		lastErr = apiErr
		if !retryable(apiErr) || attempt == c.attempts {
			return nil, apiErr
		}

		delay := c.backoffDelay(attempt)
		if retryAfter > 0 {
			delay = retryAfter
		}
		if deadline, ok := ctx.Deadline(); ok && time.Until(deadline) <= delay {
			return nil, apiErr // waiting would consume the whole remaining budget
		}
		if err := c.sleep(ctx, delay); err != nil {
			return nil, contextError(err, apiErr)
		}
	}
	return nil, lastErr
}

func (c *Client) backoffDelay(attempt int) time.Duration {
	base := backoff[attempt-1]
	return time.Duration(float64(base) * (1 + jitterFraction*c.jitter()))
}

// retryable reports whether a failure is transient: a retryable HTTP status or
// a connection reset.
func retryable(err *llm.Error) bool {
	switch err.UpstreamStatus {
	case http.StatusTooManyRequests, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
		return true
	}
	return err.Transient
}

// once performs a single HTTP exchange and classifies the outcome.
func (c *Client) once(ctx context.Context, method, path string, body []byte) (raw []byte, retryAfter time.Duration, err error) {
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, reader)
	if err != nil {
		return nil, 0, &llm.Error{Kind: llm.ErrProviderUnavailable, Detail: "build request"}
	}
	for k, v := range c.headers {
		req.Header.Set(k, v)
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}

	resp, err := c.http.Do(req) // #nosec G704 -- the URL comes from operator configuration.
	if err != nil {
		return nil, 0, classifyTransportError(ctx, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, parseRetryAfter(resp.Header.Get("Retry-After")), classifyStatus(resp)
	}

	limit := c.maxBody
	data, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, 0, classifyTransportError(ctx, err)
	}
	if int64(len(data)) > limit {
		return nil, 0, &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "response body exceeds the size limit"}
	}
	return data, 0, nil
}

// classifyTransportError maps a failure to send or receive to an llm.Error. A
// cancellation by the caller is returned unchanged so it can stop the retry
// loop; it is not an upstream problem.
func classifyTransportError(ctx context.Context, err error) error {
	switch {
	case errors.Is(err, context.DeadlineExceeded) || isNetTimeout(err):
		return &llm.Error{Kind: llm.ErrTimeout}
	case errors.Is(err, context.Canceled) || ctx.Err() != nil:
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return &llm.Error{Kind: llm.ErrTimeout}
		}
		return context.Canceled
	case isConnectionReset(err):
		return &llm.Error{Kind: llm.ErrProviderUnavailable, Detail: "connection reset", Transient: true}
	default:
		return &llm.Error{Kind: llm.ErrProviderUnavailable, Detail: "network error"}
	}
}

// contextError converts a context error hit while sleeping between attempts.
func contextError(err error, last *llm.Error) error {
	if errors.Is(err, context.DeadlineExceeded) {
		return &llm.Error{Kind: llm.ErrTimeout}
	}
	if errors.Is(err, context.Canceled) {
		return context.Canceled
	}
	return last
}

func isNetTimeout(err error) bool {
	var ne net.Error
	return errors.As(err, &ne) && ne.Timeout()
}

func isConnectionReset(err error) bool {
	return errors.Is(err, syscall.ECONNRESET) ||
		errors.Is(err, wsaeconnreset) ||
		errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.Is(err, io.EOF)
}

// classifyStatus maps a non-200 reply to an llm.Error per the design's error
// table. The body is read only to spot "unknown model" and is discarded.
func classifyStatus(resp *http.Response) *llm.Error {
	status := resp.StatusCode
	switch status {
	case http.StatusNotFound:
		return &llm.Error{Kind: llm.ErrModelNotFound, UpstreamStatus: status}
	case http.StatusBadRequest:
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, errorBodyLimit))
		if mentionsUnknownModel(string(snippet)) {
			return &llm.Error{Kind: llm.ErrModelNotFound, UpstreamStatus: status}
		}
	}
	return &llm.Error{Kind: llm.ErrProviderUnavailable, UpstreamStatus: status}
}

func mentionsUnknownModel(body string) bool {
	b := strings.ToLower(body)
	return strings.Contains(b, "not a valid model") ||
		strings.Contains(b, "model not found") ||
		strings.Contains(b, "no such model") ||
		(strings.Contains(b, "model") && strings.Contains(b, "does not exist"))
}

func parseRetryAfter(v string) time.Duration {
	secs, err := strconv.Atoi(strings.TrimSpace(v))
	if err != nil || secs <= 0 {
		return 0
	}
	return time.Duration(secs) * time.Second
}

// --- request and response bodies ---

type chatRequest struct {
	Model          string          `json:"model"`
	Messages       []chatMessage   `json:"messages"`
	MaxTokens      int             `json:"max_tokens,omitempty"`
	ResponseFormat *responseFormat `json:"response_format,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type contentPart struct {
	Type     string    `json:"type"`
	Text     string    `json:"text,omitempty"`
	ImageURL *imageURL `json:"image_url,omitempty"`
}

type imageURL struct {
	URL string `json:"url"`
}

type responseFormat struct {
	Type       string      `json:"type"`
	JSONSchema *jsonSchema `json:"json_schema,omitempty"`
}

type jsonSchema struct {
	Name   string          `json:"name"`
	Strict bool            `json:"strict"`
	Schema json.RawMessage `json:"schema"`
}

func buildRequestBody(req llm.ChatRequest) ([]byte, error) {
	var user any = req.User
	if req.Image != nil {
		dataURL := "data:" + req.Image.MIME + ";base64," + base64.StdEncoding.EncodeToString(req.Image.Data)
		user = []contentPart{
			{Type: "text", Text: req.User},
			{Type: "image_url", ImageURL: &imageURL{URL: dataURL}},
		}
	}

	cr := chatRequest{
		Model: req.Model,
		Messages: []chatMessage{
			{Role: "system", Content: req.System},
			{Role: "user", Content: user},
		},
		MaxTokens: req.MaxTokens,
	}
	switch req.StructuredOutput {
	case config.StructuredOutputJSONObject:
		cr.ResponseFormat = &responseFormat{Type: "json_object"}
	case config.StructuredOutputJSONSchema:
		if len(req.ResponseSchema) > 0 {
			cr.ResponseFormat = &responseFormat{
				Type:       "json_schema",
				JSONSchema: &jsonSchema{Name: "answer", Strict: true, Schema: req.ResponseSchema},
			}
		}
	}
	return json.Marshal(cr)
}

type completionReply struct {
	Choices []struct {
		Message struct {
			Content json.RawMessage `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error json.RawMessage `json:"error"`
}

func parseCompletion(raw []byte) (string, error) {
	var reply completionReply
	if err := json.Unmarshal(raw, &reply); err != nil {
		return "", &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "reply is not valid JSON"}
	}
	if len(reply.Choices) == 0 {
		if len(reply.Error) > 0 && string(reply.Error) != "null" {
			// Some gateways report failures with HTTP 200 and an error object.
			return "", &llm.Error{Kind: llm.ErrProviderUnavailable, Detail: "provider reported an error"}
		}
		return "", &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "reply has no choices"}
	}
	content, err := messageText(reply.Choices[0].Message.Content)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(content) == "" {
		return "", &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "reply content is empty"}
	}
	return content, nil
}

// messageText accepts content as a string or as an array of text parts.
func messageText(raw json.RawMessage) (string, error) {
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s, nil
	}
	var parts []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if err := json.Unmarshal(raw, &parts); err != nil {
		return "", &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "reply content has an unexpected type"}
	}
	var sb strings.Builder
	for _, p := range parts {
		if p.Type == "" || p.Type == "text" {
			sb.WriteString(p.Text)
		}
	}
	return sb.String(), nil
}

type modelsReply struct {
	Data []struct {
		ID           string `json:"id"`
		Name         string `json:"name"`
		Architecture struct {
			InputModalities []string `json:"input_modalities"`
		} `json:"architecture"`
	} `json:"data"`
}

func parseModels(raw []byte) ([]llm.Model, error) {
	var reply modelsReply
	if err := json.Unmarshal(raw, &reply); err != nil {
		return nil, &llm.Error{Kind: llm.ErrInvalidResponse, Detail: "models reply is not valid JSON"}
	}
	models := make([]llm.Model, 0, len(reply.Data))
	for _, d := range reply.Data {
		if d.ID == "" {
			continue
		}
		name := d.Name
		if name == "" {
			name = d.ID
		}
		vision := false
		for _, m := range d.Architecture.InputModalities {
			if strings.EqualFold(m, "image") {
				vision = true
			}
		}
		models = append(models, llm.Model{
			ID:           d.ID,
			Name:         name,
			Capabilities: llm.Capabilities{Text: true, Vision: vision},
		})
	}
	return models, nil
}

// String makes accidental logging of a Client safe: it never prints the key.
func (c *Client) String() string {
	return fmt.Sprintf("openaicompat(%s)", c.baseURL)
}
