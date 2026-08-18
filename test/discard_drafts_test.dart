import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// Discarding an unfinished inspection has to actually get rid of it.
///
/// A draft is written on every step change, so each abandoned attempt leaves
/// one behind. Discarding removed only the newest, and the banner came
/// straight back showing the next — which reads as the discard not working at
/// all.
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

  Future<void> draft(String uuid, DateTime at, {String status = 'draft'}) async {
    await repo.saveInspection(
      EggInspectionsCompanion.insert(
        clientUuid: uuid,
        inspectedAt: at,
        updatedAt: at,
        status: Value(status),
        clientName: Value('Client $uuid'),
      ),
      [
        EggSamplesCompanion.insert(
          inspectionUuid: uuid,
          eggNumber: 1,
          massG: const Value(52),
        ),
      ],
    );
    await repo.addPhotoReturningId(
      EggPhotosCompanion.insert(
        inspectionUuid: uuid,
        kind: 'label',
        filePath: '/photos/$uuid.jpg',
        capturedAt: at,
      ),
    );
  }

  test('every abandoned attempt is listed, newest first', () async {
    await draft('a', DateTime(2026, 8, 2, 9));
    await draft('b', DateTime(2026, 8, 2, 11));
    await draft('c', DateTime(2026, 8, 2, 10));

    final all = await repo.drafts();

    expect(all.length, 3);
    expect(all.first.clientUuid, 'b', reason: 'newest first, for Resume');
  });

  test('discarding removes all of them, not just the newest', () async {
    await draft('a', DateTime(2026, 8, 2, 9));
    await draft('b', DateTime(2026, 8, 2, 11));
    await draft('c', DateTime(2026, 8, 2, 10));

    final removed = await repo.deleteAllDrafts();

    expect(removed, 3);
    expect(await repo.drafts(), isEmpty,
        reason: 'the banner must not come back');
    expect(await repo.latestDraft(), isNull);
  });

  test('the eggs and photo rows go with them', () async {
    await draft('a', DateTime(2026, 8, 2, 9));
    await draft('b', DateTime(2026, 8, 2, 11));

    await repo.deleteAllDrafts();

    for (final uuid in ['a', 'b']) {
      expect(await repo.samplesFor(uuid), isEmpty);
      expect(await repo.photosFor(uuid), isEmpty);
    }
  });

  test('finished inspections are never touched', () async {
    await draft('half', DateTime(2026, 8, 2, 9));
    await draft('done', DateTime(2026, 8, 2, 10), status: 'completed');

    final removed = await repo.deleteAllDrafts();

    expect(removed, 1);
    expect(await repo.inspectionByUuid('done'), isNotNull,
        reason: 'completed work is not a draft and must survive');
    expect((await repo.samplesFor('done')).length, 1);
  });

  test('discarding with nothing to discard is harmless', () async {
    expect(await repo.deleteAllDrafts(), 0);
    expect(await repo.drafts(), isEmpty);
  });
}
