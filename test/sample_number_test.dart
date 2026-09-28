import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/data/sample_number.dart';

/// The internal sample number is made up by the app (Ethan, 2026-09-25):
/// one per sample this inspector takes today, across raw and processed
/// meat, so two bags from one day never carry the same number.
void main() {
  late LocalDatabase db;
  final today = DateTime(2026, 9, 25, 10);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.syncedUsers).insert(
        SyncedUsersCompanion.insert(id: const Value(7), username: 'Ethan'));
  });
  tearDown(() => db.close());

  test('reads as S-<inspector>-<date>-<sequence>', () {
    expect(
        SampleNumber.generate(inspectorId: 7, on: today, takenTodayBefore: 0),
        'S-7-20260925-001');
    expect(
        SampleNumber.generate(inspectorId: 7, on: today, takenTodayBefore: 11),
        'S-7-20260925-012');
  });

  test('counts the samples already taken today, raw and processed meat',
      () async {
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-1',
          inspectedAt: today,
          updatedAt: today,
          inspectorUsername: const Value('Ethan'),
          isSampled: const Value(true),
        ));
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: today,
          updatedAt: today,
          inspectorUsername: const Value('Ethan'),
          isSampled: const Value(true),
        ));
    // Not counted: not sampled, another day, another inspector, itself.
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-2',
          inspectedAt: today,
          updatedAt: today,
          inspectorUsername: const Value('Ethan'),
        ));
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-3',
          inspectedAt: today.subtract(const Duration(days: 1)),
          updatedAt: today,
          inspectorUsername: const Value('Ethan'),
          isSampled: const Value(true),
        ));
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-4',
          inspectedAt: today,
          updatedAt: today,
          inspectorUsername: const Value('Kabelo'),
          isSampled: const Value(true),
        ));
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'this-one',
          inspectedAt: today,
          updatedAt: today,
          inspectorUsername: const Value('Ethan'),
          isSampled: const Value(true),
        ));

    expect(
        await SampleNumber.next(db,
            inspectorUsername: 'Ethan', exceptUuid: 'this-one', on: today),
        'S-7-20260925-003');
  });
}
