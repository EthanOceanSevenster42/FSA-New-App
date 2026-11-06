import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/calendar/data/planned_visit_repository.dart';

/// An inspector's own entries on the follow-up calendar.
///
/// The calendar could only ever show what the records dictated: the
/// "correct by" dates that say where an inspector must return. The week
/// they actually intend to work — the depots on Tuesday, the abattoir on
/// the way back — lived in a notebook, so the office saw it only once the
/// work was done and the inspector carried it in their head until then.
///
/// These hold the rules that make a plan safe to rely on: it belongs to
/// whoever made it, it survives being edited, and starting the inspection
/// from it does not quietly erase the plan or let it be started twice.
void main() {
  late LocalDatabase db;
  late PlannedVisitRepository planner;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    planner = PlannedVisitRepository(db);
  });
  tearDown(() => db.close());

  final tuesday = DateTime(2026, 11, 3);
  final wednesday = DateTime(2026, 11, 4);

  test('a plan is kept for the day it was made for', () async {
    await planner.save(
      inspector: 'kutlwano',
      plannedFor: tuesday,
      facilityName: 'Country fair product',
      facilityAddress: '12 Mill Road, Epping',
      facilityPhone: '021 555 0100',
      commodities: const ['Poultry'],
      note: 'Ask for the QUID records from last month',
    );

    final mine = await planner.all('kutlwano');
    expect(mine, hasLength(1));
    expect(mine.single.plannedFor, tuesday);
    expect(mine.single.facilityName, 'Country fair product');
    expect(commoditiesOf(mine.single), ['Poultry']);
    expect(mine.single.note, 'Ask for the QUID records from last month');
    expect(mine.single.startedVisitUuid, isEmpty,
        reason: 'a plan has not been acted on until it is started');
  });

  test('a visit can be planned for several commodities at once', () async {
    // One call at a store is one grouped inspection covering whatever is
    // found there. Raw processed meat and eggs on the same visit is the
    // ordinary case, not an edge one.
    final id = await planner.save(
      inspector: 'neo',
      plannedFor: tuesday,
      facilityName: 'Pick n Pay Lynnwood',
      commodities: const ['Eggs', 'Raw Processed Meat'],
    );
    expect(commoditiesOf((await planner.byUuid(id))!),
        ['Eggs', 'Raw Processed Meat']);
  });

  test('choosing no commodity leaves none, not an empty one', () async {
    final id = await planner.save(inspector: 'neo', plannedFor: tuesday);
    expect(commoditiesOf((await planner.byUuid(id))!), isEmpty);
  });

  test('a blank among the commodities is dropped', () async {
    final id = await planner.save(
      inspector: 'neo',
      plannedFor: tuesday,
      commodities: const ['Eggs', '  ', ''],
    );
    expect(commoditiesOf((await planner.byUuid(id))!), ['Eggs']);
  });

  test('plans are listed soonest first', () async {
    await planner.save(
        inspector: 'neo', plannedFor: wednesday, facilityName: 'Second');
    await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'First');

    expect(
      (await planner.all('neo')).map((p) => p.facilityName),
      ['First', 'Second'],
    );
  });

  test('a plan belongs to the inspector who made it', () async {
    await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Hers');
    await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'His');

    expect((await planner.all('kutlwano')).map((p) => p.facilityName), ['Hers']);
    expect((await planner.all('neo')).map((p) => p.facilityName), ['His']);
  });

  test('a name capitalised differently at sign-in still finds the plan',
      () async {
    // Sign-in names are typed, and the same inspector reaches the handset as
    // "Lwandile.D" one day and "lwandile.d" the next. Their week must not
    // vanish over it.
    await planner.save(
        inspector: 'lwandile.d', plannedFor: tuesday, facilityName: 'Depot');
    expect((await planner.all('Lwandile.D')), hasLength(1));
  });

  test('a plan saved with no owner is shown to whoever is holding the handset',
      () async {
    await planner.save(
        inspector: '', plannedFor: tuesday, facilityName: 'Unowned');
    expect((await planner.all('kutlwano')), hasLength(1),
        reason: 'an ownerless row is not hidden from everyone');
  });

  test('editing a plan changes it rather than making a second one', () async {
    final id = await planner.save(
      inspector: 'neo',
      plannedFor: tuesday,
      facilityName: 'Kekkel en Kraai',
      commodities: const ['Poultry'],
    );
    await planner.save(
      uuid: id,
      inspector: 'neo',
      plannedFor: wednesday,
      facilityName: 'Kekkel en Kraai',
      commodities: const ['Poultry', 'Eggs'],
    );

    final mine = await planner.all('neo');
    expect(mine, hasLength(1));
    expect(mine.single.uuid, id);
    expect(mine.single.plannedFor, wednesday);
    expect(commoditiesOf(mine.single), ['Poultry', 'Eggs']);
  });

  test('editing a started plan does not un-start it', () async {
    // The inspection has already been opened from this plan. Correcting the
    // time afterwards must not offer Start a second time and make a second
    // visit for the same stop.
    final id = await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'Depot');
    await planner.markStarted(id, 'visit-abc');
    await planner.save(
        uuid: id,
        inspector: 'neo',
        plannedFor: tuesday,
        facilityName: 'Depot',
        commodities: const ['Eggs']);

    final plan = (await planner.all('neo')).single;
    expect(plan.startedVisitUuid, 'visit-abc');
    expect(commoditiesOf(plan), ['Eggs']);
  });

  test('the created date survives an edit, the updated date moves', () async {
    final id = await planner.save(inspector: 'neo', plannedFor: tuesday);
    final first = (await planner.byUuid(id))!;
    // A full second, because these columns are stored to the second: a
    // shorter wait would prove nothing either way.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await planner.save(uuid: id, inspector: 'neo', plannedFor: wednesday);
    final second = (await planner.byUuid(id))!;

    expect(second.createdAt, first.createdAt,
        reason: 'an edit is not a new plan');
    expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
  });

  test('moving a plan to another day keeps everything else', () async {
    final id = await planner.save(
      inspector: 'neo',
      plannedFor: tuesday,
      facilityName: 'Kekkel en Kraai',
      commodities: const ['Poultry', 'Eggs'],
      note: 'bring the scale',
    );
    await planner.reschedule(id, wednesday);

    final plan = (await planner.byUuid(id))!;
    expect(plan.plannedFor, wednesday);
    expect(plan.facilityName, 'Kekkel en Kraai');
    expect(commoditiesOf(plan), ['Poultry', 'Eggs']);
    expect(plan.note, 'bring the scale');
  });

  test('a plan is stored at midnight whatever time of day it was made',
      () async {
    // The calendar groups by day, and a row stamped 14:07 would land in no
    // day box at all.
    final id = await planner.save(
        inspector: 'neo', plannedFor: DateTime(2026, 11, 3, 14, 7, 32));
    expect((await planner.byUuid(id))!.plannedFor, tuesday);
  });

  test('an address is stored in the one spelling of itself', () async {
    // Caught on the tablet: a correct but untidy address went up exactly as
    // typed, so the office would have had "western Cape" and "Western
    // Cape" as two different places. Tidying lives here, at the write, so
    // no caller can skip it.
    final id = await planner.save(
      inspector: 'neo',
      plannedFor: tuesday,
      facilityAddress: '12  Mill Road ,,Epping,Cape   Town , western cape , 7460 ',
    );
    expect((await planner.byUuid(id))!.facilityAddress,
        '12 Mill Road, Epping, Cape Town, Western Cape, 7460');
  });

  test('an address that cannot be read is still kept as written', () async {
    // The form refuses a malformed address, but nothing here may throw one
    // away: whatever is in the box is what the inspector meant.
    final id = await planner.save(
        inspector: 'neo',
        plannedFor: tuesday,
        facilityAddress: 'behind the Engen, ask for Thabo');
    expect((await planner.byUuid(id))!.facilityAddress,
        'behind the Engen, ask for Thabo');
  });

  test('a removed plan is gone and takes nothing with it', () async {
    final keep = await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'Keep');
    final drop = await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'Drop');
    await planner.delete(drop);

    expect((await planner.all('neo')).map((p) => p.facilityName), ['Keep']);
    expect(await planner.byUuid(keep), isNotNull);
  });
}
