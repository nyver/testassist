package analysis

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

// Answer statuses.
const (
	StatusAnswered  = "answered"
	StatusUncertain = "uncertain"
)

// modelAnswer is a validated answer as returned by the model, before
// normalization.
type modelAnswer struct {
	Status           string
	CorrectOptionIDs []string
	Explanation      *string
	Details          *string
	Confidence       float64
	Warnings         []string

	// Question and Options are what the model read from the image of an
	// image-only request. They stay empty for a request with text.
	Question string
	Options  []Option
}

// errInvalidAnswer marks any violation of the answer contract. Its messages
// name the violated rule only: they never repeat model output, so they are safe
// to log.
var errInvalidAnswer = errors.New("invalid model answer")

func invalidf(format string, args ...any) error {
	return fmt.Errorf("%w: %s", errInvalidAnswer, fmt.Sprintf(format, args...))
}

// parseAnswer validates the model's raw output against the answer contract:
// a single JSON object, optionally wrapped in one Markdown code fence, with all
// required fields of the right type, a confidence within 0..1, option ids taken
// from validIDs, and at least one id when the status is "answered".
func parseAnswer(raw string, validIDs map[string]bool) (modelAnswer, error) {
	fields, err := decodeObject(raw)
	if err != nil {
		return modelAnswer{}, err
	}
	ans, err := parseCore(fields)
	if err != nil {
		return modelAnswer{}, err
	}
	if err := checkIDs(ans, validIDs); err != nil {
		return modelAnswer{}, err
	}
	return ans, nil
}

// parseImageAnswer validates the output for an image-only request. The model
// also reports the question and options it read from the image; the answer's
// option ids must come from those. An uncertain answer may leave them out.
func parseImageAnswer(raw string) (modelAnswer, error) {
	fields, err := decodeObject(raw)
	if err != nil {
		return modelAnswer{}, err
	}
	ans, err := parseCore(fields)
	if err != nil {
		return modelAnswer{}, err
	}

	question, options, err := recognized(fields)
	switch {
	case err == nil:
		ans.Question, ans.Options = question, options
	case ans.Status == StatusAnswered:
		return modelAnswer{}, err
	}

	validIDs := make(map[string]bool, len(ans.Options))
	for _, o := range ans.Options {
		validIDs[o.ID] = true
	}
	if err := checkIDs(ans, validIDs); err != nil {
		return modelAnswer{}, err
	}
	return ans, nil
}

// decodeObject decodes the output as exactly one JSON object.
func decodeObject(raw string) (map[string]json.RawMessage, error) {
	body := stripCodeFence(raw)

	dec := json.NewDecoder(strings.NewReader(body))
	var fields map[string]json.RawMessage
	if err := dec.Decode(&fields); err != nil {
		return nil, invalidf("output is not a JSON object")
	}
	if dec.More() {
		return nil, invalidf("output has content after the JSON object")
	}
	if fields == nil { // the literal null
		return nil, invalidf("output is not a JSON object")
	}
	return fields, nil
}

// parseCore reads and type-checks the fields every answer has.
func parseCore(fields map[string]json.RawMessage) (modelAnswer, error) {
	var ans modelAnswer
	if err := requiredString(fields, "status", &ans.Status); err != nil {
		return modelAnswer{}, err
	}
	if ans.Status != StatusAnswered && ans.Status != StatusUncertain {
		return modelAnswer{}, invalidf("status is not answered or uncertain")
	}
	if err := requiredStringSlice(fields, "correctOptionIds", &ans.CorrectOptionIDs); err != nil {
		return modelAnswer{}, err
	}
	if err := requiredNullableString(fields, "explanation", &ans.Explanation); err != nil {
		return modelAnswer{}, err
	}
	if err := requiredNullableString(fields, "details", &ans.Details); err != nil {
		return modelAnswer{}, err
	}
	if err := requiredNumber(fields, "confidence", &ans.Confidence); err != nil {
		return modelAnswer{}, err
	}
	if ans.Confidence < 0 || ans.Confidence > 1 {
		return modelAnswer{}, invalidf("confidence is outside 0.0..1.0")
	}
	if err := requiredStringSlice(fields, "warnings", &ans.Warnings); err != nil {
		return modelAnswer{}, err
	}
	return ans, nil
}

// checkIDs verifies the answered ids against the known option ids.
func checkIDs(ans modelAnswer, validIDs map[string]bool) error {
	for _, id := range ans.CorrectOptionIDs {
		if !validIDs[id] {
			return invalidf("correctOptionIds contains an id that is not one of the options")
		}
	}
	if ans.Status == StatusAnswered && len(ans.CorrectOptionIDs) == 0 {
		return invalidf("status is answered but correctOptionIds is empty")
	}
	return nil
}

// recognized reads the question and options the model transcribed from the
// image and applies the request limits to them. Overlong texts are cut rather
// than rejected: the answer is already paid for and the text is only shown.
func recognized(fields map[string]json.RawMessage) (string, []Option, error) {
	var question string
	if err := requiredString(fields, "question", &question); err != nil {
		return "", nil, err
	}
	question = truncateRunes(strings.TrimSpace(question), maxQuestionChars)
	if question == "" {
		return "", nil, invalidf("question is empty")
	}

	raw, ok := fields["options"]
	if !ok {
		return "", nil, missing("options")
	}
	var list []Option
	if err := json.Unmarshal(raw, &list); err != nil || isNull(raw) {
		return "", nil, wrongType("options")
	}
	if len(list) < minOptions || len(list) > maxOptions {
		return "", nil, invalidf("options has an unsupported number of items")
	}

	seen := make(map[string]bool, len(list))
	options := make([]Option, len(list))
	for i, o := range list {
		id := strings.TrimSpace(o.ID)
		text := truncateRunes(strings.TrimSpace(o.Text), maxOptionChars)
		if n := utf8.RuneCountInString(id); n < 1 || n > maxOptionIDChars {
			return "", nil, invalidf("an option id has an unsupported length")
		}
		if seen[id] {
			return "", nil, invalidf("option ids are not unique")
		}
		seen[id] = true
		if text == "" {
			return "", nil, invalidf("an option text is empty")
		}
		options[i] = Option{ID: id, Text: text}
	}
	return question, options, nil
}

func truncateRunes(s string, limit int) string {
	if utf8.RuneCountInString(s) <= limit {
		return s
	}
	return string([]rune(s)[:limit])
}

// stripCodeFence removes one surrounding Markdown code fence (``` or ```json).
func stripCodeFence(s string) string {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "```") {
		return s
	}
	s = strings.TrimSpace(strings.TrimPrefix(s, "```"))
	// An optional language tag follows the opening fence. A JSON object starts
	// with a brace, so removing a leading "json" cannot eat answer content.
	if len(s) >= 4 && strings.EqualFold(s[:4], "json") {
		s = s[4:]
	}
	return strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(s), "```"))
}

func missing(name string) error { return invalidf("required field %q is missing", name) }

func wrongType(name string) error { return invalidf("field %q has the wrong type", name) }

func requiredString(fields map[string]json.RawMessage, name string, dst *string) error {
	raw, ok := fields[name]
	if !ok {
		return missing(name)
	}
	if err := json.Unmarshal(raw, dst); err != nil || isNull(raw) {
		return wrongType(name)
	}
	return nil
}

func requiredNullableString(fields map[string]json.RawMessage, name string, dst **string) error {
	raw, ok := fields[name]
	if !ok {
		return missing(name)
	}
	if isNull(raw) {
		*dst = nil
		return nil
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return wrongType(name)
	}
	*dst = &s
	return nil
}

func requiredNumber(fields map[string]json.RawMessage, name string, dst *float64) error {
	raw, ok := fields[name]
	if !ok {
		return missing(name)
	}
	if isNull(raw) {
		return wrongType(name)
	}
	if err := json.Unmarshal(raw, dst); err != nil {
		return wrongType(name)
	}
	return nil
}

func requiredStringSlice(fields map[string]json.RawMessage, name string, dst *[]string) error {
	raw, ok := fields[name]
	if !ok {
		return missing(name)
	}
	if isNull(raw) {
		return wrongType(name)
	}
	var out []string
	if err := json.Unmarshal(raw, &out); err != nil {
		return wrongType(name)
	}
	*dst = out
	return nil
}

func isNull(raw json.RawMessage) bool {
	return bytes.Equal(bytes.TrimSpace(raw), []byte("null"))
}
