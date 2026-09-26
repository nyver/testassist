package analysis

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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
	body := stripCodeFence(raw)

	dec := json.NewDecoder(strings.NewReader(body))
	var fields map[string]json.RawMessage
	if err := dec.Decode(&fields); err != nil {
		return modelAnswer{}, invalidf("output is not a JSON object")
	}
	if dec.More() {
		return modelAnswer{}, invalidf("output has content after the JSON object")
	}
	if fields == nil { // the literal null
		return modelAnswer{}, invalidf("output is not a JSON object")
	}

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

	for _, id := range ans.CorrectOptionIDs {
		if !validIDs[id] {
			return modelAnswer{}, invalidf("correctOptionIds contains an id that is not one of the options")
		}
	}
	if ans.Status == StatusAnswered && len(ans.CorrectOptionIDs) == 0 {
		return modelAnswer{}, invalidf("status is answered but correctOptionIds is empty")
	}
	return ans, nil
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
