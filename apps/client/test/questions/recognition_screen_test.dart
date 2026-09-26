import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/features/questions/domain/models.dart';

import '../support/harness.dart';
import '../support/test_data.dart';

QuestionDraft _draft({
  String question = 'Which protocol encrypts web traffic?',
  List<OptionItem> options = optionsAbcd,
  String ocr = 'raw text',
  String? image,
  bool sendImage = false,
}) => QuestionDraft(
  imagePath: image,
  ocrText: ocr,
  questionText: question,
  options: options,
  sendImage: sendImage,
);

/// Lets real file I/O finish; testWidgets runs in fake async otherwise.
Future<void> _realIo(WidgetTester tester) => tester.runAsync(
  () => Future<void>.delayed(const Duration(milliseconds: 200)),
);

/// Pumps frames without waiting for endless animations.
Future<void> _pumpFrames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Harness h;
  setUp(() async {
    h = await Harness.create();
    await h.seedServer();
  });
  tearDown(() => h.dispose());

  Finder button() => find.byKey(const Key('get-answer'));
  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(button()).onPressed != null;

  testWidgets('an unfinished draft is restored on start', (tester) async {
    h.drafts.draft = _draft(question: 'Restored question?', image: null);
    await pumpApp(tester, h);

    expect(find.byKey(const Key('question-field')), findsOneWidget);
    expect(find.text('Restored question?'), findsOneWidget);
    expect(find.text('HTTPS'), findsOneWidget);
    expect(find.byKey(const Key('option-id-3')), findsOneWidget);
  });

  testWidgets('a complete draft can be sent', (tester) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h);
    expect(enabled(tester), isTrue);
    expect(find.byKey(const Key('low-quality-warning')), findsNothing);
  });

  testWidgets('duplicate ids disable the button and are highlighted', (
    tester,
  ) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h);

    await tester.enterText(find.byKey(const Key('option-id-1')), 'A');
    await tester.pump();

    expect(enabled(tester), isFalse);
    expect(find.text('Duplicate option ID'), findsNWidgets(2));

    await tester.enterText(find.byKey(const Key('option-id-1')), 'B');
    await tester.pump();
    expect(enabled(tester), isTrue);
    expect(find.text('Duplicate option ID'), findsNothing);
  });

  testWidgets('an empty id, empty question or too few options disable it', (
    tester,
  ) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h);

    await tester.enterText(find.byKey(const Key('option-id-0')), '');
    await tester.pump();
    expect(enabled(tester), isFalse);
    expect(find.text('Enter an ID'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('option-id-0')), 'A');

    await tester.enterText(find.byKey(const Key('question-field')), '   ');
    await tester.pump();
    expect(enabled(tester), isFalse);
    expect(find.byKey(const Key('low-quality-warning')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('question-field')), 'Q?');
    await tester.pump();
    expect(enabled(tester), isTrue);
  });

  testWidgets('one option only shows the warning and allows adding more', (
    tester,
  ) async {
    h.drafts.draft = _draft(
      options: const [OptionItem(id: 'A', text: 'one')],
    );
    await pumpApp(tester, h);

    expect(
      find.text(
        'Could not reliably recognize the question. Try taking the photo again.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester), isFalse);

    await tester.tap(find.byKey(const Key('add-option')));
    await tester.pump();
    expect(find.byKey(const Key('option-id-1')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('option-text-1')), 'two');
    await tester.pump();

    expect(find.byKey(const Key('low-quality-warning')), findsNothing);
    expect(enabled(tester), isTrue);
  });

  testWidgets('no recognized text shows the warning but stays editable', (
    tester,
  ) async {
    h.drafts.draft = _draft(question: '', options: const [], ocr: '');
    await pumpApp(tester, h);

    expect(find.byKey(const Key('low-quality-warning')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('question-field')), 'Typed');
    await tester.pump();
    expect(find.text('Typed'), findsOneWidget);
  });

  testWidgets('re-parsing replaces the fields from the edited raw text', (
    tester,
  ) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h);

    await tester.tap(find.byKey(const Key('raw-text-tile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('raw-text')),
      'New question?\nA. red\nB. blue',
    );
    await tester.tap(find.byKey(const Key('reparse')));
    await tester.pump();

    expect(find.text('New question?'), findsOneWidget);
    expect(find.byKey(const Key('option-id-2')), findsNothing);
    expect(find.text('blue'), findsOneWidget);
  });

  testWidgets('options can be moved and removed', (tester) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h);

    await tester.tap(find.byKey(const Key('option-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('option-id-0')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'B',
    );

    await tester.tap(find.byKey(const Key('option-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove option'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('option-id-3')), findsNothing);
  });

  group('image switch', () {
    Future<void> openModelSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('is off by default and enabled for a vision model', (
      tester,
    ) async {
      h.drafts.draft = _draft(image: 'images/x.jpg');
      await pumpApp(tester, h);

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('send-image-switch')),
      );
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNotNull, reason: 'the default model has vision');
    });

    testWidgets('selecting a text-only model turns it off and explains why', (
      tester,
    ) async {
      h.drafts.draft = _draft(image: 'images/x.jpg', sendImage: true);
      await pumpApp(tester, h);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('send-image-switch')))
            .value,
        isTrue,
      );

      await openModelSheet(tester);
      await tester.tap(find.byKey(const Key('model-text-model')));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('send-image-switch')),
      );
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNull, reason: 'disabled for a text-only model');
      expect(
        find.text(
          'The selected model does not support images. Only the recognized text will be sent.',
        ),
        findsWidgets,
      );
      expect(h.drafts.draft!.sendImage, isFalse);
    });

    testWidgets('the model list shows which models accept images', (
      tester,
    ) async {
      h.drafts.draft = _draft();
      await pumpApp(tester, h);
      await openModelSheet(tester);

      expect(find.byKey(const Key('badge-vision')), findsWidgets);
      expect(find.byKey(const Key('badge-text')), findsWidgets);
      expect(find.text('Vision model'), findsWidgets);
      expect(find.text('Text model'), findsOneWidget);
    });

    testWidgets('a vision model with the switch on sends the image', (
      tester,
    ) async {
      h.drafts.draft = _draft(image: 'images/x.jpg', sendImage: true);
      await pumpApp(tester, h);
      // The file does not exist on disk, so the upload path stays empty, but
      // the request is still made with the vision model.
      await tester.tap(button());
      await _pumpFrames(tester);
      await _realIo(tester);
      await _pumpFrames(tester);
      await tester.pumpAndSettle();

      expect(h.questionsApi.requests.single.model, 'vision-model');
    });
  });

  group('getting the answer', () {
    testWidgets('opens the result and saves it to history', (tester) async {
      h.drafts.draft = _draft();
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('answer-card')), findsOneWidget);
      expect(find.byKey(const Key('correct-B')), findsOneWidget);
      expect(h.history.entries, hasLength(1));
      expect(h.drafts.draft, isNull);
    });

    testWidgets('shows progress and lets the user cancel, keeping the draft', (
      tester,
    ) async {
      h.drafts.draft = _draft();
      final started = Completer<void>();
      h.questionsApi.onAnalyze = (request, token) async {
        started.complete();
        final cancelled = Completer<void>();
        unawaited(token!.whenCancel.then((_) => cancelled.complete()));
        await cancelled.future;
        throw const CancelledFailure();
      };
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);
      await started.future;
      expect(find.byKey(const Key('analyze-progress')), findsOneWidget);

      await tester.tap(find.byKey(const Key('analyze-cancel')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('analyze-progress')), findsNothing);
      expect(find.text('Request cancelled.'), findsOneWidget);
      expect(find.byKey(const Key('question-field')), findsOneWidget);
      expect(h.drafts.draft, isNotNull);
      expect(h.history.entries, isEmpty);
    });

    testWidgets('a timeout shows the message with a retry action', (
      tester,
    ) async {
      h.drafts.draft = _draft();
      h.questionsApi.onAnalyze = (_, _) =>
          throw const ApiFailure(code: 'LLM_TIMEOUT', message: 'slow');
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);

      expect(
        find.text('The model did not respond in time. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(h.drafts.draft, isNotNull);

      // Retry sends the same draft again and succeeds.
      h.questionsApi.onAnalyze = (request, _) => AnalysisResult(
        status: AnswerStatus.answered,
        correctOptionIds: const ['B'],
        answerText: 'HTTPS',
        explanation: 'ok',
        details: null,
        confidence: 0.9,
        confidenceLevel: ConfidenceLevel.high,
        warnings: const [],
        provider: request.provider,
        model: request.model,
      );
      await tester.tap(find.text('Retry'));
      await _pumpFrames(tester);
      await tester.pumpAndSettle();
      expect(h.questionsApi.requests, hasLength(2));
      expect(find.byKey(const Key('answer-card')), findsOneWidget);
    });

    testWidgets('a network failure shows the network message', (tester) async {
      h.drafts.draft = _draft();
      h.questionsApi.onAnalyze = (_, _) => throw const NetworkFailure('down');
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);

      expect(
        find.text(
          'Could not connect to the server. Check the network and server address.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('an unknown server error shows the request id, no raw text', (
      tester,
    ) async {
      h.drafts.draft = _draft();
      h.questionsApi.onAnalyze = (_, _) => throw const ApiFailure(
        code: 'INTERNAL_ERROR',
        message: 'stack trace here',
        requestId: 'abc',
      );
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);

      expect(find.textContaining('abc'), findsOneWidget);
      expect(find.textContaining('stack trace'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a vision refusal offers to resend the text only', (
      tester,
    ) async {
      h.drafts.draft = _draft(image: 'images/x.jpg', sendImage: true);
      var first = true;
      h.questionsApi.onAnalyze = (request, _) {
        if (first) {
          first = false;
          throw const ApiFailure(
            code: 'MODEL_DOES_NOT_SUPPORT_VISION',
            message: 'no',
          );
        }
        return AnalysisResult(
          status: AnswerStatus.answered,
          correctOptionIds: const ['B'],
          answerText: 'HTTPS',
          explanation: null,
          details: null,
          confidence: 0.9,
          confidenceLevel: ConfidenceLevel.high,
          warnings: const [],
          provider: request.provider,
          model: request.model,
        );
      };
      await pumpApp(tester, h);

      await tester.tap(button());
      await _pumpFrames(tester);
      await _realIo(tester);
      await _pumpFrames(tester);
      expect(find.text('Send text only'), findsOneWidget);

      await tester.tap(find.text('Send text only'));
      await _pumpFrames(tester);
      await _realIo(tester);
      await _pumpFrames(tester);
      await tester.pumpAndSettle();

      expect(h.questionsApi.requests, hasLength(2));
      expect(h.questionsApi.requests.last.imagePath, isNull);
      expect(find.byKey(const Key('answer-card')), findsOneWidget);
    });
  });

  testWidgets('the model list failing to load offers a retry', (tester) async {
    h.drafts.draft = _draft();
    await pumpApp(tester, h, withServer: false);
    // Without a questions API override the real client fails to connect.
    expect(find.byKey(const Key('model-error')), findsOneWidget);
    expect(enabled(tester), isFalse);
  });
}
