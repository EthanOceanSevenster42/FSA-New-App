import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// An egg inspection captured while the tablet pointed at a local server
/// holds that server's ids — facility type 13, reason 7 — which the live
/// server has never had and the bundled rules cannot name. The live server
/// refused it as `Invalid pk "13"` on every pass (Ethan, 2026-09-24). The
/// visit it belongs to keeps both answers as names, so the repair matches
/// through the visit instead.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 23, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    // The live server's rows, as the tablet holds them after a sync.
    for (final (id, name) in const [
      (1, 'Retailer/Distr. Center'),
      (2, 'Import'),
      (3, 'Producer'),
      (4, 'Pack House'),
    ]) {
      await db.into(db.eggFacilityTypes).insert(
          EggFacilityTypesCompanion.insert(id: Value(id), name: name));
    }
    for (final (id, name) in const [
      (1, 'Inspection'),
      (2, 'Follow-up Inspection'),
      (3, 'Complaint'),
    ]) {
      await db.into(db.eggInspectionReasons).insert(
          EggInspectionReasonsCompanion.insert(id: Value(id), name: name));
    }
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Shoprite Polokwane'),
          facilityType: const Value('Pack House'),
          inspectionReason: const Value('Inspection'),
        ));
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          visitUuid: const Value('visit-1'),
          inspectedAt: when,
          updatedAt: when,
          status: const Value('completed'),
          facilityTypeId: const Value(13),
          reasonId: const Value(7),
        ));
  });
  tearDown(() => db.close());

  test('ids only another server had are re-pointed through the visit',
      () async {
    final eggs = EggsRepository(database: db, baseUrl: '');
    expect(await eggs.repointLookupIds('egg-1'), isTrue);
    final row = (await db.select(db.eggInspections).get()).single;
    expect(row.facilityTypeId, 4, reason: 'Pack House on the live server');
    expect(row.reasonId, 1, reason: 'Inspection on the live server');
  });

  test('ids this device knows are left alone', () async {
    await (db.update(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-1')))
        .write(const EggInspectionsCompanion(
            facilityTypeId: Value(2), reasonId: Value(3)));
    final eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.repointLookupIds('egg-1');
    final row = (await db.select(db.eggInspections).get()).single;
    expect(row.facilityTypeId, 2);
    expect(row.reasonId, 3);
  });
}
