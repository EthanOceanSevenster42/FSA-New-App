import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/data/eggs_sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Pending work must go up by itself, without anyone pressing Send.
///
/// Retrying only when the signal returns misses everything that fails while
/// already online — a token that needed refreshing, a server restarting, a
/// request that timed out on one weak bar. Those sat untouched until the
/// connection happened to drop and come back, or the app was reopened. An
/// inspector should not have to arrange either.
class _AlwaysOnline implements ConnectivityService {
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

  Future<void> pending(String uuid) async {
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

  test('a send that failed while online is retried on its own', () async {
    var attempts = 0;
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('inspections')) {
          attempts++;
          // Fails the first time, as a restarting server would.
          if (attempts == 1) return http.Response('{"detail":"boom"}', 500);
          return http.Response(jsonEncode({'ok': true}), 201);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');
    await pending('insp-1');

    final service = EggsSyncService(
      repository: repo,
      connectivity: _AlwaysOnline(),
    );

    // First pass fails; the record stays pending.
    await service.syncNow();
    expect(attempts, 1);
    var row = await repo.inspectionByUuid('insp-1');
    expect(row!.isUploaded, isFalse, reason: 'the failure must not be lost');

    // The next pass — which the timer fires without anyone asking — succeeds.
    await service.syncNow();
    expect(attempts, 2);
    row = await repo.inspectionByUuid('insp-1');
    expect(row!.isUploaded, isTrue);

    await service.dispose();
  });

  test('the timer keeps trying without anyone asking', () {
    // fakeAsync lets the clock run without the test taking two minutes.
    fakeAsync((async) {
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'results': []}), 200),
        ),
      );
      final service = EggsSyncService(
        repository: repo,
        connectivity: _AlwaysOnline(),
      );

      service.start();
      async.flushMicrotasks();

      // Three intervals pass with nobody touching the app.
      async.elapse(EggsSyncService.retryInterval * 3);
      expect(async.periodicTimerCount, 1, reason: 'exactly one retry timer');

      unawaited(service.dispose());
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0,
          reason: 'disposing must not leave a timer running');
    });
  });

  test('the retry interval is sensible', () {
    // Short enough that a record does not linger, long enough to be invisible.
    expect(EggsSyncService.retryInterval.inSeconds, greaterThan(30));
    expect(EggsSyncService.retryInterval.inMinutes, lessThanOrEqualTo(5));
  });

  test('nothing pending means nothing is sent', () async {
    var posts = 0;
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.method == 'POST') posts++;
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');

    final service = EggsSyncService(
      repository: repo,
      connectivity: _AlwaysOnline(),
    );
    await service.syncNow();

    expect(posts, 0);
    await service.dispose();
  });
}
