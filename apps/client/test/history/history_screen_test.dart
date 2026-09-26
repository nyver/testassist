import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/features/history/domain/history_entry.dart';
import 'package:test_assistant/features/questions/domain/models.dart';

import '../support/harness.dart';
import '../support/test_data.dart';

NewHistoryEntry _entry(
  String question, {
  AnalysisResult? result,
  String? imagePath,
}) => NewHistoryEntry(
  imagePath: imagePath,
  ocrText: '',
  questionText: question,
  options: optionsAbcd,
  result: result ?? answeredResult(),
  serverRef: 1,
);

void main() {
  late Harness h;
  setUp(() async {
    h = await Harness.create();
    await h.seedServer();
  });
  tearDown(() => h.dispose());

  Future<void> openHistory(WidgetTester tester) async {
    await pumpApp(tester, h);
    await tester.tap(find.byKey(const Key('main-history')));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty history says so', (tester) async {
    await openHistory(tester);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
    expect(find.byKey(const Key('history-clear')), findsNothing);
  });

  testWidgets('entries are listed newest first with answer, level and date', (
    tester,
  ) async {
    await h.history.insert(_entry('First question'));
    await h.history.insert(
      _entry('Second question', result: uncertainResult()),
    );
    await h.history.insert(
      _entry(
        'Third question',
        result: answeredResult(
          ids: const ['A', 'C'],
          level: ConfidenceLevel.medium,
        ),
      ),
    );
    await openHistory(tester);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['Third question', 'Second question', 'First question']);

    expect(find.textContaining('A. HTTP; C. TLS'), findsOneWidget);
    expect(find.textContaining('Medium'), findsOneWidget);
    expect(find.text('No reliable answer'), findsOneWidget);
    expect(find.textContaining('Low'), findsOneWidget);
    expect(find.textContaining('High'), findsOneWidget);
    // The date is formatted for the locale and shows the year.
    expect(find.textContaining('2026'), findsWidgets);
  });

  testWidgets('a long question is shortened to an excerpt', (tester) async {
    await h.history.insert(_entry('word ' * 200));
    await openHistory(tester);
    final title = tester.widget<Text>(
      find
          .descendant(of: find.byType(ListTile), matching: find.byType(Text))
          .first,
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('opening an entry shows its result', (tester) async {
    final saved = await h.history.insert(_entry('Open me'));
    await openHistory(tester);

    await tester.tap(find.byKey(Key('history-entry-${saved.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Open me'), findsOneWidget);
    expect(find.byKey(const Key('answer-card')), findsOneWidget);
  });

  testWidgets('an entry without an image opens without an error', (
    tester,
  ) async {
    final saved = await h.history.insert(
      _entry('No image', imagePath: 'images/missing.jpg'),
    );
    await openHistory(tester);
    await tester.tap(find.byKey(Key('history-entry-${saved.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('answer-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting an entry needs a confirmation', (tester) async {
    final a = await h.history.insert(_entry('Keep me'));
    final b = await h.history.insert(_entry('Delete me'));
    await openHistory(tester);

    await tester.tap(find.byKey(Key('history-menu-${b.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('history-delete-${b.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this entry and its image?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.history.entries, hasLength(2));

    await tester.tap(find.byKey(Key('history-menu-${b.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('history-delete-${b.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(h.history.entries.map((e) => e.id), [a.id]);
    expect(find.text('Delete me'), findsNothing);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('clearing everything needs a confirmation', (tester) async {
    await h.history.insert(_entry('One'));
    await h.history.insert(_entry('Two'));
    await openHistory(tester);

    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete all history entries and their images?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.history.entries, hasLength(2));

    await tester.tap(find.byKey(const Key('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(h.history.entries, isEmpty);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
  });

  testWidgets('deleting an entry also deletes its image file', (tester) async {
    final image = h.images.imagesDir..createSync(recursive: true);
    final file = File('${image.path}/pic.jpg')..writeAsBytesSync([1, 2, 3]);
    final saved = await h.history.insert(
      _entry('With image', imagePath: 'images/pic.jpg'),
    );
    await openHistory(tester);

    await tester.tap(find.byKey(Key('history-menu-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('history-delete-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    // File deletion is real I/O.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(file.existsSync(), isFalse);
    expect(h.history.entries, isEmpty);
  });
}
