package analysis

import (
	"strings"
	"testing"

	"github.com/nyver/test-assistant/server/internal/apierr"
)

const imageOnlyAnswered = `{"status":"answered","question":"Что такое ООП?","options":[{"id":"A","text":"Объектно-ориентированное программирование"},{"id":"B","text":"Очень одинокий программист"}],"correctOptionIds":["A"],"explanation":"why","details":null,"confidence":0.9,"warnings":[]}`

func imageOnlyRequest() Request {
	return Request{
		ImageOnly: true,
		Language:  "ru",
		Model:     "vision-model",
		Image:     &Image{MIME: "image/png", Data: []byte{0x89, 'P', 'N', 'G'}},
	}
}

func TestImageOnlyAnswer(t *testing.T) {
	t.Parallel()

	fp := &fakeProvider{reply: imageOnlyAnswered}
	res, err := newService(t, fp).Analyze(t.Context(), imageOnlyRequest())
	if err != nil {
		t.Fatal(err)
	}

	if res.Status != StatusAnswered || len(res.CorrectOptionIDs) != 1 || res.CorrectOptionIDs[0] != "A" {
		t.Errorf("result = %+v", res)
	}
	if res.AnswerText == nil || *res.AnswerText != "Объектно-ориентированное программирование" {
		t.Errorf("answer text must come from the recognized options, got %v", res.AnswerText)
	}
	if res.RecognizedQuestion != "Что такое ООП?" || len(res.RecognizedOptions) != 2 {
		t.Errorf("recognized = %q %+v", res.RecognizedQuestion, res.RecognizedOptions)
	}

	call := fp.calls[0]
	if call.System != imageOnlySystemPrompt || string(call.ResponseSchema) != string(imageOnlyAnswerSchema) {
		t.Error("the image-only prompt and schema must be used")
	}
	if call.Image == nil || strings.Contains(call.User, "<question>") || !strings.Contains(call.User, "Explanation language: ru") {
		t.Errorf("unexpected user message or image: %q, %+v", call.User, call.Image)
	}
}

func TestImageOnlyRequestValidation(t *testing.T) {
	t.Parallel()

	t.Run("without an image", func(t *testing.T) {
		t.Parallel()
		fp := &fakeProvider{}
		req := imageOnlyRequest()
		req.Image = nil
		_, err := newService(t, fp).Analyze(t.Context(), req)
		wantCode(t, err, apierr.InvalidRequest)
		if len(fp.calls) != 0 {
			t.Error("the provider must not be called")
		}
	})

	t.Run("with a text-only model", func(t *testing.T) {
		t.Parallel()
		fp := &fakeProvider{}
		req := imageOnlyRequest()
		req.Model = "text-model"
		_, err := newService(t, fp).Analyze(t.Context(), req)
		wantCode(t, err, apierr.ModelDoesNotSupportVision)
		if len(fp.calls) != 0 {
			t.Error("the provider must not be called")
		}
	})
}

func TestImageOnlyAnswerValidation(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		reply string
		code  apierr.Code // empty: the answer is accepted
	}{
		{
			"answered without the question",
			`{"status":"answered","correctOptionIds":["A"],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`,
			apierr.LLMInvalidResponse,
		},
		{
			"answered with an id that was not recognized",
			strings.Replace(imageOnlyAnswered, `["A"]`, `["C"]`, 1),
			apierr.LLMInvalidResponse,
		},
		{
			"answered with one option",
			`{"status":"answered","question":"Q?","options":[{"id":"A","text":"x"}],"correctOptionIds":["A"],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`,
			apierr.LLMInvalidResponse,
		},
		{
			"duplicate recognized ids",
			`{"status":"answered","question":"Q?","options":[{"id":"A","text":"x"},{"id":"A","text":"y"}],"correctOptionIds":["A"],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`,
			apierr.LLMInvalidResponse,
		},
		{
			"uncertain without the question and options",
			`{"status":"uncertain","question":"","options":[],"correctOptionIds":[],"explanation":null,"details":null,"confidence":0.1,"warnings":["The image is blurred."]}`,
			"",
		},
		{
			"uncertain that leaves the fields out",
			`{"status":"uncertain","correctOptionIds":[],"explanation":null,"details":null,"confidence":0.1,"warnings":[]}`,
			"",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			fp := &fakeProvider{reply: tt.reply}
			res, err := newService(t, fp).Analyze(t.Context(), imageOnlyRequest())
			if tt.code != "" {
				wantCode(t, err, tt.code)
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if res.Status != StatusUncertain || res.RecognizedQuestion != "" || res.RecognizedOptions != nil || len(res.Warnings) == 0 {
				t.Errorf("result = %+v", res)
			}
		})
	}
}

func TestImageOnlyRecognizedTextIsCapped(t *testing.T) {
	t.Parallel()

	long := strings.Repeat("я", maxQuestionChars+50)
	reply := `{"status":"answered","question":"` + long + `","options":[{"id":"A","text":"` + strings.Repeat("ы", maxOptionChars+5) + `"},{"id":"B","text":"y"}],"correctOptionIds":["B"],"explanation":null,"details":null,"confidence":0.9,"warnings":[]}`
	res, err := newService(t, &fakeProvider{reply: reply}).Analyze(t.Context(), imageOnlyRequest())
	if err != nil {
		t.Fatal(err)
	}
	if n := len([]rune(res.RecognizedQuestion)); n != maxQuestionChars {
		t.Errorf("question has %d characters", n)
	}
	if n := len([]rune(res.RecognizedOptions[0].Text)); n != maxOptionChars {
		t.Errorf("option has %d characters", n)
	}
}
