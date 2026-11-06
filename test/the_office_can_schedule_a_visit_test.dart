import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/calendar/data/planned_visit_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A visit the office puts on an inspector's calendar.
///
/// Planning only ever went one way: the handset told the office what the
/// inspector intended. The office could see the week but not add to it, so
/// a recall or a complaint had to be telephoned through and the inspector
/// wrote it in a notebook — exactly the thing the calendar replaced.
///
/// These hold the rules that make an office-scheduled visit safe to rely
/// on. It has to arrive, it has to be recognisable as somebody else's
/// instruction, and — the awkward half — it must not fight with what the
/// inspector has been doing on the tablet meanwhile.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const base = 'https://inspector.example';

  /// A server that hands back [plans] on the download.
  PlannedVisitRepository serving(List<Map<String, Object?>> plans) =>
      PlannedVisitRepository(
        db,
        baseUrl: base,
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer tok');
          return http.Response(jsonEncode({'plans': plans}), 200);
        }),
      );

  Map<String, Object?> officePlan({
    String uuid = 'office-1',
    String plannedFor = '2026-11-20',
    String facility = 'SHOPRITE Soshanguve',
    String updatedAt = '2026-11-02T10:00:00Z',
    bool removed = false,
    String startedVisitUuid = '',
  }) =>
      {
        'uuid': uuid,
        'planned_for': plannedFor,
        'facility_name': facility,
        'facility_address': '12 Mill Road, Epping',
        'facility_phone': '021 555 0100',
        'commodities': 'Eggs, Poultry',
        'note': 'Complaint about date marking',
        'started_visit_uuid': startedVisitUuid,
        'removed': removed,
        'created_at': '2026-11-02T10:00:00Z',
        'updated_at': updatedAt,
        'scheduled_by_office': true,
        'scheduled_by': 'Neo Noe',
      };

  test('a visit the office scheduled arrives on the handset', () async {
    final planner = serving([officePlan()]);

    final brought =
        await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    expect(brought, 1);
    final mine = await planner.all('kutlwano');
    expect(mine, hasLength(1));
    final plan = mine.single;
    expect(plan.facilityName, 'SHOPRITE Soshanguve');
    expect(plan.plannedFor, DateTime(2026, 11, 20));
    expect(commoditiesOf(plan), ['Eggs', 'Poultry']);
    expect(plan.note, 'Complaint about date marking');
  });

  test('it is marked as the office\'s, with who scheduled it', () async {
    // The whole reason the handset is told: the app refuses to let the
    // inspector delete a visit that is not theirs, and the card names
    // somebody to ring if the day does not work.
    final planner = serving([officePlan()]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    final plan = (await planner.all('kutlwano')).single;
    expect(plan.scheduledByOffice, isTrue);
    expect(plan.scheduledBy, 'Neo Noe');
  });

  test('it does not go straight back up as though it were a local edit',
      () async {
    final planner = serving([officePlan()]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    expect(await planner.pendingUploads('kutlwano'), isEmpty);
  });

  test('a withdrawn visit comes off the calendar', () async {
    final planner = serving([officePlan()]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');
    expect(await planner.all('kutlwano'), hasLength(1));

    final withdrawn = serving([
      officePlan(removed: true, updatedAt: '2026-11-02T11:00:00Z'),
    ]);
    final changed =
        await withdrawn.downloadPlans(token: 'tok', inspector: 'kutlwano');

    expect(changed, 1);
    expect(await withdrawn.all('kutlwano'), isEmpty);
  });

  test('an unsent change on the tablet is not overwritten', () async {
    // The guard this needs most. An inspector who moved a visit this
    // morning and has not synced yet must not have it dragged back by the
    // copy the office still holds — their edit goes up in the same sync.
    final planner = serving([officePlan(facility: 'The office spelling')]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    await planner.save(
      uuid: 'office-1',
      inspector: 'kutlwano',
      plannedFor: DateTime(2026, 11, 28),
      facilityName: 'What the inspector typed',
    );
    expect(await planner.pendingUploads('kutlwano'), hasLength(1));

    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    final plan = (await planner.all('kutlwano')).single;
    expect(plan.facilityName, 'What the inspector typed');
    expect(plan.plannedFor, DateTime(2026, 11, 28));
  });

  test('an older copy from the server is not news', () async {
    final planner = serving([officePlan(updatedAt: '2026-11-02T10:00:00Z')]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');

    // Same row, but the server's copy is older than what is held here.
    final stale = serving([
      officePlan(
          facility: 'STALE', updatedAt: '2026-11-01T08:00:00Z'),
    ]);
    final changed =
        await stale.downloadPlans(token: 'tok', inspector: 'kutlwano');

    expect(changed, 0);
    expect((await stale.all('kutlwano')).single.facilityName,
        'SHOPRITE Soshanguve');
  });

  test('a visit already started here is never un-started', () async {
    // The office's copy can lag. Clearing this would offer the inspector a
    // second inspection for a call they have already made.
    final planner = serving([officePlan()]);
    await planner.downloadPlans(token: 'tok', inspector: 'kutlwano');
    await planner.markStarted('office-1', 'visit-abc');
    // markStarted is a local edit, so let the server be the newer copy
    // again — otherwise the unsent-change guard would decide this test.
    await (db.update(db.plannedVisits)
          ..where((t) => t.uuid.equals('office-1')))
        .write(const PlannedVisitsCompanion(isUploaded: Value(true)));

    final later = serving([officePlan(updatedAt: '2026-11-03T09:00:00Z')]);
    await later.downloadPlans(token: 'tok', inspector: 'kutlwano');

    expect((await later.all('kutlwano')).single.startedVisitUuid, 'visit-abc');
  });

  test('a handset never pointed at a server simply does not ask', () async {
    final offline = PlannedVisitRepository(db);
    expect(await offline.downloadPlans(token: 'tok', inspector: 'k'), 0);
  });

  test('a refusal is raised, not swallowed', () async {
    final broken = PlannedVisitRepository(
      db,
      baseUrl: base,
      client: MockClient((_) async => http.Response('nope', 503)),
    );
    expect(
      () => broken.downloadPlans(token: 'tok', inspector: 'k'),
      throwsA(isA<Exception>()),
    );
  });
}
