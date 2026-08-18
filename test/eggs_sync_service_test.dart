import 'dart:async';
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

/// Connectivity the test drives directly, so "went offline" and "came back"
/// are deterministic rather than dependent on a real radio.
class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({bool online = true}) : _online = online;

  bool _online;
  final _controller = StreamController<bool>.broadcast();

  void goOnline() {
    _online = true;
    _controller.add(true);
  }

  void goOffline() {
    _online = false;
    _controller.add(false);
  }

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  Future<void> dispose() => _controller.close();
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

  /// Repository whose uploads succeed or fail on command, counting calls.
  ({EggsRepository repo, List<String> uploaded, void Function(bool) setOk})
      buildRepo() {
    final uploaded = <String>[];
    var ok = true;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        if (!ok) return http.Response('server exploded', 500);
        uploaded.add(request.url.path);
        return http.Response(jsonEncode({'ok': true}), 201);
      }
      return http.Response(jsonEncode({'results': []}), 200);
    });
    return (
      repo: EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: client,
      ),
      uploaded: uploaded,
      setOk: (v) => ok = v,
    );
  }

  Future<void> signInHappened() =>
      db.writeSyncState('auth.accessToken', 'token-123');

  Future<void> pendingInspection(String uuid, {String status = 'completed'}) {
    final now = DateTime.now();
    return db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            inspectedAt: now,
            updatedAt: now,
            status: Value(status),
            isUploaded: const Value(false),
          ),
        );
  }

  Future<void> pendingDirection(String uuid) {
    final now = DateTime.now();
    return db.into(db.eggDirections).insert(
          EggDirectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            qualityPart: const Value(true),
            issuedAt: now,
            updatedAt: now,
            status: const Value('completed'),
            isUploaded: const Value(false),
          ),
        );
  }

  test('uploads everything pending and marks it sent', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');
    await pendingInspection('i2');
    await pendingDirection('d1');

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    final report = await sync.syncNow();

    expect(report.inspectionsSent, 2);
    expect(report.directionsSent, 1);
    expect(report.failures, 0);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isTrue);
    expect((await r.repo.directionByUuid('d1'))!.isUploaded, isTrue);
  });

  test('does nothing offline, and the record stays pending', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity(online: false);
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    final report = await sync.syncNow();

    expect(report.sent, 0);
    expect(r.uploaded, isEmpty);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isFalse);
  });

  test('does nothing without a token, rather than failing repeatedly',
      () async {
    // Never signed in online, so there is no credential to upload with.
    final r = buildRepo();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    expect((await sync.syncNow()).sent, 0);
    expect(r.uploaded, isEmpty);
  });

  test('a failed upload leaves the record pending for the next pass',
      () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    r.setOk(false);
    final failed = await sync.syncNow();
    expect(failed.failures, 1);
    expect(failed.sent, 0);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isFalse);

    // The server recovers; the same record goes up unprompted.
    r.setOk(true);
    final retried = await sync.syncNow();
    expect(retried.inspectionsSent, 1);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isTrue);
  });

  test('a draft is never uploaded', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('draft-1', status: 'draft');

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    expect((await sync.syncNow()).sent, 0);
    expect(r.uploaded, isEmpty);
  });

  test('an already-uploaded record is not sent twice', () async {
    final r = buildRepo();
    await signInHappened();
    final now = DateTime.now();
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: 'done',
            inspectedAt: now,
            updatedAt: now,
            status: const Value('completed'),
            isUploaded: const Value(true),
          ),
        );

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    expect((await sync.syncNow()).sent, 0);
    expect(r.uploaded, isEmpty);
  });

  test('coming back online triggers a pass without being asked', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity(online: false);
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);
    addTearDown(sync.dispose);

    sync.start();
    await Future<void>.delayed(Duration.zero);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isFalse);

    final reported = sync.onSync.first;
    connectivity.goOnline();
    final report = await reported.timeout(const Duration(seconds: 5));

    expect(report.inspectionsSent, 1);
    expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isTrue);
  });

  test('going offline does not trigger a pass', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity(online: false);
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);
    addTearDown(sync.dispose);

    sync.start();
    connectivity.goOffline();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(r.uploaded, isEmpty);
  });

  test('overlapping passes do not upload the same record twice', () async {
    final r = buildRepo();
    await signInHappened();
    await pendingInspection('i1');

    final connectivity = FakeConnectivity();
    addTearDown(connectivity.dispose);
    final sync =
        EggsSyncService(repository: r.repo, connectivity: connectivity);

    final results = await Future.wait([sync.syncNow(), sync.syncNow()]);

    expect(results.map((x) => x.sent).reduce((a, b) => a + b), 1);
    expect(r.uploaded.length, 1);
  });

  group('sendNow', () {
    test('reports true only when the server confirmed', () async {
      final r = buildRepo();
      await signInHappened();
      await pendingInspection('i1');

      final connectivity = FakeConnectivity();
      addTearDown(connectivity.dispose);
      final sync =
          EggsSyncService(repository: r.repo, connectivity: connectivity);

      final inspection = (await r.repo.inspectionByUuid('i1'))!;
      expect(await sync.sendNow(inspection), isTrue);
    });

    test('reports false offline instead of throwing at the inspector',
        () async {
      final r = buildRepo();
      await signInHappened();
      await pendingInspection('i1');

      final connectivity = FakeConnectivity(online: false);
      addTearDown(connectivity.dispose);
      final sync =
          EggsSyncService(repository: r.repo, connectivity: connectivity);

      final inspection = (await r.repo.inspectionByUuid('i1'))!;
      expect(await sync.sendNow(inspection), isFalse);
      expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isFalse);
    });

    test('reports false when the server rejects it, and it stays pending',
        () async {
      final r = buildRepo();
      await signInHappened();
      await pendingInspection('i1');
      r.setOk(false);

      final connectivity = FakeConnectivity();
      addTearDown(connectivity.dispose);
      final sync =
          EggsSyncService(repository: r.repo, connectivity: connectivity);

      final inspection = (await r.repo.inspectionByUuid('i1'))!;
      expect(await sync.sendNow(inspection), isFalse);
      expect((await r.repo.inspectionByUuid('i1'))!.isUploaded, isFalse);
    });
  });
}
