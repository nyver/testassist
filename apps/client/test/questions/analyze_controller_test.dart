import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/features/history/domain/history_entry.dart';
import 'package:test_assistant/features/questions/domain/analyze_controller.dart';
import 'package:test_assistant/features/questions/domain/draft_controller.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/settings/data/settings_repository.dart';

import '../support/harness.dart';
import '../support/test_data.dart';

void main() {
  late Harness h;
  late ProviderContainer container;
  late String draftImage;

  Future<ProviderContainer> makeContainer({
    Map<String, Object> prefs = const {},
    Future<void> Function()? verifier,
  }) async {
    h = await Harness.create(preferences: prefs);
    await h.seedServer();
    final stored = await h.images.create();
    await stored.file.writeAsBytes([1, 2, 3]);
    draftImage = stored.relativePath;
    h.drafts.draft = QuestionDraft(
      imagePath: draftImage,
      ocrText: 'raw ocr',
      questionText: 'Which protocol encrypts web traffic?',
      options: optionsAbcd,
      sendImage: true,
    );
    final c = ProviderContainer(
      retry: (count, error) => null,
      overrides: h.overrides(verifier: verifier),
    );
    addTearDown(c.dispose);
    await c.read(serverSessionProvider.future);
    await c.read(draftControllerProvider.future);
    return c;
  }

  tearDown(() => h.dispose());

  Future<void> analyze({
    String provider = 'openrouter',
    String model = 'vision-model',
    bool vision = true,
  }) => container
      .read(analyzeControllerProvider.notifier)
      .analyzeDraft(
        provider: provider,
        model: model,
        modelSupportsVision: vision,
        language: 'ru',
      );

  group('a successful analysis', () {
    setUp(() async => container = await makeContainer());

    test('is saved to history with every field and clears the draft', () async {
      await analyze();

      final state = container.read(analyzeControllerProvider);
      expect(state, isA<AnalyzeSucceeded>());
      final entry = h.history.entries.single;
      expect((state as AnalyzeSucceeded).entryId, entry.id);
      expect(entry.questionText, 'Which protocol encrypts web traffic?');
      expect(entry.ocrText, 'raw ocr');
      expect(entry.options, optionsAbcd);
      expect(entry.result.correctOptionIds, ['B']);
      expect(entry.result.answerText, 'HTTPS');
      expect(entry.result.explanation, 'Because TLS.');
      expect(entry.result.details, 'More about TLS.');
      expect(entry.result.confidence, 0.9);
      expect(entry.result.provider, 'openrouter');
      expect(entry.result.model, 'vision-model');
      expect(entry.result.requestId, 'req-1');
      expect(entry.serverRef, isNotNull);
      expect(entry.imagePath, draftImage, reason: 'the entry owns the image');
      expect(await h.images.exists(draftImage), isTrue);
      expect(h.drafts.draft, isNull, reason: 'the draft is cleared');
      expect(container.read(draftControllerProvider).value, isNull);
    });

    test(
      'the request carries the edited text, language, model and image',
      () async {
        container
            .read(draftControllerProvider.notifier)
            .updateOption(2, const OptionItem(id: 'C', text: 'EDITED TLS'));

        await analyze();

        final request = h.questionsApi.requests.single;
        expect(request.question, 'Which protocol encrypts web traffic?');
        expect(request.options[2].text, 'EDITED TLS', reason: 'edits, not OCR');
        expect(request.language, 'ru');
        expect(request.provider, 'openrouter');
        expect(request.model, 'vision-model');
        expect(request.imagePath, h.images.resolve(draftImage)!.path);
      },
    );

    test('remembers the provider and model', () async {
      await analyze();
      final settings = container.read(settingsRepositoryProvider).load();
      expect(settings.lastProvider, 'openrouter');
      expect(settings.lastModel, 'vision-model');
    });
  });

  group('image sending', () {
    setUp(() async => container = await makeContainer());

    test('a text-only model never receives the image', () async {
      await analyze(model: 'text-model', vision: false);
      expect(h.questionsApi.requests.single.imagePath, isNull);
    });

    test('with the switch off no image is sent to a vision model', () async {
      container
          .read(draftControllerProvider.notifier)
          .setSendImage(value: false);
      await analyze();
      expect(h.questionsApi.requests.single.imagePath, isNull);
    });

    test('a missing image file is skipped, not an error', () async {
      await h.images.delete(draftImage);
      await analyze();
      expect(
        container.read(analyzeControllerProvider),
        isA<AnalyzeSucceeded>(),
      );
      expect(h.questionsApi.requests.single.imagePath, isNull);
    });
  });

  group('the delete-images setting', () {
    test('removes the file and keeps the text', () async {
      container = await makeContainer(
        prefs: {SettingsRepository.deleteImagesKey: true},
      );

      await analyze();

      final entry = h.history.entries.single;
      expect(entry.imagePath, isNull);
      expect(entry.questionText, isNotEmpty);
      expect(entry.result.answerText, 'HTTPS');
      expect(await h.images.exists(draftImage), isFalse);
      expect(h.drafts.draft, isNull);
    });
  });

  group('failures', () {
    setUp(() async => container = await makeContainer());

    for (final failure in <AppFailure>[
      const NetworkFailure('down'),
      const CertificateChangedFailure(),
      const ApiFailure(code: 'LLM_TIMEOUT', message: 'slow', requestId: 'r'),
      const ApiFailure(code: 'UNAUTHORIZED', message: 'no'),
      const ApiFailure(code: 'RATE_LIMITED', message: 'wait'),
      const ApiFailure(
        code: 'INTERNAL_ERROR',
        message: 'boom',
        requestId: 'abc',
      ),
    ]) {
      test(
        '${failure.runtimeType} keeps the draft and saves nothing',
        () async {
          h.questionsApi.onAnalyze = (_, _) => throw failure;

          await analyze();

          final state = container.read(analyzeControllerProvider);
          expect(state, isA<AnalyzeFailed>());
          expect((state as AnalyzeFailed).failure, same(failure));
          expect(h.history.entries, isEmpty);
          expect(h.drafts.draft, isNotNull);
          expect(h.drafts.draft!.questionText, isNotEmpty);
          expect(await h.images.exists(draftImage), isTrue);
        },
      );
    }

    test('an unexpected error is wrapped, never exposed raw', () async {
      h.questionsApi.onAnalyze = (_, _) => throw StateError('secret detail');
      await analyze();
      final state = container.read(analyzeControllerProvider);
      expect((state as AnalyzeFailed).failure, isA<UnexpectedFailure>());
      expect(h.history.entries, isEmpty);
    });

    test('the draft stays editable after a failure', () async {
      h.questionsApi.onAnalyze = (_, _) => throw const NetworkFailure();
      await analyze();

      container.read(draftControllerProvider.notifier).updateQuestion('Fixed?');
      h.questionsApi.onAnalyze = (request, _) => AnalysisResult(
        status: AnswerStatus.answered,
        correctOptionIds: const ['A'],
        answerText: 'HTTP',
        explanation: null,
        details: null,
        confidence: 0.7,
        confidenceLevel: ConfidenceLevel.medium,
        warnings: const [],
        provider: request.provider,
        model: request.model,
      );
      container.read(analyzeControllerProvider.notifier).reset();
      await analyze();

      expect(h.history.entries.single.questionText, 'Fixed?');
    });
  });

  group('server identity', () {
    test('a different server blocks the request', () async {
      container = await makeContainer(
        verifier: () async => throw const ServerMismatchFailure(),
      );

      await analyze();

      final state = container.read(analyzeControllerProvider);
      expect((state as AnalyzeFailed).failure, isA<ServerMismatchFailure>());
      expect(h.questionsApi.requests, isEmpty, reason: 'nothing was sent');
      expect(h.history.entries, isEmpty);
      expect(h.drafts.draft, isNotNull);
    });
  });

  group('cancel', () {
    test('aborts the HTTP request and keeps the draft editable', () async {
      container = await makeContainer();
      final started = Completer<CancelToken?>();
      h.questionsApi.onAnalyze = (request, token) async {
        started.complete(token);
        final cancelled = Completer<void>();
        unawaited(token!.whenCancel.then((_) => cancelled.complete()));
        await cancelled.future;
        throw const CancelledFailure();
      };

      final running = analyze();
      final token = await started.future;
      expect(container.read(analyzeControllerProvider), isA<AnalyzeRunning>());
      expect(token!.isCancelled, isFalse);

      container.read(analyzeControllerProvider.notifier).cancel();
      await running;

      expect(token.isCancelled, isTrue);
      final state = container.read(analyzeControllerProvider);
      expect((state as AnalyzeFailed).failure, isA<CancelledFailure>());
      expect(h.history.entries, isEmpty);
      expect(h.drafts.draft, isNotNull);
    });

    test('a second request while one is running is ignored', () async {
      container = await makeContainer();
      final release = Completer<void>();
      h.questionsApi.onAnalyze = (request, token) async {
        await release.future;
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

      final first = analyze();
      await pumpEventQueue();
      await analyze(); // ignored
      release.complete();
      await first;

      expect(h.questionsApi.requests, hasLength(1));
      expect(h.history.entries, hasLength(1));
    });
  });

  group('retry and change model from a saved entry', () {
    late HistoryEntry entry;

    setUp(() async {
      container = await makeContainer();
      await analyze();
      entry = h.history.entries.single;
    });

    test('creates a new entry and keeps the old one', () async {
      await container
          .read(analyzeControllerProvider.notifier)
          .analyzeEntry(
            entry,
            provider: 'routerai',
            model: 'router-model',
            modelSupportsVision: false,
            language: 'en',
          );

      expect(h.history.entries, hasLength(2));
      final newest = h.history.entries.last;
      expect(newest.id, isNot(entry.id));
      expect(newest.result.model, 'router-model');
      expect(newest.questionText, entry.questionText);
      expect(newest.options, entry.options);
      expect(h.questionsApi.requests.last.imagePath, isNull);
    });

    test('each entry owns its own image file', () async {
      await container
          .read(analyzeControllerProvider.notifier)
          .analyzeEntry(
            entry,
            provider: 'openrouter',
            model: 'vision-model',
            modelSupportsVision: true,
            language: 'en',
          );

      final copy = h.history.entries.last;
      expect(copy.imagePath, isNotNull);
      expect(copy.imagePath, isNot(entry.imagePath));
      expect(h.questionsApi.requests.last.imagePath, isNotNull);

      // Deleting the first entry's file must not affect the second.
      await h.images.delete(entry.imagePath);
      expect(await h.images.exists(copy.imagePath), isTrue);
    });

    test('the draft is not touched by a retry', () async {
      h.drafts.draft = const QuestionDraft(
        imagePath: null,
        ocrText: 'other',
        questionText: 'Another question?',
        options: optionsAbcd,
        sendImage: false,
      );
      await container.read(draftControllerProvider.notifier).flush();

      await container
          .read(analyzeControllerProvider.notifier)
          .analyzeEntry(
            entry,
            provider: 'openrouter',
            model: 'vision-model',
            modelSupportsVision: true,
            language: 'en',
          );

      expect(h.drafts.draft?.questionText, 'Another question?');
    });

    test('a failed retry adds no entry', () async {
      h.questionsApi.onAnalyze = (_, _) => throw const NetworkFailure();
      await container
          .read(analyzeControllerProvider.notifier)
          .analyzeEntry(
            entry,
            provider: 'openrouter',
            model: 'vision-model',
            modelSupportsVision: true,
            language: 'en',
          );
      expect(h.history.entries, hasLength(1));
    });
  });

  test('temporary files never leak into the image directory', () async {
    container = await makeContainer();
    await analyze();
    final files = h.images.imagesDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
  });
}
