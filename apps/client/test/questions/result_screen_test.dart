import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/features/history/domain/history_entry.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/questions/ui/result_screen.dart';
import 'package:test_assistant/features/settings/data/settings_repository.dart';

import '../support/harness.dart';
import '../support/test_data.dart';

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Harness h;

  Future<Harness> harness({String? mode}) async {
    h = await Harness.create(
      preferences: {SettingsRepository.displayModeKey: ?mode},
    );
    await h.seedServer();
    return h;
  }

  tearDown(() => h.dispose());

  Future<void> openResult(
    WidgetTester tester,
    NewHistoryEntry entry, {
    List<Override> extra = const [],
  }) async {
    await h.history.insert(entry);
    await pumpApp(tester, h, extra: extra);
    await tester.tap(find.byKey(const Key('main-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('history-entry-${h.history.entries.last.id}')),
    );
    await tester.pumpAndSettle();
  }

  NewHistoryEntry entry({
    AnalysisResult? result,
    String? imagePath,
    List<OptionItem> options = optionsAbcd,
  }) => NewHistoryEntry(
    imagePath: imagePath,
    ocrText: 'raw',
    questionText: 'Which protocol encrypts web traffic?',
    options: options,
    result: result ?? answeredResult(details: 'Long details here.'),
    serverRef: 1,
  );

  group('display modes', () {
    testWidgets('default: option, confidence and short explanation', (
      tester,
    ) async {
      await harness();
      await openResult(tester, entry());

      expect(find.text('B. HTTPS'), findsOneWidget);
      expect(find.text('Confidence: High'), findsOneWidget);
      expect(find.byKey(const Key('explanation')), findsOneWidget);
      expect(find.byKey(const Key('details')), findsNothing);
      expect(find.byKey(const Key('action-more')), findsOneWidget);
    });

    testWidgets('"More" reveals the details in the default mode', (
      tester,
    ) async {
      await harness();
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-more')));
      await tester.pumpAndSettle();

      expect(find.text('Long details here.'), findsOneWidget);
      expect(find.byKey(const Key('action-more')), findsNothing);
    });

    testWidgets('correct option only hides the explanation until "More"', (
      tester,
    ) async {
      await harness(mode: 'optionOnly');
      await openResult(tester, entry());

      expect(find.text('B. HTTPS'), findsOneWidget);
      expect(find.text('Confidence: High'), findsOneWidget);
      expect(find.byKey(const Key('explanation')), findsNothing);
      expect(find.byKey(const Key('details')), findsNothing);

      await tester.tap(find.byKey(const Key('action-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explanation')), findsOneWidget);
      expect(find.byKey(const Key('details')), findsOneWidget);
    });

    testWidgets('detailed mode shows explanation and details', (tester) async {
      await harness(mode: 'detailed');
      await openResult(tester, entry());

      expect(find.byKey(const Key('explanation')), findsOneWidget);
      expect(find.text('Long details here.'), findsOneWidget);
      expect(find.byKey(const Key('action-more')), findsNothing);
    });

    testWidgets('no "More" when there is nothing more to show', (tester) async {
      await harness();
      await openResult(tester, entry(result: answeredResult(details: null)));
      expect(find.byKey(const Key('action-more')), findsNothing);
    });
  });

  testWidgets('several correct options are all listed with their texts', (
    tester,
  ) async {
    await harness();
    await openResult(
      tester,
      entry(
        result: answeredResult(ids: const ['A', 'C'], answerText: 'HTTP; TLS'),
      ),
    );
    expect(find.text('A. HTTP'), findsOneWidget);
    expect(find.text('C. TLS'), findsOneWidget);
  });

  testWidgets('an uncertain result says so and lists the warnings', (
    tester,
  ) async {
    await harness();
    await openResult(tester, entry(result: uncertainResult()));

    expect(find.byKey(const Key('uncertain-text')), findsOneWidget);
    expect(find.text('No reliable answer was found.'), findsOneWidget);
    expect(find.text('Option C is not readable'), findsOneWidget);
    expect(find.text('Confidence: Low'), findsOneWidget);
    expect(find.byKey(const Key('correct-B')), findsNothing);
  });

  testWidgets('warnings of an answered result are shown too', (tester) async {
    await harness();
    await openResult(
      tester,
      entry(result: answeredResult(warnings: const ['Question was cropped'])),
    );
    expect(find.text('Question was cropped'), findsOneWidget);
  });

  testWidgets('an entry whose image is gone shows without an error', (
    tester,
  ) async {
    await harness();
    await openResult(tester, entry(imagePath: 'images/deleted.jpg'));

    expect(find.byKey(const Key('answer-card')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Something went wrong'), findsNothing);
  });

  group('copy and share', () {
    testWidgets('copy puts question, option and explanation on the clipboard', (
      tester,
    ) async {
      await harness();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-copy')));
      await tester.pumpAndSettle();

      expect(
        copied,
        contains('Question: Which protocol encrypts web traffic?'),
      );
      expect(copied, contains('Answer: B. HTTPS'));
      expect(copied, contains('Explanation: HTTPS wraps HTTP in TLS.'));
      expect(find.text('Copied to clipboard.'), findsOneWidget);
    });

    testWidgets('share sends the same plain text', (tester) async {
      await harness();
      final shared = <String>[];
      await openResult(
        tester,
        entry(),
        extra: [
          shareTextProvider.overrideWithValue((text) async => shared.add(text)),
        ],
      );

      await tester.tap(find.byKey(const Key('action-share')));
      await tester.pump();

      expect(shared, hasLength(1));
      expect(shared.single, contains('Answer: B. HTTPS'));
      expect(shared.single, contains('Explanation:'));
    });
  });

  group('retry and change model', () {
    testWidgets('retry resends the same question with the same model', (
      tester,
    ) async {
      await harness();
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-retry')));
      await _frames(tester);
      await tester.pumpAndSettle();

      final request = h.questionsApi.requests.single;
      expect(request.question, 'Which protocol encrypts web traffic?');
      expect(request.provider, 'openrouter');
      expect(request.model, 'openai/gpt-4o-mini');
      expect(request.options, optionsAbcd);
      expect(h.history.entries, hasLength(2), reason: 'each retry is an entry');
      expect(find.byKey(const Key('answer-card')), findsOneWidget);
    });

    testWidgets('change model sends the question to the chosen model', (
      tester,
    ) async {
      await harness();
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-change-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-text-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-confirm')));
      await _frames(tester);
      await tester.pumpAndSettle();

      final request = h.questionsApi.requests.single;
      expect(request.model, 'text-model');
      expect(request.provider, 'openrouter');
      expect(h.history.entries.last.result.model, 'text-model');
      expect(h.history.entries, hasLength(2));
    });

    testWidgets('a failed retry keeps the current result and reports it', (
      tester,
    ) async {
      await harness();
      h.questionsApi.onAnalyze = (_, _) =>
          throw const ApiFailure(code: 'LLM_TIMEOUT', message: 'slow');
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-retry')));
      await _frames(tester);

      expect(
        find.text('The model did not respond in time. Try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('answer-card')), findsOneWidget);
      expect(h.history.entries, hasLength(1));
    });
  });

  group('delete', () {
    testWidgets('asks for confirmation, then removes the entry and closes', (
      tester,
    ) async {
      await harness();
      await openResult(tester, entry());

      await tester.tap(find.byKey(const Key('action-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry from history?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.history.entries, hasLength(1));

      await tester.tap(find.byKey(const Key('action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(h.history.entries, isEmpty);
      expect(find.byKey(const Key('answer-card')), findsNothing);
      expect(find.byKey(const Key('main-take-photo')), findsOneWidget);
    });
  });
}
