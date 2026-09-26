import '../../../l10n/generated/app_localizations.dart';
import '../../history/domain/history_entry.dart';
import 'models.dart';

/// The options that were reported correct, as `(id, text)` pairs in the order
/// of the question's options. Falls back to the model's ids and the server's
/// answer text if an id is not among the options.
List<(String, String)> correctOptions(
  List<OptionItem> options,
  AnalysisResult result,
) {
  final byId = {for (final o in options) o.id: o.text};
  return [for (final id in result.correctOptionIds) (id, byId[id] ?? '')];
}

/// The question of an entry for display. An entry answered from the image alone
/// has none when the model could not read one.
String displayQuestion(AppLocalizations l10n, HistoryEntry entry) =>
    entry.questionText.trim().isEmpty
    ? l10n.questionFromImage
    : entry.questionText;

/// `B. HTTPS` style label of a correct option.
String optionLabel((String, String) option) =>
    option.$2.isEmpty ? option.$1 : '${option.$1}. ${option.$2}';

/// Plain text for Copy and Share: the question, the correct option(s) and the
/// explanation.
String composeShareText(AppLocalizations l10n, HistoryEntry entry) {
  final result = entry.result;
  final buffer = StringBuffer()
    ..writeln('${l10n.resultShareQuestion}: ${displayQuestion(l10n, entry)}');

  if (result.isUncertain) {
    buffer.writeln('${l10n.resultShareAnswer}: ${l10n.resultUncertain}');
  } else {
    final labels = correctOptions(
      entry.options,
      result,
    ).map(optionLabel).join('; ');
    buffer.writeln('${l10n.resultShareAnswer}: $labels');
  }

  final explanation = result.explanation;
  if (explanation != null && explanation.trim().isNotEmpty) {
    buffer.writeln('${l10n.resultShareExplanation}: $explanation');
  }
  return buffer.toString().trimRight();
}
