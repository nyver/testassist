import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../ocr/domain/question_parser.dart';
import 'models.dart';

final draftControllerProvider =
    AsyncNotifierProvider<DraftController, QuestionDraft?>(DraftController.new);

/// Suggests the id of a newly added option from the last one: the next letter
/// or number, or an empty id when there is no obvious successor.
String suggestNextOptionId(List<OptionItem> options) {
  if (options.isEmpty) return 'A';
  final last = options.last.id.trim();
  final number = int.tryParse(last);
  if (number != null) return '${number + 1}';
  if (last.runes.length == 1) {
    final code = last.runes.first;
    final isLetter =
        (code >= 0x41 && code < 0x5A) || // A-Y
        (code >= 0x61 && code < 0x7A) || // a-y
        (code >= 0x410 && code < 0x42F) || // А-Э
        (code >= 0x430 && code < 0x44F); // а-э
    if (isLetter) return String.fromCharCode(code + 1);
  }
  return '';
}

/// The question being edited. Every change is persisted (debounced), and
/// [flush] writes immediately, so the draft survives process death.
class DraftController extends AsyncNotifier<QuestionDraft?> {
  static const _saveDelay = Duration(milliseconds: 400);
  static const _parser = QuestionParser();

  Timer? _saveTimer;

  @override
  Future<QuestionDraft?> build() {
    ref.onDispose(() => _saveTimer?.cancel());
    return ref.read(draftRepositoryProvider).load();
  }

  QuestionDraft? get _draft => state.value;

  /// Replaces the draft with a freshly recognized question. The previous
  /// draft's image is deleted: it only ever belonged to that draft.
  Future<void> startNew({
    required String? imagePath,
    required String ocrText,
  }) async {
    await _deleteCurrentImage();
    final parsed = _parser.parse(ocrText);
    final draft = QuestionDraft(
      imagePath: imagePath,
      ocrText: ocrText,
      questionText: parsed.question,
      options: parsed.options,
      sendImage: false,
    );
    _saveTimer?.cancel();
    state = AsyncData(draft);
    await ref.read(draftRepositoryProvider).save(draft);
  }

  /// What the parser found in the current raw OCR text, for the warning.
  ParsedQuestion parseCurrent() => _parser.parse(_draft?.ocrText ?? '');

  void updateOcrText(String text) => _change((d) => d.copyWith(ocrText: text));

  void updateQuestion(String text) =>
      _change((d) => d.copyWith(questionText: text));

  void updateOption(int index, OptionItem option) => _change((d) {
    if (index < 0 || index >= d.options.length) return d;
    final options = [...d.options]..[index] = option;
    return d.copyWith(options: options);
  });

  void addOption() => _change((d) {
    final option = OptionItem(id: suggestNextOptionId(d.options), text: '');
    return d.copyWith(options: [...d.options, option]);
  });

  void removeOption(int index) => _change((d) {
    if (index < 0 || index >= d.options.length) return d;
    return d.copyWith(options: [...d.options]..removeAt(index));
  });

  /// Moves an option by [delta] positions (negative is up).
  void moveOption(int index, int delta) => _change((d) {
    final target = index + delta;
    if (index < 0 ||
        index >= d.options.length ||
        target < 0 ||
        target >= d.options.length) {
      return d;
    }
    final options = [...d.options];
    final moved = options.removeAt(index);
    options.insert(target, moved);
    return d.copyWith(options: options);
  });

  void setSendImage({required bool value}) =>
      _change((d) => d.copyWith(sendImage: value));

  /// Re-parses the (possibly edited) raw OCR text and replaces the question
  /// and options with the result.
  void reparse() => _change((d) {
    final parsed = _parser.parse(d.ocrText);
    return d.copyWith(questionText: parsed.question, options: parsed.options);
  });

  /// Turns the image switch off when the selected model cannot take images.
  /// Returns true when the switch was on and had to be turned off, so the UI
  /// can explain why.
  bool enforceVisionGate({required bool modelSupportsVision}) {
    final draft = _draft;
    if (draft == null || modelSupportsVision || !draft.sendImage) return false;
    _change((d) => d.copyWith(sendImage: false));
    return true;
  }

  /// Writes the draft now. Call when leaving the screen and before sending.
  Future<void> flush() async {
    _saveTimer?.cancel();
    final draft = _draft;
    if (draft != null) await ref.read(draftRepositoryProvider).save(draft);
  }

  /// Removes the draft after its analysis was saved. The image file is not
  /// deleted: the history entry took it over (or the caller deleted it).
  Future<void> clearAfterSave() async {
    _saveTimer?.cancel();
    await ref.read(draftRepositoryProvider).clear();
    state = const AsyncData(null);
  }

  /// Throws the draft away together with its image.
  Future<void> discard() async {
    _saveTimer?.cancel();
    await _deleteCurrentImage();
    await ref.read(draftRepositoryProvider).clear();
    state = const AsyncData(null);
  }

  void _change(QuestionDraft Function(QuestionDraft) update) {
    final draft = _draft;
    if (draft == null) return;
    state = AsyncData(update(draft));
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(flush()));
  }

  Future<void> _deleteCurrentImage() async {
    final path = _draft?.imagePath ?? (await future)?.imagePath;
    if (path != null) await ref.read(imageStoreProvider).delete(path);
  }
}
