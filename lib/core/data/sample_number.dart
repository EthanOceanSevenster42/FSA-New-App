import 'package:drift/drift.dart';

import 'local_database.dart';

/// The internal sample number, made up by the app rather than typed
/// (Ethan, 2026-09-25), the way a rejection number is:
/// `S-<inspector>-<yyyyMMdd>-<nnn>`, where nnn counts the samples this
/// inspector has taken today across raw and processed meat. It goes on the
/// sample bag and the laboratory's sheet, so two bags from one day can
/// never carry the same number.
abstract final class SampleNumber {
  static String generate({
    required int inspectorId,
    required DateTime on,
    required int takenTodayBefore,
  }) {
    final date = '${on.year}'
        '${on.month.toString().padLeft(2, '0')}'
        '${on.day.toString().padLeft(2, '0')}';
    final sequence = (takenTodayBefore + 1).toString().padLeft(3, '0');
    return 'S-$inspectorId-$date-$sequence';
  }

  /// The next number for a sample taken [on] (today unless said), counted
  /// from what this device holds for [inspectorUsername]. [exceptUuid] is
  /// the record being numbered, which must not count itself.
  static Future<String> next(
    LocalDatabase database, {
    required String inspectorUsername,
    required String exceptUuid,
    DateTime? on,
  }) async {
    final day = on ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final inspector = await database.findUser(inspectorUsername);
    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) =>
              t.isSampled.equals(true) &
              t.inspectorUsername.equals(inspectorUsername) &
              t.inspectedAt.isBetweenValues(start, end) &
              t.clientUuid.equals(exceptUuid).not()))
        .get();
    final pmp = await (database.select(database.pmpInspections)
          ..where((t) =>
              t.isSampled.equals(true) &
              t.inspectorUsername.equals(inspectorUsername) &
              t.inspectedAt.isBetweenValues(start, end) &
              t.clientUuid.equals(exceptUuid).not()))
        .get();
    return generate(
      inspectorId: inspector?.id ?? 0,
      on: day,
      takenTodayBefore: raw.length + pmp.length,
    );
  }
}
