import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/data/eggs_sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A handset must not hand a sync problem back to the inspector.
///
/// Reference rows are keyed by the server's own ids, and a captured inspection
/// stores those ids. Point the app at a different server — or set a device up
/// before the origin was recorded — and every upload comes back "Invalid pk …
/// object does not exist". The inspector is standing at a consignment, not at
/// a desk; the app has to notice and fix itself.
class _Online implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onStatusChanged => const Stream<bool>.empty();
}

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });
  tearDown(() async => db.close());

  Future<void> pendingInspection(String uuid) async {
    final at = DateTime(2026, 8, 2, 9);
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            inspectedAt: at,
            updatedAt: at,
            status: const Value('completed'),
          ),
        );
  }

  test('a rejected record refreshes the lookups and goes up by itself',
      () async {
    var posts = 0;
    var referenceFetches = 0;

    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('reference')) {
          referenceFetches++;
          return http.Response(
            jsonEncode({'cursor': null, 'counts': {}, 'data': {}}),
            200,
          );
        }
        if (request.method == 'POST') {
          posts++;
          // The first attempt carries ids from the other server.
          if (posts == 1) {
            return http.Response(
              jsonEncode({
                'tray_size': ['Invalid pk "3" - object does not exist.']
              }),
              400,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 201);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');
    await pendingInspection('insp-1');

    final service = EggsSyncService(repository: repo, connectivity: _Online());
    final saved = await repo.inspectionByUuid('insp-1');
    final sent = await service.sendNow(saved!);

    expect(sent, isTrue, reason: 'the inspector should never see this fail');
    expect(referenceFetches, greaterThan(0),
        reason: 'the stale lookups must be replaced');
    expect(posts, 2, reason: 'refreshed, then retried');

    await service.dispose();
  });

  test('a record the server keeps refusing is reported, not looped', () async {
    var posts = 0;
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('reference')) {
          return http.Response(
            jsonEncode({'cursor': null, 'counts': {}, 'data': {}}),
            200,
          );
        }
        if (request.method == 'POST') {
          posts++;
          return http.Response(jsonEncode({'detail': 'no'}), 400);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');
    await pendingInspection('insp-2');

    final service = EggsSyncService(repository: repo, connectivity: _Online());
    final saved = await repo.inspectionByUuid('insp-2');
    final sent = await service.sendNow(saved!);

    expect(sent, isFalse);
    expect(service.lastOutcome, SendOutcome.rejected);
    // Refreshed once and retried once — not a download loop.
    expect(posts, 2);

    // A second send does not refresh all over again.
    await service.sendNow(saved);
    expect(posts, 3);

    await service.dispose();
  });

  group('knowing where the lookups came from', () {
    test('data of unknown origin is treated as foreign', () async {
      final repo = EggsRepository(
        baseUrl: 'http://prod.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      // Rows exist but nothing recorded which server they came from — exactly
      // a handset set up before the origin was tracked. "Grade A" is the
      // giveaway: this server only has Grade 1, 2 and 3.
      await db.into(db.eggSizes).insert(
            EggSizesCompanion.insert(
              id: const Value(1),
              name: 'Small',
              minMassG: 33,
            ),
          );
      await db.into(db.eggGrades).insert(
            EggGradesCompanion.insert(
              id: const Value(1),
              name: 'Grade A',
              rank: 1,
            ),
          );

      expect(await repo.referenceIsForeign, isTrue);
    });

    test('an empty device is not foreign, just empty', () async {
      final repo = EggsRepository(
        baseUrl: 'http://prod.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await repo.referenceIsForeign, isFalse);
    });

    test('data from this same server is kept', () async {
      final repo = EggsRepository(
        baseUrl: 'http://prod.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await db.writeSyncState(
        EggsRepository.referenceOriginKey,
        'http://prod.test',
      );
      expect(await repo.referenceIsForeign, isFalse);
    });

    test('data from another server is discarded', () async {
      final repo = EggsRepository(
        baseUrl: 'http://prod.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await db.writeSyncState(
        EggsRepository.referenceOriginKey,
        'http://laptop.test',
      );
      expect(await repo.referenceIsForeign, isTrue);
    });

    test('clearing lookups keeps the inspector\'s own work', () async {
      final repo = EggsRepository(
        baseUrl: 'http://prod.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await pendingInspection('mine');
      await db.into(db.eggSizes).insert(
            EggSizesCompanion.insert(
              id: const Value(1),
              name: 'Small',
              minMassG: 33,
            ),
          );
      await db.into(db.eggGrades).insert(
            EggGradesCompanion.insert(
              id: const Value(1),
              name: 'Grade A',
              rank: 1,
            ),
          );

      await repo.clearReferenceData();

      expect(await repo.gradeRefs(), isEmpty, reason: 'lookups go');
      expect(await repo.inspectionByUuid('mine'), isNotNull,
          reason: 'captured work stays — it is not ours to discard');
    });
  });

  test('the background pass heals a stale lookup table too', () async {
    // The path that matters most: work captured earlier, retrying on a timer
    // with nobody watching. Handling this only on the save path left every
    // older record stuck retrying into the same 400 forever.
    var posts = 0;
    var referenceFetches = 0;
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('reference')) {
          referenceFetches++;
          return http.Response(
            jsonEncode({'cursor': null, 'counts': {}, 'data': {}}),
            200,
          );
        }
        if (request.method == 'POST') {
          posts++;
          if (posts == 1) {
            return http.Response(
              jsonEncode({
                'reason': ['Invalid pk "7" - object does not exist.']
              }),
              400,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 201);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');
    await pendingInspection('older');

    final service = EggsSyncService(repository: repo, connectivity: _Online());
    final report = await service.syncNow();

    expect(report.inspectionsSent, 1,
        reason: 'a background pass must recover on its own');
    expect(referenceFetches, greaterThan(0));
    expect((await repo.inspectionByUuid('older'))!.isUploaded, isTrue);

    await service.dispose();
  });
}
