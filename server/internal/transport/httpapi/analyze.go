package httpapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/http"

	"github.com/nyver/test-assistant/server/internal/analysis"
	"github.com/nyver/test-assistant/server/internal/apierr"
)

const (
	// maxFieldBytes bounds each text field. 12 options of 1000 characters at up
	// to 4 bytes each, plus JSON overhead, stay well below it.
	maxFieldBytes = 128 << 10
	// sniffLen is how much of the image http.DetectContentType inspects.
	sniffLen = 512
)

// analyzeForm is the parsed multipart body.
type analyzeForm struct {
	question string
	options  string
	language string
	provider string
	model    string
	image    []byte
	// imageMIME is sniffed from the image content.
	imageMIME string
	seen      map[string]bool
}

type analyzeResponse struct {
	RequestID string `json:"requestId"`
	analysis.Result
}

// analyzeQuestion handles POST /api/v1/questions/analyze. The multipart body is
// streamed part by part and the image is held in memory only: nothing is ever
// written to disk, which multipart.Reader.ReadForm could do for large parts.
func (s *Server) analyzeQuestion(w http.ResponseWriter, r *http.Request) error {
	form, err := s.readAnalyzeForm(r)
	if err != nil {
		return err
	}

	var options []analysis.Option
	if err := json.Unmarshal([]byte(form.options), &options); err != nil {
		return apierr.New(apierr.InvalidRequest, "options must be a JSON array of objects with id and text.")
	}

	req := analysis.Request{
		Question: form.question,
		Options:  options,
		Language: form.language,
		Provider: form.provider,
		Model:    form.model,
	}
	if form.image != nil {
		req.Image = &analysis.Image{MIME: form.imageMIME, Data: form.image}
	}

	result, err := s.deps.Analysis.Analyze(r.Context(), req)
	st := stateFrom(r.Context())
	st.provider, st.model = result.Provider, result.Model // available for the log even on failure
	if err != nil {
		return err
	}

	writeJSON(w, http.StatusOK, analyzeResponse{RequestID: st.id, Result: result})
	return nil
}

func (s *Server) readAnalyzeForm(r *http.Request) (*analyzeForm, error) {
	mediaType, params, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "multipart/form-data" || params["boundary"] == "" {
		return nil, apierr.New(apierr.InvalidRequest, "Content-Type must be multipart/form-data.")
	}

	mr := multipart.NewReader(r.Body, params["boundary"])
	form := &analyzeForm{seen: make(map[string]bool)}
	for {
		part, err := mr.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, partError(err)
		}
		if err := s.readPart(form, part); err != nil {
			return nil, err
		}
	}
	if !form.seen["question"] {
		return nil, apierr.New(apierr.InvalidRequest, "question is required.")
	}
	if !form.seen["options"] {
		return nil, apierr.New(apierr.InvalidRequest, "options is required.")
	}
	return form, nil
}

func (s *Server) readPart(form *analyzeForm, part *multipart.Part) error {
	defer func() { _ = part.Close() }()

	name := part.FormName()
	switch name {
	case "question", "options", "language", "provider", "model":
		if form.seen[name] {
			return apierr.New(apierr.InvalidRequest, fmt.Sprintf("%s must not be repeated.", name))
		}
		form.seen[name] = true
		value, err := readBounded(part, maxFieldBytes)
		if err != nil {
			return err
		}
		switch name {
		case "question":
			form.question = value
		case "options":
			form.options = value
		case "language":
			form.language = value
		case "provider":
			form.provider = value
		case "model":
			form.model = value
		}
		return nil
	case "image":
		if form.seen[name] {
			return apierr.New(apierr.InvalidRequest, "image must not be repeated.")
		}
		form.seen[name] = true
		return s.readImage(form, part)
	default:
		// Unknown fields are ignored; the part is drained by NextPart.
		return nil
	}
}

func (s *Server) readImage(form *analyzeForm, part *multipart.Part) error {
	limit := s.deps.Config.Limits.MaxImageBytes
	data, err := io.ReadAll(io.LimitReader(part, limit+1))
	if err != nil {
		return partError(err)
	}
	if int64(len(data)) > limit {
		return apierr.New(apierr.ImageTooLarge, "Image exceeds the maximum allowed size.")
	}
	if len(data) == 0 {
		return apierr.New(apierr.InvalidRequest, "image must not be empty.")
	}
	// The declared Content-Type is ignored: only the content decides.
	switch mimeType := http.DetectContentType(data[:min(len(data), sniffLen)]); mimeType {
	case "image/jpeg", "image/png", "image/webp":
		form.image, form.imageMIME = data, mimeType
		return nil
	default:
		return apierr.New(apierr.UnsupportedImageType, "Only JPEG, PNG and WebP images are supported.")
	}
}

func readBounded(r io.Reader, limit int64) (string, error) {
	var buf bytes.Buffer
	n, err := io.Copy(&buf, io.LimitReader(r, limit+1))
	if err != nil {
		return "", partError(err)
	}
	if n > limit {
		return "", apierr.New(apierr.InvalidRequest, "A form field is too large.")
	}
	return buf.String(), nil
}

// partError maps a body read failure: exceeding the body limit is 413 and any
// other failure means the multipart body is malformed.
func partError(err error) error {
	if isMaxBytes(err) {
		return apierr.Wrap(apierr.ImageTooLarge, "Request body exceeds the maximum allowed size.", err)
	}
	return apierr.Wrap(apierr.InvalidRequest, "The multipart body is malformed.", err)
}
