import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

/// One handset, several inspectors: each sees only their own work.
///
/// Field devices get shared. Before inspections carried an owner, every list on
/// the device showed every inspection on it — and worse, work captured by one
/// inspector but still unsent when another signed in was uploaded under the
/// second one's token, so the server recorded it against the wrong person
/// permanently. In a food-safety record that is misattributed evidence.
void main() {
  late LocalDatabase db;
  late EggsRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(baseUrl: 'http://example.test', database: db);
  });
  tearDown(() async => db.close());

  /// Sign in as [name], or sign out entirely when null.
  Future<void> signedInAs(String? name) =>
      db.writeSyncState(EggsRepository.sessionUserKey, name ?? '');

  Future<void> inspection(
    String uuid, {
    String status = 'completed',
    bool uploaded = false,
  }) =>
      repo.saveInspection(
        EggInspectionsCompanion.insert(
          clientUuid: uuid,
          inspectedAt: DateTime(2026, 8, 3, 9),
          updatedAt: DateTime(2026, 8, 3, 9),
          status: Value(status),
          isUploaded: Value(uploaded),
          clientName: Value('Client $uuid'),
        ),
        const [],
      );

  Future<void> direction(String uuid, {String status = 'completed'}) =>
      repo.saveDirection(
        EggDirectionsCompanion.insert(
          clientUuid: uuid,
          issuedAt: DateTime(2026, 8, 3, 10),
          updatedAt: DateTime(2026, 8, 3, 10),
          status: Value(status),
          clientName: Value('Client $uuid'),
        ),
      );

  test('an inspection is stamped with whoever captured it', () async {
    await signedInAs('Ethan');
    await inspection('a');

    final row = await repo.inspectionByUuid('a');
    expect(row!.inspectorUsername, 'Ethan');
  });

  test('two inspectors on one handset do not see each other', () async {
    await signedInAs('Ethan');
    await inspection('ethan-1');
    await inspection('ethan-2');

    await signedInAs('Armand');
    await inspection('armand-1');

    expect(
      (await repo.savedInspections()).map((i) => i.clientUuid),
      ['armand-1'],
      reason: 'Armand is signed in, so only Armand\'s work is listed',
    );

    await signedInAs('Ethan');
    expect(
      (await repo.savedInspections()).map((i) => i.clientUuid).toSet(),
      {'ethan-1', 'ethan-2'},
    );
  });

  test('directions are private too', () async {
    await signedInAs('Ethan');
    await direction('ethan-d');

    await signedInAs('Armand');
    await direction('armand-d');

    expect((await repo.savedDirections()).map((d) => d.clientUuid), ['armand-d']);

    await signedInAs('Ethan');
    expect((await repo.savedDirections()).map((d) => d.clientUuid), ['ethan-d']);
  });

  test('unfinished work is offered back only to its own author', () async {
    await signedInAs('Ethan');
    await inspection('ethan-draft', status: 'draft');
    await direction('ethan-draft-d', status: 'draft');

    await signedInAs('Armand');
    expect(await repo.drafts(), isEmpty);
    expect(await repo.latestDraft(), isNull);
    expect(await repo.directionDrafts(), isEmpty);

    await signedInAs('Ethan');
    expect((await repo.drafts()).single.clientUuid, 'ethan-draft');
    expect((await repo.latestDraft())!.clientUuid, 'ethan-draft');
    expect((await repo.directionDrafts()).single.clientUuid, 'ethan-draft-d');
  });

  test('discarding drafts cannot reach another inspector\'s work', () async {
    await signedInAs('Ethan');
    await inspection('ethan-draft', status: 'draft');

    await signedInAs('Armand');
    expect(await repo.deleteAllDrafts(), 0, reason: 'nothing of Armand\'s');

    await signedInAs('Ethan');
    expect(
      (await repo.drafts()).single.clientUuid,
      'ethan-draft',
      reason: 'Armand pressing Discard must not destroy Ethan\'s capture',
    );
  });

  /// The bug this whole change exists to prevent.
  ///
  /// The uploader enumerates through [EggsRepository.savedInspections], so
  /// scoping that list is what keeps one inspector's unsent work from being
  /// sent under another's token — and recorded against them on the server.
  test('unsent work is never uploaded under the next signed-in account',
      () async {
    await signedInAs('Ethan');
    await inspection('ethan-unsent');
    await direction('ethan-unsent-d');

    await signedInAs('Armand');
    expect(
      await repo.savedInspections(),
      isEmpty,
      reason: 'the uploader iterates this list; Ethan\'s work must not be in it',
    );
    expect(await repo.savedDirections(), isEmpty);
    expect(await repo.pendingUploadCount(), 0);
    expect(await repo.pendingDirectionCount(), 0);
  });

  test('pending counts follow the signed-in inspector', () async {
    await signedInAs('Ethan');
    await inspection('e1');
    await inspection('e2', uploaded: true);
    await direction('ed1');

    await signedInAs('Armand');
    await inspection('a1');

    expect(await repo.pendingUploadCount(), 1);
    expect(await repo.pendingDirectionCount(), 0);

    await signedInAs('Ethan');
    expect(await repo.pendingUploadCount(), 1, reason: 'e1 only; e2 is sent');
    expect(await repo.pendingDirectionCount(), 1);
  });

  test('with nobody signed in, nothing is listed', () async {
    await signedInAs('Ethan');
    await inspection('a');
    await direction('d');

    await signedInAs(null);
    expect(await repo.currentInspector(), isNull);
    expect(await repo.savedInspections(), isEmpty);
    expect(await repo.savedDirections(), isEmpty);
    expect(await repo.drafts(), isEmpty);
    // Unowned rows are excluded rather than shown to all. Treating a missing
    // owner as a wildcard would reopen the leak precisely where ownership is
    // unknown.
    expect(await repo.pendingUploadCount(), 0);
  });

  test('the home dashboard counts only the reader\'s own work', () async {
    final today = DateTime.now();

    Future<void> completedToday(String uuid, {bool uploaded = false}) =>
        repo.saveInspection(
          EggInspectionsCompanion.insert(
            clientUuid: uuid,
            inspectedAt: today,
            updatedAt: today,
            status: const Value('completed'),
            isUploaded: Value(uploaded),
          ),
          const [],
        );

    await signedInAs('Ethan');
    await completedToday('e1');
    await completedToday('e2');

    await signedInAs('Armand');
    await completedToday('a1');

    final armand = await HomeSummary.load(db);
    expect(armand.inspectionsToday, 1);
    expect(armand.pendingUpload, 1,
        reason: 'a queue this account cannot send must not be shown to it');

    await signedInAs('Ethan');
    final ethan = await HomeSummary.load(db);
    expect(ethan.inspectionsToday, 2);
    expect(ethan.pendingUpload, 2);

    await signedInAs(null);
    final nobody = await HomeSummary.load(db);
    expect(nobody.inspectionsToday, 0);
    expect(nobody.pendingUpload, 0);
  });

  group('the v8 back-fill', () {
    /// Work captured before ownership existed. Written with raw SQL because
    /// the repository now always stamps an owner, which is exactly what an
    /// upgrading database has not had done to it.
    Future<void> ownerlessInspection(String uuid) => db.customStatement(
          "INSERT INTO egg_inspections "
          "(client_uuid, status, inspected_at, updated_at, is_uploaded) "
          "VALUES ('$uuid', 'completed', 0, 0, 0)",
        );

    Future<void> runBackfill() async {
      for (final statement in LocalDatabase.ownerBackfillStatements) {
        await db.customStatement(statement);
      }
    }

    test('adopts existing work to the inspector using the handset', () async {
      await ownerlessInspection('older');
      await signedInAs('Ethan');
      await runBackfill();

      expect((await repo.inspectionByUuid('older'))!.inspectorUsername, 'Ethan');
      expect((await repo.savedInspections()).map((i) => i.clientUuid), ['older']);
    });

    test('a cleared session leaves work unowned rather than owned by ""',
        () async {
      await ownerlessInspection('older');
      await signedInAs(null); // stores '', as sign-out does
      await runBackfill();

      final row = await repo.inspectionByUuid('older');
      expect(row!.inspectorUsername, isNull,
          reason: '"" would read as a real username and match nobody safely');
    });

    test('does not disturb work that already has an owner', () async {
      await signedInAs('Ethan');
      await inspection('ethans');

      await signedInAs('Armand');
      await runBackfill();

      expect((await repo.inspectionByUuid('ethans'))!.inspectorUsername, 'Ethan',
          reason: 'a later upgrade must not reassign what is already owned');
    });
  });

  test('usernames are matched exactly, not by prefix', () async {
    // Armand and Armand1 are the same person's inspector and administrator
    // accounts. They must still be separate owners.
    await signedInAs('Armand');
    await inspection('by-armand');

    await signedInAs('Armand1');
    await inspection('by-armand1');

    expect((await repo.savedInspections()).map((i) => i.clientUuid),
        ['by-armand1']);

    await signedInAs('Armand');
    expect((await repo.savedInspections()).map((i) => i.clientUuid),
        ['by-armand']);
  });
}
