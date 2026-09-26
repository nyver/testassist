import 'package:flutter/foundation.dart';

import '../../questions/domain/models.dart';

/// Reasons a parse result deserves the "could not reliably recognize" warning.
enum ParseWarning { noText, emptyQuestion, tooFewOptions, duplicateIds }

/// The question and options found in recognized text.
@immutable
class ParsedQuestion {
  const ParsedQuestion({
    required this.question,
    required this.options,
    required this.warnings,
  });

  final String question;
  final List<OptionItem> options;
  final Set<ParseWarning> warnings;

  /// True when the user should be warned that recognition was unreliable:
  /// nothing recognized, no question, or fewer than two options.
  bool get isLowQuality =>
      warnings.contains(ParseWarning.noText) ||
      warnings.contains(ParseWarning.emptyQuestion) ||
      warnings.contains(ParseWarning.tooFewOptions);
}

enum _Family { latin, cyrillic, number }

@immutable
class _Marker {
  const _Marker(this.family, this.label, this.rest);

  final _Family family;

  /// Upper-case label without punctuation, for example `B`, `Б` or `12`.
  final String label;

  /// Text that follows the marker on the same line.
  final String rest;
}

/// Splits recognized text into a question and options.
///
/// Option markers are a Latin letter, a Cyrillic letter (either case) or a
/// number from 1 to 99, followed by `.` or `)`, or enclosed as `(X)`.
///
/// The parser first looks for the longest run of markers of one family whose
/// labels follow each other (A, B, C, or А, Б, В, or 1, 2, 3). That family is
/// the option family. Text before the run is the question; a leading question
/// number is dropped when the options are lettered. Lines without a marker
/// after the run start continue the current option. Without any run, the first
/// lettered marker starts the options, so a lone option is still found and the
/// user is warned.
class QuestionParser {
  const QuestionParser();

  static const _letter = r'[A-Za-zА-яЁё]';
  static final _enclosed = RegExp(
    '^\\(\\s*($_letter|\\d{1,2})\\s*\\)\\s*(.*)\$',
  );
  static final _punctuated = RegExp('^($_letter|\\d{1,2})\\s*[.)]\\s*(.*)\$');
  static final _decimal = RegExp(r'^\d{1,2}\.\d');
  static final _questionNumber = RegExp(r'^\d{1,3}\s*[.)]\s*(.+)$');

  static const _latinAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  // Both the complete alphabet and the traditional enumeration alphabet that
  // skips Ё, Й, Ъ, Ы and Ь are accepted as sequences.
  static const _cyrillicFull = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ';
  static const _cyrillicList = 'АБВГДЕЖЗИКЛМНОПРСТУФХЦЧШЩЭЮЯ';

  ParsedQuestion parse(String text) {
    final lines = text
        .split(RegExp(r'\r\n|\r|\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const ParsedQuestion(
        question: '',
        options: [],
        warnings: {
          ParseWarning.noText,
          ParseWarning.emptyQuestion,
          ParseWarning.tooFewOptions,
        },
      );
    }

    final markers = lines.map(_markerOf).toList();
    final start = _optionStart(markers);

    if (start == null) {
      return _result(_joinQuestion(lines, null), const []);
    }

    final family = markers[start.index]!.family;
    final options = <OptionItem>[];
    for (var i = start.index; i < lines.length; i++) {
      final marker = markers[i];
      if (marker != null && marker.family == family) {
        options.add(OptionItem(id: marker.label, text: marker.rest));
      } else if (options.isNotEmpty) {
        final last = options.removeLast();
        options.add(
          last.copyWith(
            text: last.text.isEmpty ? lines[i] : '${last.text} ${lines[i]}',
          ),
        );
      }
    }

    final questionLines = lines.sublist(0, start.index);
    return _result(_joinQuestion(questionLines, family), options);
  }

  ParsedQuestion _result(String question, List<OptionItem> options) {
    final ids = options.map((o) => o.id).toList();
    return ParsedQuestion(
      question: question,
      options: options,
      warnings: {
        if (question.isEmpty) ParseWarning.emptyQuestion,
        if (options.length < 2) ParseWarning.tooFewOptions,
        if (ids.toSet().length != ids.length) ParseWarning.duplicateIds,
      },
    );
  }

  String _joinQuestion(List<String> lines, _Family? optionFamily) {
    var question = lines.join(' ').trim();
    if (optionFamily != _Family.number) {
      // "5. What is 2+2?" before lettered options: the 5 is not an option.
      final match = _questionNumber.firstMatch(question);
      if (match != null) question = match.group(1)!.trim();
    }
    return question;
  }

  /// Finds where the options start, or null when no line looks like an option.
  ({int index})? _optionStart(List<_Marker?> markers) {
    int? bestStart;
    var bestLength = 1;
    _Family? bestFamily;

    for (var i = 0; i < markers.length; i++) {
      final first = markers[i];
      if (first == null) continue;

      var length = 1;
      var previous = first.label;
      for (var j = i + 1; j < markers.length; j++) {
        final next = markers[j];
        if (next == null || next.family != first.family) continue;
        if (!_follows(first.family, previous, next.label)) break;
        length++;
        previous = next.label;
      }

      if (length < 2) continue;
      final better =
          length > bestLength ||
          (length == bestLength &&
              bestFamily == _Family.number &&
              first.family != _Family.number);
      if (better) {
        bestStart = i;
        bestLength = length;
        bestFamily = first.family;
      }
    }
    if (bestStart != null) return (index: bestStart);

    // No run: fall back to the first lettered marker, so a single option is
    // still found (the caller reports too few options).
    for (var i = 0; i < markers.length; i++) {
      final m = markers[i];
      if (m != null && m.family != _Family.number) return (index: i);
    }
    return null;
  }

  bool _follows(_Family family, String previous, String next) {
    switch (family) {
      case _Family.number:
        final p = int.tryParse(previous);
        final n = int.tryParse(next);
        return p != null && n != null && n == p + 1;
      case _Family.latin:
        return _succession(_latinAlphabet, previous, next);
      case _Family.cyrillic:
        return _succession(_cyrillicFull, previous, next) ||
            _succession(_cyrillicList, previous, next);
    }
  }

  bool _succession(String alphabet, String previous, String next) {
    final i = alphabet.indexOf(previous);
    return i >= 0 && i + 1 < alphabet.length && alphabet[i + 1] == next;
  }

  _Marker? _markerOf(String line) {
    if (_decimal.hasMatch(line)) return null; // "2.5 metres", not option 2

    final match = _enclosed.firstMatch(line) ?? _punctuated.firstMatch(line);
    if (match == null) return null;

    final raw = match.group(1)!;
    final rest = match.group(2)!.trim();
    if (int.tryParse(raw) != null) {
      final n = int.parse(raw);
      if (n < 1 || n > 99) return null;
      return _Marker(_Family.number, '$n', rest);
    }
    final upper = raw.toUpperCase();
    final isLatin = _latinAlphabet.contains(upper);
    return _Marker(isLatin ? _Family.latin : _Family.cyrillic, upper, rest);
  }
}
