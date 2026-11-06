import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';

/// An inspection must reach the server whatever name it was captured under.
///
/// Lwandile Dlamini signed in as "lwandile2" on the 23rd and as "Lwandile2"
/// on the 26th. The eggs compared the owner exactly, so four finished
/// inspections captured under the first spelling were invisible to every
/// upload pass made under the second: never sent, and — because they were
/// never in the list the uploader walks — never counted as a failure either.
/// The app reported all clear while the work sat on the handset for five
/// days (Ethan, 2026-10-28).
///
/// Two things are checked here. That the egg screens accept a different
/// spelling of the signed-in name, as the other three commodities already
/// did; and that the upload pass of every commodity ignores ownership
/// altogether, so a genuinely different name — not merely a different case —
/// can no longer strand finished work.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final when = DateTime.utc(2026, 10, 23, 9);

  Future<void> egg(String uuid, String owner) =>
      db.into(db.eggInspections).insert(
            EggInspectionsCompanion.insert(
              inspectorUsername: Value(owner),
              clientUuid: uuid,
              inspectedAt: when,
              updatedAt: when,
              status: const Value('completed'),
            ),
          );

  group('the egg screens', () {
    late EggsRepository repo;

    setUp(() async {
      repo = EggsRepository(baseUrl: 'http://example.test', database: db);
      await db.writeSyncState(EggsRepository.sessionUserKey, 'Lwandile2');
    });

    test('show work captured under another spelling of the same name',
        () async {
      await egg('captured-as-lowercase', 'lwandile2');

      final mine = await repo.savedInspections();

      expect(mine.map((i) => i.clientUuid), ['captured-as-lowercase']);
    });

    test('show work that has no owner at all', () async {
      // The v8 backfill leaves rows null where no session was stored. They
      // belong to whoever is signed in; there is no better answer.
      await egg('no-owner', '');

      final mine = await repo.savedInspections();

      expect(mine.map((i) => i.clientUuid), ['no-owner']);
    });

    test("still keep another inspector's work out of sight", () async {
      await egg('someone-elses', 'Sandisiwe');

      expect(await repo.savedInspections(), isEmpty);
    });

    test('show nothing at all when nobody is signed in', () async {
      await db.writeSyncState(EggsRepository.sessionUserKey, '');
      await egg('captured-as-lowercase', 'lwandile2');

      expect(await repo.savedInspections(), isEmpty);
    });
  });

  group('the upload pass', () {
    test('offers an egg inspection owned by a different inspector entirely',
        () async {
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
      );
      await db.writeSyncState(EggsRepository.sessionUserKey, 'Lwandile2');
      await egg('someone-elses', 'Sandisiwe');

      // Hidden from his screens, but still sent: whether finished work
      // reaches the server is not a question about who may look at it.
      expect(await repo.savedInspections(), isEmpty);
      expect(
        (await repo.inspectionsForUpload()).map((i) => i.clientUuid),
        ['someone-elses'],
      );
    });

    test('offers a raw-product inspection owned by another name', () async {
      final repo = RawRmpRepository(
        baseUrl: 'http://example.test',
        database: db,
      );
      await db.into(db.rawRmpInspections).insert(
            RawRmpInspectionsCompanion.insert(
              inspectorUsername: const Value('lwandile2'),
              clientUuid: 'raw-1',
              inspectedAt: when,
              updatedAt: when,
              status: const Value('completed'),
            ),
          );

      expect(
        (await repo.inspectionsForUpload()).map((i) => i.clientUuid),
        ['raw-1'],
      );
    });

    test('offers a processed-meat inspection owned by another name', () async {
      final repo = PmpRepository(
        baseUrl: 'http://example.test',
        database: db,
      );
      await db.into(db.pmpInspections).insert(
            PmpInspectionsCompanion.insert(
              inspectorUsername: const Value('lwandile2'),
              clientUuid: 'pmp-1',
              inspectedAt: when,
              updatedAt: when,
              status: const Value('completed'),
            ),
          );

      expect(
        (await repo.inspectionsForUpload()).map((i) => i.clientUuid),
        ['pmp-1'],
      );
    });

    test('offers a grading inspection owned by another name', () async {
      final repo = PoultryRepository(
        baseUrl: 'http://example.test',
        database: db,
      );
      await db.into(db.poultryInspections).insert(
            PoultryInspectionsCompanion.insert(
              inspectorUsername: const Value('lwandile2'),
              clientUuid: 'poultry-1',
              inspectedAt: when,
              updatedAt: when,
              status: const Value('completed'),
            ),
          );

      expect(
        (await repo.inspectionsForUpload()).map((i) => i.clientUuid),
        ['poultry-1'],
      );
    });

    test('offers a label checklist owned by another name', () async {
      final repo = PoultryCaptureRepository(
        baseUrl: 'http://example.test',
        database: db,
      );
      await db.into(db.poultryLabelInspections).insert(
            PoultryLabelInspectionsCompanion.insert(
              inspectorUsername: const Value('lwandile2'),
              clientUuid: 'label-1',
              inspectedAt: when,
              updatedAt: when,
              status: const Value('completed'),
            ),
          );

      expect(
        (await repo.labelInspectionsForUpload()).map((i) => i.clientUuid),
        ['label-1'],
      );
    });
  });
}
