import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Backing out of a commodity added to the plan by mistake.
///
/// A plan of one raw inspection with a draft open used to be a dead end: the
/// draft counted as captured, the minus button locked, and the visit could
/// not be signed off either, because an unfinished member blocks it.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seedVisit() => db.into(db.storeVisits).insert(
        StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: DateTime.utc(2026, 8, 24, 8),
          facilityName: const Value('Kroon Foods'),
          plannedRaw: const Value(1),
        ),
      );

  Future<void> seedRaw(String uuid, String status) =>
      db.into(db.rawRmpInspections).insert(
            RawRmpInspectionsCompanion.insert(
              clientUuid: uuid,
              inspectedAt: DateTime.utc(2026, 8, 24, 9),
              updatedAt: DateTime.utc(2026, 8, 24, 9),
              status: Value(status),
              visitUuid: const Value('visit-1'),
            ),
          );

  test('an unfinished raw inspection can be taken off the visit', () async {
    await seedVisit();
    await seedRaw('raw-1', 'draft');
    expect(await visits.members('visit-1'), hasLength(1));

    expect(await visits.discardDraftMember('visit-1', 'rawrmp'), isTrue);
    expect(await visits.members('visit-1'), isEmpty);
  });

  test('its photographs and signatures go with it', () async {
    await seedVisit();
    await seedRaw('raw-1', 'draft');
    await db.into(db.poultryPhotos).insert(
          PoultryPhotosCompanion.insert(
            recordUuid: 'raw-1',
            kind: 'rawrmp',
            filePath: '/tmp/one.jpg',
            capturedAt: DateTime.utc(2026, 8, 24, 9),
          ),
        );
    await db.into(db.poultrySignatures).insert(
          PoultrySignaturesCompanion.insert(
            recordUuid: 'raw-1',
            role: 'inspector',
            signedAt: DateTime.utc(2026, 8, 24, 9),
          ),
        );

    await visits.discardDraftMember('visit-1', 'rawrmp');

    expect(await db.select(db.poultryPhotos).get(), isEmpty);
    expect(await db.select(db.poultrySignatures).get(), isEmpty);
  });

  test('captured work is never dropped', () async {
    await seedVisit();
    await seedRaw('raw-1', 'ready');

    expect(await visits.discardDraftMember('visit-1', 'rawrmp'), isFalse,
        reason: 'an inspection that has been captured is a record');
    expect(await visits.members('visit-1'), hasLength(1));
  });

  test('the newest draft goes, not the oldest', () async {
    await seedVisit();
    await seedRaw('raw-old', 'draft');
    await seedRaw('raw-new', 'draft');
    await (db.update(db.rawRmpInspections)
          ..where((t) => t.clientUuid.equals('raw-new')))
        .write(RawRmpInspectionsCompanion(
            updatedAt: Value(DateTime.utc(2026, 8, 24, 11))));

    await visits.discardDraftMember('visit-1', 'rawrmp');

    final left = await visits.members('visit-1');
    expect(left.map((m) => m.uuid), ['raw-old']);
  });

  test('nothing to drop is not an error', () async {
    await seedVisit();
    expect(await visits.discardDraftMember('visit-1', 'rawrmp'), isFalse);
  });
}
