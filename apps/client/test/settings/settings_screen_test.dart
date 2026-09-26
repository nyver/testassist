import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/features/settings/data/settings_repository.dart';

import '../support/harness.dart';

AnswerDisplayMode? _selectedMode(WidgetTester tester) => tester
    .widget<RadioGroup<AnswerDisplayMode>>(
      find.byType(RadioGroup<AnswerDisplayMode>),
    )
    .groupValue;

void main() {
  late Harness h;
  setUp(() async {
    h = await Harness.create();
    await h.seedServer();
  });
  tearDown(() => h.dispose());

  Future<void> openSettings(WidgetTester tester) async {
    await pumpApp(tester, h);
    await tester.tap(find.byKey(const Key('main-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults: short explanation, images kept', (tester) async {
    await openSettings(tester);

    expect(find.text('Answer + short explanation'), findsOneWidget);
    expect(_selectedMode(tester), AnswerDisplayMode.short);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('delete-images-switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('the display mode is stored', (tester) async {
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('mode-detailed')));
    await tester.pumpAndSettle();

    expect(h.prefs.getString(SettingsRepository.displayModeKey), 'detailed');
    expect(_selectedMode(tester), AnswerDisplayMode.detailed);
  });

  testWidgets('"Delete images after analysis" is stored', (tester) async {
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('delete-images-switch')));
    await tester.pumpAndSettle();

    expect(h.prefs.getBool(SettingsRepository.deleteImagesKey), isTrue);
  });

  testWidgets('links to the server settings', (tester) async {
    await openSettings(tester);
    await tester.tap(find.byKey(const Key('settings-server')));
    await tester.pumpAndSettle();
    expect(find.text('Trusted certificate fingerprint'), findsOneWidget);
  });

  testWidgets('the app is usable in Russian', (tester) async {
    await pumpApp(tester, h);
    // The default test locale is English; rebuild with Russian.
    await tester.binding.setLocale('ru', 'RU');
    await tester.pumpAndSettle();
    expect(find.text('Сфотографировать'), findsOneWidget);
    expect(find.text('Выбрать изображение'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
  });
}
