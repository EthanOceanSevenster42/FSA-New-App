import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Egg and poultry inspections are not billed through the Request for
/// Invoice. A visit of only those keeps its RFI on the handset and does not
/// send it, so it never reaches the web folder documents are sent out from;
/// a visit that also holds a meat inspection sends it as before (Ethan,
/// 2026-09-29).
void main() {
  late LocalDatabase db;
  late VisitRepository visits;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: DateTime.utc(2026, 9, 29, 8),
          facilityName: const Value('Kroon Foods'),
        ));
  });
  tearDown(() => db.close());

  Future<void> egg() => db.into(db.eggInspections).insert(
        EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          inspectedAt: DateTime.utc(2026, 9, 29, 9),
          updatedAt: DateTime.utc(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          status: const Value('ready'),
        ),
      );

  Future<void> quid() => db.into(db.poultryQuidInspections).insert(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: DateTime.utc(2026, 9, 29, 9),
          updatedAt: DateTime.utc(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          status: const Value('ready'),
          facilityName: const Value('Kroon Foods'),
        ),
      );

  Future<void> pmp() => db.into(db.pmpInspections).insert(
        PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: DateTime.utc(2026, 9, 29, 10),
          updatedAt: DateTime.utc(2026, 9, 29, 10),
          visitUuid: const Value('visit-1'),
          status: const Value('ready'),
        ),
      );

  test('eggs alone keep the RFI on the handset', () async {
    await egg();
    expect(await visits.rfiStaysOnHandset('visit-1'), isTrue);
  });

  Future<void> labelling() => db.into(db.poultryLabelInspections).insert(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          inspectedAt: DateTime.utc(2026, 9, 29, 9),
          updatedAt: DateTime.utc(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          status: const Value('ready'),
        ),
      );

  Future<void> grading() => db.into(db.poultryInspections).insert(
        PoultryInspectionsCompanion.insert(
          clientUuid: 'grading-1',
          inspectedAt: DateTime.utc(2026, 9, 29, 9),
          updatedAt: DateTime.utc(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          status: const Value('ready'),
        ),
      );

  test('poultry alone keeps it on the handset: labelling, grading, QUID',
      () async {
    await labelling();
    await grading();
    await quid();
    expect(await visits.rfiStaysOnHandset('visit-1'), isTrue);
  });

  test('eggs and poultry keep it on the handset too', () async {
    await egg();
    await quid();
    expect(await visits.rfiStaysOnHandset('visit-1'), isTrue);
  });

  test('a meat inspection in the visit sends it as before', () async {
    await egg();
    await pmp();
    expect(await visits.rfiStaysOnHandset('visit-1'), isFalse);
  });

  test('an empty visit is not judged', () async {
    expect(await visits.rfiStaysOnHandset('visit-1'), isFalse);
  });
}
