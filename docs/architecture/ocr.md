# On-device OCR

The client recognizes text on the device with ML Kit (`google_mlkit_text_recognition`, the bundled **Latin** recognizer). The image never leaves the phone for OCR. Recognition runs on a grayscale, contrast-normalized copy of the cropped photo; the raw text is kept unchanged for editing and history, and `QuestionParser` turns it into a question and options.

## Spike results (task 9.5)

**Method.** `apps/client/tool/ocr_spike.dart` runs the recognizer on sample images, once on the original file and once on the app's OCR copy, and prints the raw text and the parser's result. Run on an Android 16 (API 36) x86-64 emulator with three clean, synthetic samples rendered in Arial 40 (black on white, no perspective, no noise): one English question, one Russian question with Latin terms, and one purely Russian question.

| Sample | Raw image | Preprocessed copy |
|---|---|---|
| English: `Which protocol encrypts HTTP?` + `A. FTP` … `D. Telnet` | exact | exact |
| Russian with Latin terms: `Какой протокол шифрует HTTP?` + `а) FTP` … | `Kakoṁ npoTOKOI unopyeT HTTP?`, Latin words exact, markers read as `a) 6) B) r)` | same, one character worse |
| Russian only: `Столица России?` + `а) Москва` … | `CTOIMLa Poccuu?`, `MocKBa`, `CaHKT-[leTepoypr`, markers `a) 6) B) r)` | similar garbage |

**Findings.**

1. **English is reliable.** Question and options were read exactly and parsed into the expected options (`A=FTP; B=HTTPS; C=SMTP; D=Telnet`).
2. **Cyrillic is not usable.** The Latin recognizer maps Cyrillic glyphs to the nearest Latin, digit or symbol shapes (`Москва` → `MocKBa`, `б)` → `6)`, `г)` → `r)`). The text is not readable and cannot be repaired by post-processing. This is a limit of the recognizer, not of the photo quality or of our preprocessing: the preprocessed copy did not help.
3. **Latin terms inside Russian text survive** (`HTTP`, `HTTPS`, `SMTP`, `Telnet`, `FTP`), so technical questions are partly usable.
4. **Marker misreads confuse the parser.** Cyrillic markers come back as `6)` or `r)`. The parser then sees a number or a stray letter instead of `Б)`/`Г)`, so options merge or drop (`A=FTP 6) HTTPS; B=SMTP`). The low-quality warning does not fire in those cases because two or more options are still found.
5. Preprocessing (orientation, crop, downscale, grayscale/contrast) made no measurable difference on clean images. It is kept because photos of paper are not clean; its value has to be judged on real photos.

**Not verified.** Real camera photos (perspective, shadows, glare, handwriting) and other devices. The synthetic samples give the best case, so real-world results can only be worse.

## Decision

- Keep ML Kit Latin for the MVP: it is free, offline and accurate for English, and its cost is small.
- Treat Russian text as **"needs correction or vision"**. The recognition screen always shows the raw text and lets the user edit the question and options ("Parse again" re-parses edited raw text).
- For Russian questions the recommended path is **"Send image to model"** with a vision model: the model reads the image itself and the OCR text is only a hint. The image switch is off by default and is gated by the model's `vision` capability.
- A better Cyrillic engine (for example a server-side OCR or another on-device engine) is a follow-up change, not part of this MVP. The `OcrService` interface is the seam.

## Follow-ups

- Repeat the spike with real photos of Russian tests on a physical device.
- Consider normalizing digit/letter lookalikes in option markers when the surrounding text is Cyrillic.
- Consider telling the user, when the app language is Russian and OCR output contains few Cyrillic letters, that sending the image to a vision model gives better results.
