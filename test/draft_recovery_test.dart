import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Recovering an inspection the app was killed in the middle of.
///
/// Android reclaims memory by killing whatever is in the background, and the
/// camera is the hungriest thing an inspector opens — so losing the process
/// while photographing a label is routine on a small handset. Everything
/// captured up to that point has to survive.
void main() {
  late LocalDatabase db;
  late EggsRepository repo;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(baseUrl: 'http://example.test', database: db);
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });

  tearDown(() async => db.close());

  Future<void> saveDraft(
    String uuid, {
    String client = 'Sunrise Poultry Farm',
    int eggs = 3,
    DateTime? at,
  }) async {
    final when = at ?? DateTime(2026, 8, 1, 9);
    await repo.saveInspection(
      EggInspectionsCompanion.insert(
        clientUuid: uuid,
        inspectedAt: when,
        updatedAt: when,
        status: const Value('draft'),
        clientName: Value(client),
        batchNumber: const Value('B-1'),
      ),
      [
        for (var i = 1; i <= eggs; i++)
          EggSamplesCompanion.insert(
            inspectionUuid: uuid,
            eggNumber: i,
            massG: Value(50.0 + i),
          ),
      ],
    );
  }

  group('finding an interrupted inspection', () {
    test('a draft is offered back', () async {
      await saveDraft('draft-1');

      final draft = await repo.latestDraft();

      expect(draft, isNotNull);
      expect(draft!.clientName, 'Sunrise Poultry Farm');
      expect(draft.status, 'draft');
    });

    test('a finished inspection is not offered back', () async {
      final at = DateTime(2026, 8, 1, 9);
      await repo.saveInspection(
        EggInspectionsCompanion.insert(
          clientUuid: 'done-1',
          inspectedAt: at,
          updatedAt: at,
          status: const Value('completed'),
        ),
        const [],
      );

      expect(await repo.latestDraft(), isNull);
    });

    test('the most recent draft wins', () async {
      await saveDraft('old', client: 'Older', at: DateTime(2026, 8, 1, 8));
      await saveDraft('new', client: 'Newer', at: DateTime(2026, 8, 1, 11));

      expect((await repo.latestDraft())!.clientName, 'Newer');
    });

    test('no draft on a clean device', () async {
      expect(await repo.latestDraft(), isNull);
    });
  });

  group('what survives', () {
    test('every egg and its readings come back', () async {
      await saveDraft('draft-1', eggs: 5);

      final samples = await repo.samplesFor('draft-1');

      expect(samples.length, 5);
      expect(samples.map((s) => s.massG), [51.0, 52.0, 53.0, 54.0, 55.0]);
    });

    test('photographs taken before the interruption survive', () async {
      // Photos are written as they are taken rather than at save, so a process
      // death on the very next screen cannot lose them.
      await saveDraft('draft-1');
      await repo.addPhotoReturningId(
        EggPhotosCompanion.insert(
          inspectionUuid: 'draft-1',
          kind: 'label',
          filePath: '/data/photos/label.jpg',
          capturedAt: DateTime(2026, 8, 1, 9, 5),
        ),
      );

      final photos = await repo.photosFor('draft-1');

      expect(photos.length, 1);
      expect(photos.single.kind, 'label');
    });

    test('resuming writes back to the same record, not a second one',
        () async {
      await saveDraft('draft-1', eggs: 2);
      // Continuing the same uuid, now finished.
      await repo.saveInspection(
        EggInspectionsCompanion.insert(
          clientUuid: 'draft-1',
          inspectedAt: DateTime(2026, 8, 1, 9),
          updatedAt: DateTime(2026, 8, 1, 10),
          status: const Value('completed'),
          clientName: const Value('Sunrise Poultry Farm'),
        ),
        [
          for (var i = 1; i <= 8; i++)
            EggSamplesCompanion.insert(
              inspectionUuid: 'draft-1',
              eggNumber: i,
              massG: Value(50.0 + i),
            ),
        ],
      );

      expect((await repo.savedInspections()).length, 1);
      expect((await repo.samplesFor('draft-1')).length, 8);
      expect(await repo.latestDraft(), isNull);
    });
  });

  group('a draft is never sent to the server', () {
    test('upload skips anything not completed', () async {
      var posted = 0;
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          if (request.method == 'POST') posted++;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );
      await db.writeSyncState('auth.accessToken', 'token');
      final at = DateTime(2026, 8, 1, 9);
      await repo.saveInspection(
        EggInspectionsCompanion.insert(
          clientUuid: 'draft-1',
          inspectedAt: at,
          updatedAt: at,
          status: const Value('draft'),
        ),
        const [],
      );

      // Half an inspection must never reach the server as though it were a
      // finished one; the sync service filters on status.
      final pending = (await repo.savedInspections())
          .where((i) => !i.isUploaded && i.status == 'completed');

      expect(pending, isEmpty);
      expect(posted, 0);
    });
  });

  group('discarding', () {
    test('removes the record, its eggs and its photo rows', () async {
      await saveDraft('draft-1', eggs: 4);
      await repo.addPhotoReturningId(
        EggPhotosCompanion.insert(
          inspectionUuid: 'draft-1',
          kind: 'label',
          filePath: '/data/photos/label.jpg',
          capturedAt: DateTime(2026, 8, 1, 9),
        ),
      );

      await repo.deleteInspection('draft-1');

      expect(await repo.inspectionByUuid('draft-1'), isNull);
      expect(await repo.samplesFor('draft-1'), isEmpty);
      expect(await repo.photosFor('draft-1'), isEmpty);
      expect(await repo.latestDraft(), isNull);
    });

    test('leaves other records alone', () async {
      await saveDraft('draft-1');
      final at = DateTime(2026, 8, 1, 9);
      await repo.saveInspection(
        EggInspectionsCompanion.insert(
          clientUuid: 'keep-me',
          inspectedAt: at,
          updatedAt: at,
          status: const Value('completed'),
        ),
        const [],
      );

      await repo.deleteInspection('draft-1');

      expect(await repo.inspectionByUuid('keep-me'), isNotNull);
    });
  });

  test('removing one photograph leaves the others', () async {
    await saveDraft('draft-1');
    final first = await repo.addPhotoReturningId(
      EggPhotosCompanion.insert(
        inspectionUuid: 'draft-1',
        kind: 'label',
        filePath: '/data/photos/a.jpg',
        capturedAt: DateTime(2026, 8, 1, 9),
      ),
    );
    await repo.addPhotoReturningId(
      EggPhotosCompanion.insert(
        inspectionUuid: 'draft-1',
        kind: 'egg',
        filePath: '/data/photos/b.jpg',
        capturedAt: DateTime(2026, 8, 1, 9),
      ),
    );

    await repo.deletePhoto(first);

    final left = await repo.photosFor('draft-1');
    expect(left.length, 1);
    expect(left.single.kind, 'egg');
  });
}
