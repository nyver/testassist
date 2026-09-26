// Package analysis is the question-analysis use case: it validates a request,
// resolves the provider and model, gates image input on the model's vision
// capability, builds the prompt, calls the LLM and turns its untrusted output
// into a validated, normalized answer.
package analysis

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/nyver/test-assistant/server/internal/apierr"
	"github.com/nyver/test-assistant/server/internal/config"
	"github.com/nyver/test-assistant/server/internal/llm"
)

// Request limits from the API contract.
const (
	maxQuestionChars = 4000
	minOptions       = 2
	maxOptions       = 12
	maxOptionIDChars = 8
	maxOptionChars   = 1000
	maxLanguageChars = 35
	defaultLanguage  = "en"
)

// Confidence levels.
const (
	LevelHigh   = "high"
	LevelMedium = "medium"
	LevelLow    = "low"
)

// insufficientDataWarning is added to an uncertain answer that has no warnings.
const insufficientDataWarning = "The model could not determine the answer from the provided data."

// languageTag accepts BCP 47 tags such as "en", "ru", "pt-BR" and "zh-Hant-TW".
var languageTag = regexp.MustCompile(`^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$`)

// Option is one answer option of the question.
type Option struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

// Image is an uploaded image whose type has already been verified.
type Image struct {
	MIME string
	Data []byte
}

// Request is a question to analyze.
type Request struct {
	Question string
	Options  []Option
	Language string
	Provider string
	Model    string
	Image    *Image

	// ImageOnly marks a request without text: Question and Options are empty
	// and the model reads them from Image, which is then required.
	ImageOnly bool
}

// Result is a validated, normalized answer. The JSON tags match the analyze
// response of the API, minus the request id that the transport adds.
type Result struct {
	Status           string   `json:"status"`
	CorrectOptionIDs []string `json:"correctOptionIds"`
	AnswerText       *string  `json:"answerText"`
	Explanation      *string  `json:"explanation"`
	Details          *string  `json:"details"`
	Confidence       float64  `json:"confidence"`
	ConfidenceLevel  string   `json:"confidenceLevel"`
	Warnings         []string `json:"warnings"`
	Provider         string   `json:"provider"`
	Model            string   `json:"model"`

	// RecognizedQuestion and RecognizedOptions are what the model read from
	// the image of an image-only request; absent otherwise.
	RecognizedQuestion string   `json:"recognizedQuestion,omitempty"`
	RecognizedOptions  []Option `json:"recognizedOptions,omitempty"`
}

// Settings are the analysis parameters taken from configuration.
type Settings struct {
	Timeout    time.Duration
	MaxTokens  int
	Confidence config.ConfidenceConfig
}

// Service runs analyses against the registered providers.
type Service struct {
	registry *llm.Registry
	set      Settings
}

// NewService returns a Service that uses reg to reach LLM providers.
func NewService(reg *llm.Registry, set Settings) *Service {
	return &Service{registry: reg, set: set}
}

// Analyze validates and analyzes a question. Provider and Model of the returned
// Result are filled as soon as they are resolved, even when an error follows,
// so callers can log them. Errors are *apierr.Error, except a cancellation of
// ctx, which is returned as is.
func (s *Service) Analyze(ctx context.Context, req Request) (Result, error) {
	req, err := normalizeRequest(req)
	if err != nil {
		return Result{}, err
	}

	res := Result{}
	providerID, err := s.resolveProvider(req.Provider)
	if err != nil {
		return res, err
	}
	res.Provider = providerID

	model, err := s.resolveModel(ctx, providerID, req.Model)
	if err != nil {
		return res, err
	}
	res.Model = model.ID

	if req.Image != nil && !model.Capabilities.Vision {
		return res, apierr.New(apierr.ModelDoesNotSupportVision, "The selected model does not support image input.")
	}

	provider, _ := s.registry.Provider(providerID)
	callCtx, cancel := context.WithTimeout(ctx, s.set.Timeout)
	defer cancel()

	chat := llm.ChatRequest{
		Model:            model.ID,
		System:           systemPrompt,
		User:             buildUserMessage(req.Question, req.Options, req.Language),
		MaxTokens:        s.set.MaxTokens,
		StructuredOutput: model.StructuredOutput,
		ResponseSchema:   answerSchema,
	}
	if req.ImageOnly {
		chat.System = imageOnlySystemPrompt
		chat.User = buildImageOnlyUserMessage(req.Language)
		chat.ResponseSchema = imageOnlyAnswerSchema
	}
	if req.Image != nil {
		chat.Image = &llm.Image{MIME: req.Image.MIME, Data: req.Image.Data}
	}

	reply, err := provider.Complete(callCtx, chat)
	if err != nil {
		return res, mapLLMError(ctx, err)
	}

	var ans modelAnswer
	if req.ImageOnly {
		ans, err = parseImageAnswer(reply.Content)
	} else {
		ids := make(map[string]bool, len(req.Options))
		for _, o := range req.Options {
			ids[o.ID] = true
		}
		ans, err = parseAnswer(reply.Content, ids)
	}
	if err != nil {
		return res, apierr.Wrap(apierr.LLMInvalidResponse, "The LLM returned an invalid response.", err)
	}

	options := req.Options
	if req.ImageOnly {
		options = ans.Options
		res.RecognizedQuestion, res.RecognizedOptions = ans.Question, ans.Options
	}
	return s.buildResult(res, options, ans), nil
}

// normalizeRequest trims and validates the request fields.
func normalizeRequest(req Request) (Request, error) {
	invalid := func(format string, args ...any) error {
		return apierr.New(apierr.InvalidRequest, fmt.Sprintf(format, args...))
	}

	if req.ImageOnly {
		if req.Image == nil {
			return req, invalid("image is required when question and options are omitted.")
		}
		req.Question, req.Options = "", nil
	} else {
		var err error
		if req, err = normalizeQuestion(req); err != nil {
			return req, err
		}
	}

	req.Language = strings.TrimSpace(req.Language)
	if req.Language == "" {
		req.Language = defaultLanguage
	}
	if len(req.Language) > maxLanguageChars || !languageTag.MatchString(req.Language) {
		return req, invalid("language must be a BCP 47 language tag.")
	}
	return req, nil
}

// normalizeQuestion trims and validates the question and options.
func normalizeQuestion(req Request) (Request, error) {
	invalid := func(format string, args ...any) error {
		return apierr.New(apierr.InvalidRequest, fmt.Sprintf(format, args...))
	}

	req.Question = strings.TrimSpace(req.Question)
	if n := utf8.RuneCountInString(req.Question); n < 1 || n > maxQuestionChars {
		return req, invalid("question must be between 1 and %d characters.", maxQuestionChars)
	}
	if n := len(req.Options); n < minOptions || n > maxOptions {
		return req, invalid("options must contain between %d and %d items.", minOptions, maxOptions)
	}

	seen := make(map[string]bool, len(req.Options))
	options := make([]Option, len(req.Options))
	for i, o := range req.Options {
		id := strings.TrimSpace(o.ID)
		text := strings.TrimSpace(o.Text)
		if n := utf8.RuneCountInString(id); n < 1 || n > maxOptionIDChars {
			return req, invalid("option ids must be between 1 and %d characters.", maxOptionIDChars)
		}
		if seen[id] {
			return req, invalid("option ids must be unique.")
		}
		seen[id] = true
		if n := utf8.RuneCountInString(text); n < 1 || n > maxOptionChars {
			return req, invalid("option texts must be between 1 and %d characters.", maxOptionChars)
		}
		options[i] = Option{ID: id, Text: text}
	}
	req.Options = options
	return req, nil
}

func (s *Service) resolveProvider(id string) (string, error) {
	if id == "" {
		id = s.registry.DefaultProviderID()
	}
	if id == "" || !s.registry.Has(id) {
		return "", apierr.New(apierr.ProviderNotFound, "Provider not found.")
	}
	return id, nil
}

func (s *Service) resolveModel(ctx context.Context, providerID, modelID string) (llm.Model, error) {
	if modelID == "" {
		modelID = s.registry.DefaultModel(providerID)
	}
	if modelID == "" {
		return llm.Model{}, apierr.New(apierr.InvalidRequest, "model is required because the provider has no default model.")
	}
	model, found, err := s.registry.FindModel(ctx, providerID, modelID)
	if err != nil {
		return llm.Model{}, apierr.Wrap(apierr.Internal, "Internal server error.", err)
	}
	if !found {
		return llm.Model{}, apierr.New(apierr.ModelNotFound, "Model not found.")
	}
	return model, nil
}

// mapLLMError converts an adapter failure to an API error. A cancellation of
// the caller's context is passed through: the client is gone.
func mapLLMError(ctx context.Context, err error) error {
	switch {
	case ctx.Err() != nil && errors.Is(err, context.Canceled):
		return err
	case errors.Is(err, llm.ErrTimeout), errors.Is(err, context.DeadlineExceeded):
		return apierr.Wrap(apierr.LLMTimeout, "The LLM provider did not respond in time.", err)
	case errors.Is(err, llm.ErrModelNotFound):
		return apierr.Wrap(apierr.ModelNotFound, "Model not found.", err)
	case errors.Is(err, llm.ErrInvalidResponse):
		return apierr.Wrap(apierr.LLMInvalidResponse, "The LLM returned an invalid response.", err)
	case errors.Is(err, llm.ErrProviderUnavailable):
		return apierr.Wrap(apierr.LLMProviderUnavailable, "The LLM provider is unavailable.", err)
	default:
		return apierr.Wrap(apierr.Internal, "Internal server error.", err)
	}
}

// buildResult normalizes a validated answer: uncertain answers lose their
// option ids and gain a warning if they have none, answered ones get the
// answer text (duplicate ids are dropped), and the numeric confidence is mapped
// to a level.
func (s *Service) buildResult(res Result, options []Option, ans modelAnswer) Result {
	res.Status = ans.Status
	res.Explanation = ans.Explanation
	res.Details = ans.Details
	res.Confidence = ans.Confidence
	res.ConfidenceLevel = s.confidenceLevel(ans.Confidence)
	res.Warnings = append([]string{}, ans.Warnings...)

	if ans.Status == StatusUncertain {
		res.CorrectOptionIDs = []string{}
		res.AnswerText = nil
		if len(res.Warnings) == 0 {
			res.Warnings = []string{insufficientDataWarning}
		}
		return res
	}

	chosen := make(map[string]bool, len(ans.CorrectOptionIDs))
	ids := make([]string, 0, len(ans.CorrectOptionIDs))
	for _, id := range ans.CorrectOptionIDs {
		if !chosen[id] {
			chosen[id] = true
			ids = append(ids, id)
		}
	}
	res.CorrectOptionIDs = ids

	// The answer text follows the order of the request options, not the order
	// in which the model listed its choices.
	texts := make([]string, 0, len(chosen))
	for _, o := range options {
		if chosen[o.ID] {
			texts = append(texts, o.Text)
		}
	}
	text := strings.Join(texts, "; ")
	res.AnswerText = &text
	return res
}

func (s *Service) confidenceLevel(c float64) string {
	switch {
	case c >= s.set.Confidence.High:
		return LevelHigh
	case c >= s.set.Confidence.Medium:
		return LevelMedium
	default:
		return LevelLow
	}
}
