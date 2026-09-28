import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Approving a grouped inspection in Inspection Management (Ethan,
/// 2026-09-24): once it is on the server, the inspector approves it, and the
/// approval goes to the server — now, or on the next sync.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 24, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
          completedAt: Value(when),
          isUploaded: const Value(true),
        ));
  });
  tearDown(() => db.close());

  Future<StoreVisit> row() async =>
      (await db.select(db.storeVisits).get()).single;

  test('approving is kept on the device until the server has it', () async {
    final visits = VisitRepository(db);
    await visits.approve('visit-1', at: DateTime(2026, 9, 24, 12, 30));
    expect((await row()).approvedAt, DateTime(2026, 9, 24, 12, 30));
    expect((await row()).approvalSent, isFalse);
    expect(await visits.pendingApprovals(), hasLength(1));
  });

  test('the approval goes to the approve endpoint with its time', () async {
    late http.Request sent;
    final visits = VisitRepository(db, baseUrl: 'https://server.test',
        client: MockClient((request) async {
      sent = request;
      return http.Response('{"approved": true}', 200);
    }));
    await visits.approve('visit-1', at: DateTime.utc(2026, 9, 24, 12, 30));

    expect(await visits.sendPendingApprovals(token: 'jwt'), 1);
    expect(sent.url.path, '/api/visits/visit-1/approve/');
    expect(sent.headers['Authorization'], 'Bearer jwt');
    expect(jsonDecode(sent.body)['approved'], isTrue);
    expect(jsonDecode(sent.body)['approved_at'], '2026-09-24T12:30:00.000Z');
    expect((await row()).approvalSent, isTrue);
    expect(await visits.pendingApprovals(), isEmpty);
  });

  test('a refused approval keeps waiting for the next sync', () async {
    final visits = VisitRepository(db,
        baseUrl: 'https://server.test',
        client: MockClient((_) async => http.Response('', 503)));
    await visits.approve('visit-1');
    expect(await visits.sendPendingApprovals(token: 'jwt'), 0);
    expect(await visits.pendingApprovals(), hasLength(1));
  });

  test('a visit never approved has nothing to send', () async {
    expect(await VisitRepository(db).pendingApprovals(), isEmpty);
  });

  test('taking the approval back is sent the same way', () async {
    final bodies = <Map<String, dynamic>>[];
    final visits = VisitRepository(db, baseUrl: 'https://server.test',
        client: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }));
    await visits.approve('visit-1');
    await visits.sendPendingApprovals(token: 'jwt');

    await visits.unapprove('visit-1');
    expect((await row()).approvedAt, isNull);
    expect(await visits.pendingApprovals(), hasLength(1),
        reason: 'the server still holds the approval');
    expect(await visits.sendPendingApprovals(token: 'jwt'), 1);
    expect(bodies.last['approved'], isFalse);
    expect(bodies.last['approved_at'], isNull);
    expect((await row()).approvalSent, isTrue);
  });

  test('a visit not yet on the server has no approval to send', () async {
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals('visit-1')))
        .write(const StoreVisitsCompanion(isUploaded: Value(false)));
    final visits = VisitRepository(db);
    await visits.approve('visit-1');
    expect(await visits.pendingApprovals(), isEmpty);
  });
}
