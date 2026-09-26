import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/features/questions/domain/draft_controller.dart';
import 'package:test_assistant/features/questions/domain/model_selection_controller.dart';
import 'package:test_assistant/features/questions/domain/models.dart';
import 'package:test_assistant/features/settings/data/settings_repository.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  tearDown(() => h.dispose());

  Future<ProviderContainer> containerWith({
    Map<String, Object> prefs = const {},
  }) async {
    h = await Harness.create(preferences: prefs);
    await h.seedServer();
    final c = ProviderContainer(
      retry: (count, error) => null,
      overrides: h.overrides(),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('draft controller', () {
    const text = 'Which protocol?\nA. HTTP\nB. HTTPS\nC. TLS';

    Future<DraftController> started(ProviderContainer c) async {
      await c.read(draftControllerProvider.future);
      final controller = c.read(draftControllerProvider.notifier);
      await controller.startNew(imagePath: null, ocrText: text);
      return controller;
    }

    test('startNew parses the text and persists the draft', () async {
      final c = await containerWith();
      await started(c);

      final draft = c.read(draftControllerProvider).value!;
      expect(draft.questionText, 'Which protocol?');
      expect(draft.options.map((o) => o.id), ['A', 'B', 'C']);
      expect(draft.ocrText, text, reason: 'the raw text stays unchanged');
      expect(draft.sendImage, isFalse, reason: 'off by default');
      expect(h.drafts.draft!.questionText, 'Which protocol?');
    });

    group('the image switch after recognition', () {
      Future<QuestionDraft> startWith(String? image, String ocr) async {
        final c = await containerWith();
        await c.read(draftControllerProvider.future);
        await c
            .read(draftControllerProvider.notifier)
            .startNew(imagePath: image, ocrText: ocr);
        return c.read(draftControllerProvider).value!;
      }

      test('starts on when nothing was recognized', () async {
        expect((await startWith('images/x.jpg', '')).sendImage, isTrue);
      });

      test('starts on when only garbage or too little was found', () async {
        // No options were found in it.
        expect(
          (await startWith('images/x.jpg', 'CTOIMLa Poccuu?')).sendImage,
          isTrue,
        );
        // One option is not a question yet.
        expect(
          (await startWith('images/x.jpg', 'Q?\nA. one')).sendImage,
          isTrue,
        );
      });

      test('stays off when the question and options were recognized', () async {
        expect((await startWith('images/x.jpg', text)).sendImage, isFalse);
      });

      test('stays off without an image', () async {
        expect((await startWith(null, '')).sendImage, isFalse);
      });

      test('the user can still turn it off', () async {
        final c = await containerWith();
        await c.read(draftControllerProvider.future);
        final controller = c.read(draftControllerProvider.notifier);
        await controller.startNew(imagePath: 'images/x.jpg', ocrText: '');

        controller.setSendImage(value: false);

        expect(c.read(draftControllerProvider).value!.sendImage, isFalse);
      });
    });

    test('a stored draft is restored by a new container', () async {
      final c1 = await containerWith();
      final controller = await started(c1);
      controller.updateQuestion('Edited?');
      await controller.flush();

      // Simulates a restart after the process was killed.
      final c2 = ProviderContainer(
        retry: (count, error) => null,
        overrides: h.overrides(),
      );
      addTearDown(c2.dispose);
      final restored = await c2.read(draftControllerProvider.future);

      expect(restored!.questionText, 'Edited?');
      expect(restored.options.map((o) => o.id), ['A', 'B', 'C']);
    });

    test(
      'edits are saved shortly after, and flush saves immediately',
      () async {
        final c = await containerWith();
        final controller = await started(c);
        final savesBefore = h.drafts.saves;

        controller.updateQuestion('One');
        controller.updateQuestion('Two');
        expect(h.drafts.saves, savesBefore, reason: 'debounced');
        await controller.flush();

        expect(h.drafts.saves, savesBefore + 1);
        expect(h.drafts.draft!.questionText, 'Two');
      },
    );

    test('add, remove and reorder options', () async {
      final c = await containerWith();
      final controller = await started(c);
      List<String> ids() => c
          .read(draftControllerProvider)
          .value!
          .options
          .map((o) => o.id)
          .toList();

      controller.addOption();
      expect(ids(), [
        'A',
        'B',
        'C',
        'D',
      ], reason: 'the next letter is suggested');

      controller.moveOption(0, 1);
      expect(ids(), ['B', 'A', 'C', 'D']);
      controller.moveOption(0, -1); // already first: no change
      expect(ids(), ['B', 'A', 'C', 'D']);
      controller.moveOption(3, 1); // already last: no change
      expect(ids(), ['B', 'A', 'C', 'D']);

      controller.removeOption(1);
      expect(ids(), ['B', 'C', 'D']);
      controller.removeOption(99); // out of range: ignored
      expect(ids(), ['B', 'C', 'D']);

      controller.updateOption(0, const OptionItem(id: 'X', text: 'ex'));
      expect(c.read(draftControllerProvider).value!.options.first.text, 'ex');
    });

    test(
      'reparse rebuilds the question and options from the raw text',
      () async {
        final c = await containerWith();
        final controller = await started(c);

        controller.updateOcrText('New?\n1. red\n2. blue');
        controller.updateQuestion('manual');
        controller.reparse();

        final draft = c.read(draftControllerProvider).value!;
        expect(draft.questionText, 'New?');
        expect(draft.options.map((o) => o.id), ['1', '2']);
      },
    );

    test('suggested ids follow the existing style', () {
      expect(suggestNextOptionId(const []), 'A');
      expect(suggestNextOptionId(const [OptionItem(id: '2', text: '')]), '3');
      expect(suggestNextOptionId(const [OptionItem(id: 'В', text: '')]), 'Г');
      expect(suggestNextOptionId(const [OptionItem(id: 'b', text: '')]), 'c');
      expect(suggestNextOptionId(const [OptionItem(id: 'Z', text: '')]), '');
      expect(suggestNextOptionId(const [OptionItem(id: 'opt', text: '')]), '');
    });

    test(
      'a text-only model turns the image switch off and reports it',
      () async {
        final c = await containerWith();
        final controller = await started(c);
        controller.setSendImage(value: true);

        final changed = controller.enforceVisionGate(
          modelSupportsVision: false,
        );

        expect(changed, isTrue);
        expect(c.read(draftControllerProvider).value!.sendImage, isFalse);
        expect(
          controller.enforceVisionGate(modelSupportsVision: false),
          isFalse,
        );
      },
    );

    test('a vision model leaves the switch alone', () async {
      final c = await containerWith();
      final controller = await started(c);
      controller.setSendImage(value: true);

      expect(controller.enforceVisionGate(modelSupportsVision: true), isFalse);
      expect(c.read(draftControllerProvider).value!.sendImage, isTrue);
    });

    test('starting a new draft deletes the previous draft image', () async {
      final c = await containerWith();
      await c.read(draftControllerProvider.future);
      final image = await h.images.create();
      await image.file.writeAsBytes([1]);
      final controller = c.read(draftControllerProvider.notifier);
      await controller.startNew(imagePath: image.relativePath, ocrText: text);
      expect(await image.file.exists(), isTrue);

      await controller.startNew(imagePath: null, ocrText: text);

      expect(await image.file.exists(), isFalse);
    });

    test('discard removes the draft and its image', () async {
      final c = await containerWith();
      await c.read(draftControllerProvider.future);
      final image = await h.images.create();
      await image.file.writeAsBytes([1]);
      final controller = c.read(draftControllerProvider.notifier);
      await controller.startNew(imagePath: image.relativePath, ocrText: text);

      await controller.discard();

      expect(h.drafts.draft, isNull);
      expect(c.read(draftControllerProvider).value, isNull);
      expect(await image.file.exists(), isFalse);
    });
  });

  group('model selection', () {
    Future<ModelSelection> load(ProviderContainer c) =>
        c.read(modelSelectionProvider.future);

    test('the first time the server defaults are selected', () async {
      final c = await containerWith();
      final s = await load(c);
      expect(s.providerId, 'openrouter');
      expect(s.modelId, 'vision-model');
      expect(s.supportsVision, isTrue);
      expect(s.providers.map((p) => p.id), ['openrouter', 'routerai']);
    });

    test('vision support is known for each model', () async {
      final c = await containerWith();
      await load(c);
      final controller = c.read(modelSelectionProvider.notifier);

      await controller.selectModel('text-model');

      final s = c.read(modelSelectionProvider).value!;
      expect(s.selectedModel!.supportsVision, isFalse);
      expect(s.supportsVision, isFalse);
    });

    test('the last selection is remembered and restored', () async {
      final c1 = await containerWith();
      await load(c1);
      await c1.read(modelSelectionProvider.notifier).selectProvider('routerai');
      expect(
        c1.read(modelSelectionProvider).value!.modelId,
        'router-model',
        reason: 'the provider default is picked',
      );

      // A fresh session with the same preferences.
      final c2 = ProviderContainer(
        retry: (count, error) => null,
        overrides: h.overrides(),
      );
      addTearDown(c2.dispose);
      final s = await load(c2);
      expect(s.providerId, 'routerai');
      expect(s.modelId, 'router-model');
    });

    test('a remembered model is preferred within its provider', () async {
      final c = await containerWith(
        prefs: {
          SettingsRepository.lastProviderKey: 'openrouter',
          SettingsRepository.lastModelKey: 'text-model',
        },
      );
      final s = await load(c);
      expect(s.modelId, 'text-model');
    });

    test(
      'an unavailable remembered selection falls back to the defaults',
      () async {
        final c = await containerWith(
          prefs: {
            SettingsRepository.lastProviderKey: 'gone-provider',
            SettingsRepository.lastModelKey: 'gone-model',
          },
        );
        final s = await load(c);
        expect(s.providerId, 'openrouter');
        expect(s.modelId, 'vision-model');

        final c2 = await containerWith(
          prefs: {
            SettingsRepository.lastProviderKey: 'openrouter',
            SettingsRepository.lastModelKey: 'gone-model',
          },
        );
        expect((await load(c2)).modelId, 'vision-model');
      },
    );

    test('selecting an unknown model is ignored', () async {
      final c = await containerWith();
      await load(c);
      await c.read(modelSelectionProvider.notifier).selectModel('nope');
      expect(c.read(modelSelectionProvider).value!.modelId, 'vision-model');
    });
  });
}
