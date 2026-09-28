import 'package:drift/drift.dart';

import 'local_database.dart';

/// Every restricted particular the office lists, for any commodity, as the
/// one list every form offers.
///
/// The office keeps a list per commodity — eggs has two dozen keywords,
/// poultry four, raw only "Other" — so the same question read differently
/// on every form, and an inspector at a raw label had almost nothing to
/// choose from (Ethan, 2026-09-25: "make sure they all use the same one").
///
/// A pick that is on the form's own list is kept by that list's id, as it
/// always was. One from another commodity's list has no id on this record,
/// so it is kept the way a typed-in one is: as text, which every form
/// already stores and sends.
abstract final class RestrictedParticularsCatalogue {
  /// The names, once each, in the order the office lists them: eggs first,
  /// then poultry, raw and processed meat, each adding only what the lists
  /// before it did not have. "Other" goes last, being the catch-all.
  static Future<List<String>> names(LocalDatabase db) async {
    final eggs = await (db.select(db.eggRestrictedParticulars)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
    final poultry = await (db.select(db.poultryRestrictedParticulars)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final raw = await (db.select(db.rawRmpRestrictedParticulars)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final pmp = await (db.select(db.pmpRestrictedParticulars)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return merge([
      for (final r in eggs) r.keyword,
      for (final r in poultry) r.description,
      for (final r in raw) r.description,
      for (final r in pmp) r.description,
    ]);
  }

  /// [names] once each, the first spelling kept, blanks dropped, and
  /// "Other" moved to the end whatever list it came from.
  static List<String> merge(Iterable<String> names) {
    final seen = <String>{};
    final kept = <String>[];
    var other = '';
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      if (key == 'other') {
        other = name;
        continue;
      }
      kept.add(name);
    }
    if (other.isNotEmpty) kept.add(other);
    return kept;
  }
}
