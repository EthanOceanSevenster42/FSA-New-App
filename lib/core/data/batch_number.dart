/// The batch number, as every commodity's form treats it.
///
/// Eggs, raw processed meat and processed meat all ask for one, and all
/// three had their own copy of the same rule. It lives here once so a batch
/// reads the same on whichever form it was captured.
abstract final class BatchNumber {
  /// What the office should see when the pack carries no batch code.
  static const none = 'N/A';

  /// Whether what was typed is a batch at all: a number (separators
  /// allowed), or a way of writing "there isn't one". Blank counts — a
  /// batch number is what the pack carries, not something the inspector can
  /// produce when it carries none — and is stored as [none].
  ///
  /// "None" is accepted alongside N/A because that is the word the original
  /// asks for on the raw form: "Batch Number - enter 'None' if not
  /// available".
  static bool valid(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return _isNone(t) || RegExp(r'^[0-9][0-9 \/-]*$').hasMatch(t);
  }

  /// What goes on the record: the number as typed, or [none] — left blank,
  /// written "NA", "n/a" or "None", it all files as the same thing, so the
  /// office is never left wondering whether a blank means no batch or an
  /// inspector who forgot to look (FSA, 2026-09-08).
  static String forRecord(String text) {
    final t = text.trim();
    if (t.isEmpty || _isNone(t)) return none;
    return t;
  }

  /// What the box is tidied to when the inspector leaves it: "na",
  /// "None" and the like become [none]; a blank stays blank, because the
  /// batch number is required (Ethan, 2026-09-24) — a pack with none is
  /// written N/A, not left empty.
  static String tidy(String text) =>
      text.trim().isEmpty ? '' : forRecord(text);

  /// Why the box cannot be saved as it is, or null when it can.
  static String? missing(String text) {
    if (text.trim().isEmpty) {
      return 'Batch Number is required — write N/A if the pack has none.';
    }
    if (!valid(text)) return 'A batch number, or N/A — nothing else counts.';
    return null;
  }

  static bool _isNone(String trimmed) {
    final squashed = trimmed.toUpperCase().replaceAll(' ', '');
    return squashed == 'N/A' || squashed == 'NA' || squashed == 'NONE';
  }
}
