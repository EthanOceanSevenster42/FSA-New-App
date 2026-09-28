import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Taking a commodity back off the plan.
///
/// The plan counts one row for poultry and that row covers all three of its
/// records — grading, the label checklist and a QUID determination. Reducing
/// it has to remove whichever was actually captured: a record the plan no
/// longer asks for still sits under "captured so far", and the visit refuses
/// to be signed off while it is there.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  const visitUuid = 'visit-1';
  final when = DateTime(2026, 9, 1, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: when,
        ));
  });
  tearDown(() async => db.close());

  Future<void> seedQuid({DateTime? at, String status = 'completed'}) async {
    await db
        .into(db.poultryQuidInspections)
        .insert(PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: when,
          updatedAt: at ?? when,
          visitUuid: const Value(visitUuid),
          status: Value(status),
        ));
    await db.into(db.poultryQuidSamples).insert(
        PoultryQuidSamplesCompanion.insert(inspectionUuid: 'quid-1'));
    await db.into(db.poultryQuidInjectors).insert(
        PoultryQuidInjectorsCompanion.insert(
            inspectionUuid: 'quid-1', position: 1));
  }

  Future<void> seedGrading({DateTime? at}) =>
      db.into(db.poultryInspections).insert(PoultryInspectionsCompanion.insert(
            clientUuid: 'grading-1',
            inspectedAt: when,
            updatedAt: at ?? when,
            visitUuid: const Value(visitUuid),
            status: const Value('completed'),
          ));

  Future<void> seedRaw() =>
      db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-1',
            inspectedAt: when,
            updatedAt: when,
            visitUuid: const Value(visitUuid),
            status: const Value('completed'),
          ));

  test('reducing poultry removes a QUID determination', () async {
    await seedQuid();
    final removed = await visits
        .discardDraftMember(visitUuid, 'poultry', includeCaptured: true);

    expect(removed, isTrue);
    expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
    // Its carcasses and the set-up's injectors go with it.
    expect(await db.select(db.poultryQuidSamples).get(), isEmpty);
    expect(await db.select(db.poultryQuidInjectors).get(), isEmpty);
    expect(await visits.members(visitUuid), isEmpty);
  });

  test('it takes the newest of the three poultry records', () async {
    await seedGrading(at: when);
    await seedQuid(at: when.add(const Duration(minutes: 30)));

    await visits
        .discardDraftMember(visitUuid, 'poultry', includeCaptured: true);

    // The QUID one was captured last, so that is the one being undone.
    expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
    expect((await db.select(db.poultryInspections).get()), hasLength(1));
  });

  test('it never reaches across to another commodity', () async {
    await seedQuid();
    await seedRaw();

    await visits
        .discardDraftMember(visitUuid, 'poultry', includeCaptured: true);

    // The raw inspection is not poultry's to remove — it used to be what the
    // fall-through deleted.
    expect((await db.select(db.rawRmpInspections).get()), hasLength(1));
  });

  test('a kind nothing knows about removes nothing at all', () async {
    await seedRaw();
    final removed = await visits
        .discardDraftMember(visitUuid, 'fruitveg', includeCaptured: true);

    expect(removed, isFalse);
    expect((await db.select(db.rawRmpInspections).get()), hasLength(1));
  });

  test('discarding the visit takes its QUID record with it', () async {
    await seedQuid();
    expect(await visits.discardWithMembers(visitUuid), isTrue);

    // Left behind it is a record counted by nothing and reachable from
    // nowhere.
    expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
    expect(await db.select(db.poultryQuidSamples).get(), isEmpty);
    expect(await db.select(db.poultryQuidInjectors).get(), isEmpty);
  });
}
