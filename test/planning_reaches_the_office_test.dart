import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/calendar/data/planned_visit_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The office's copy of an inspector's planning.
///
/// Planning used to live only on the tablet in somebody's bag, so nobody
/// could answer "what has Kutlwano got on for Tuesday" without telephoning
/// her. It is copied up on sync now.
///
/// These hold the parts that are easy to get wrong: a plan goes up once
/// and not again, an edit sends it again, and a removal is told to the
/// office rather than simply vanishing — an inspector with two handsets
/// would otherwise have each one deleting the other's week.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final tuesday = DateTime(2026, 11, 3);

  /// A repository whose requests are captured instead of sent.
  (PlannedVisitRepository, List<Map<String, dynamic>>) repoThatRecords({
    int status = 200,
  }) {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      sent.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"written": 1}', status);
    });
    return (
      PlannedVisitRepository(db,
          baseUrl: 'https://inspector-app.test', client: client),
      sent,
    );
  }

  test('a new plan is waiting to go up', () async {
    final (planner, _) = repoThatRecords();
    await planner.save(
        inspector: 'kutlwano',
        plannedFor: tuesday,
        facilityName: 'Country fair product');
    expect(await planner.pendingUploads('kutlwano'), hasLength(1));
  });

  test('it goes up once, and not again', () async {
    final (planner, sent) = repoThatRecords();
    await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');

    expect(await planner.uploadPending(token: 't', inspector: 'kutlwano'), 1);
    expect(sent, hasLength(1));
    expect(await planner.pendingUploads('kutlwano'), isEmpty);

    // Nothing has changed, so the next sync sends nothing and makes no
    // request at all.
    expect(await planner.uploadPending(token: 't', inspector: 'kutlwano'), 0);
    expect(sent, hasLength(1), reason: 'no second request');
  });

  test('editing it sends it again', () async {
    final (planner, sent) = repoThatRecords();
    final id = await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
    await planner.uploadPending(token: 't', inspector: 'kutlwano');

    await planner.save(
        uuid: id,
        inspector: 'kutlwano',
        plannedFor: tuesday,
        facilityName: 'Depot',
        note: 'ask for the manager');
    expect(await planner.uploadPending(token: 't', inspector: 'kutlwano'), 1);
    expect(sent.last['plans'][0]['note'], 'ask for the manager');
  });

  test('moving it to another day sends it again', () async {
    final (planner, sent) = repoThatRecords();
    final id = await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
    await planner.uploadPending(token: 't', inspector: 'kutlwano');

    await planner.reschedule(id, DateTime(2026, 11, 5));
    await planner.uploadPending(token: 't', inspector: 'kutlwano');
    expect(sent.last['plans'][0]['planned_for'], '2026-11-05');
  });

  test('starting the inspection off it sends it again', () async {
    // The office's board says "started" off this, so it has to travel.
    final (planner, sent) = repoThatRecords();
    final id = await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
    await planner.uploadPending(token: 't', inspector: 'kutlwano');

    await planner.markStarted(id, 'visit-abc');
    await planner.uploadPending(token: 't', inspector: 'kutlwano');
    expect(sent.last['plans'][0]['started_visit_uuid'], 'visit-abc');
  });

  group('removing a plan', () {
    test('hides it at once but still tells the office', () async {
      final (planner, sent) = repoThatRecords();
      final id = await planner.save(
          inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
      await planner.uploadPending(token: 't', inspector: 'kutlwano');

      await planner.delete(id);
      expect(await planner.all('kutlwano'), isEmpty,
          reason: 'gone from the calendar the moment it is removed');

      expect(await planner.uploadPending(token: 't', inspector: 'kutlwano'), 1);
      expect(sent.last['plans'][0]['removed'], isTrue,
          reason: 'absence is not proof of deletion; it has to say so');
    });

    test('is swept off the device once the office has it', () async {
      final (planner, _) = repoThatRecords();
      final id = await planner.save(
          inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
      await planner.delete(id);
      await planner.uploadPending(token: 't', inspector: 'kutlwano');

      expect(await planner.byUuid(id), isNull,
          reason: 'the tombstone has done its one job');
      expect(await planner.pendingUploads('kutlwano'), isEmpty);
    });
  });

  test('a refused upload keeps everything waiting for the next sync',
      () async {
    final (planner, _) = repoThatRecords(status: 503);
    await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');

    await expectLater(
      planner.uploadPending(token: 't', inspector: 'kutlwano'),
      throwsA(isA<Exception>()),
    );
    expect(await planner.pendingUploads('kutlwano'), hasLength(1),
        reason: 'a plan the server did not take must not be marked as sent');
  });

  test('only the signed-in inspector\'s plans go up', () async {
    // The server files each plan under whoever's token sent it, so another
    // inspector's week going up here would be a lie about who is doing
    // what.
    final (planner, sent) = repoThatRecords();
    await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Hers');
    await planner.save(
        inspector: 'neo', plannedFor: tuesday, facilityName: 'His');

    await planner.uploadPending(token: 't', inspector: 'kutlwano');
    final names = [
      for (final p in sent.single['plans'] as List) p['facility_name'],
    ];
    expect(names, ['Hers']);
  });

  test('a device with no server keeps planning to itself', () async {
    final planner = PlannedVisitRepository(db);
    await planner.save(
        inspector: 'kutlwano', plannedFor: tuesday, facilityName: 'Depot');
    expect(await planner.uploadPending(token: 't', inspector: 'kutlwano'), 0);
    expect(await planner.all('kutlwano'), hasLength(1),
        reason: 'planning still works with nowhere to send it');
  });

  test('the date goes up as a plain calendar day', () async {
    // A timestamp would be read back in the server's timezone and could
    // land the visit on the day before.
    final (planner, sent) = repoThatRecords();
    await planner.save(inspector: 'kutlwano', plannedFor: DateTime(2026, 1, 5));
    await planner.uploadPending(token: 't', inspector: 'kutlwano');
    expect(sent.single['plans'][0]['planned_for'], '2026-01-05');
  });
}
