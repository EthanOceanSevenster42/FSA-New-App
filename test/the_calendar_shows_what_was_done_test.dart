import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/calendar/data/conducted_visit_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The calendar's third colour: the inspections that were actually done.
///
/// It could show what is owed (follow-ups) and what is intended (plans),
/// but not what happened — so a month an inspector had worked flat out
/// looked identical to one they had not started, and the only way to see
/// the week behind you was Inspection Management, a list with no dates on
/// a grid. These hold what the green entries mean, because the whole point
/// of a separate colour is that it says something the other two do not.
void main() {
  late LocalDatabase db;
  late ConductedVisitRepository conducted;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    conducted = ConductedVisitRepository(db, VisitRepository(db));
  });
  tearDown(() => db.close());

  final tuesday = DateTime(2026, 11, 3, 14, 20);

  Future<void> visit(
    String uuid, {
    required String inspector,
    String facility = 'Shoprite Bridge City',
    String address = '2 Bridge City Blvd, KwaMashu',
    DateTime? completedAt,
  }) async {
    await VisitRepository(db).create(uuid, inspector);
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals(uuid)))
        .write(StoreVisitsCompanion(
      facilityName: Value(facility),
      facilityAddress: Value(address),
      completedAt: Value(completedAt),
    ));
  }

  test('a signed-off visit lands on the day it was signed off', () async {
    await visit('v-1', inspector: 'kutlwano', completedAt: tuesday);

    final done = await conducted.all('kutlwano');
    expect(done, hasLength(1));
    // The grid is keyed by the day at midnight; the time is kept apart so
    // the card can still say "signed off at 14:20".
    expect(done.single.date, DateTime(2026, 11, 3));
    expect(done.single.completedAt, tuesday);
    expect(done.single.facility, 'Shoprite Bridge City');
    expect(done.single.address, '2 Bridge City Blvd, KwaMashu');
  });

  test('a visit still being captured is NOT an inspection conducted',
      () async {
    // The guard the colour exists for. A visit opened at the door and not
    // yet signed off is work in progress; putting it on the calendar in
    // green would say an inspection was done that nobody has finished.
    await visit('v-open', inspector: 'kutlwano');

    expect(await conducted.all('kutlwano'), isEmpty);
  });

  test('another inspector\'s visits stay off this calendar', () async {
    await visit('v-mine', inspector: 'kutlwano', completedAt: tuesday);
    await visit('v-theirs', inspector: 'lwandile', completedAt: tuesday);

    final mine = await conducted.all('kutlwano');
    expect(mine.map((c) => c.uuid), ['v-mine']);
  });

  test('a visit captured before anyone signed in belongs to whoever holds '
      'the handset', () async {
    // The same tolerant reading of ownership the planning and inspection
    // tables use — and the name is matched without case, so `Kutlwano` at
    // sign-in still finds work saved as `kutlwano`.
    await visit('v-nobody', inspector: '', completedAt: tuesday);
    await visit('v-cased', inspector: 'kutlwano', completedAt: tuesday);

    final mine = await conducted.all('Kutlwano');
    expect(mine.map((c) => c.uuid).toSet(), {'v-nobody', 'v-cased'});
  });

  test('the card names the commodities that were captured, once each',
      () async {
    await visit('v-1', inspector: 'kutlwano', completedAt: tuesday);
    // Two poultry records under one visit — a grading and its labelling
    // sheet — are one commodity on the calendar, not two.
    await db.into(db.poultryInspections).insert(
          PoultryInspectionsCompanion.insert(
            clientUuid: 'p-1',
            inspectedAt: tuesday,
            updatedAt: tuesday,
            visitUuid: const Value('v-1'),
            status: const Value('completed'),
          ),
        );
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            clientUuid: 'e-1',
            inspectedAt: tuesday,
            updatedAt: tuesday,
            visitUuid: const Value('v-1'),
            status: const Value('completed'),
          ),
        );

    final done = await conducted.all('kutlwano');
    expect(done.single.commodities, ['Eggs', 'Poultry']);
  });

  test('an occurrence report is still a day worked', () async {
    // It carries no inspections at all, so a card built from the member
    // list alone would show an empty visit. The calendar says what it was.
    await visit('v-occ', inspector: 'kutlwano', completedAt: tuesday);
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals('v-occ')))
        .write(const StoreVisitsCompanion(isOccurrenceReport: Value(true)));

    final done = await conducted.all('kutlwano');
    expect(done.single.isOccurrenceReport, isTrue);
    expect(done.single.commodities, isEmpty);
  });

  test('the most recent visit is first', () async {
    await visit('v-old', inspector: 'kutlwano',
        completedAt: DateTime(2026, 10, 28, 9));
    await visit('v-new', inspector: 'kutlwano', completedAt: tuesday);

    final done = await conducted.all('kutlwano');
    expect(done.map((c) => c.uuid), ['v-new', 'v-old']);
  });
}
