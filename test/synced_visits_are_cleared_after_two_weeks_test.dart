import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// A signed-off visit the server has — every record, photograph and
/// signature confirmed — is cleared off the handset two weeks after it went
/// up, image files included (Ethan, 2026-10-23; five days until then).
/// Every commodity, and an occurrence report with nothing else under it.
/// Anything the server does not have yet, or that went up less than two
/// weeks ago, stays.
void main() {
  late LocalDatabase db;
  late Directory store;
  final when = DateTime.now().subtract(const Duration(days: 7));

  setUp(() {
    store = Directory.systemTemp.createTempSync('fsa_tidy_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  File image(String name) =>
      File('${store.path}/$name.jpg')..writeAsBytesSync(List.filled(8, 1));

  Future<void> uploadedAgo(String visit, int days) =>
      db.writeSyncState('visits.uploadedAt.$visit',
          DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String());

  Future<void> visit(String uuid, {bool occurrence = false}) =>
      db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: uuid,
            inspectorUsername: const Value('ethan'),
            startedAt: when,
            facilityName: Value('Store $uuid'),
            completedAt: Value(when),
            isUploaded: const Value(true),
            isOccurrenceReport: Value(occurrence),
          ));

  /// One record of every commodity under [v], each with a photograph.
  Future<List<File>> allCommodities(String v, {bool photosUp = true}) async {
    final files = <File>[];
    Future<void> poultryPhoto(String record, String kind) async {
      final f = image('$record-photo');
      files.add(f);
      await db.into(db.poultryPhotos).insert(PoultryPhotosCompanion.insert(
            recordUuid: record,
            kind: kind,
            filePath: f.path,
            capturedAt: when,
            isUploaded: Value(photosUp),
          ));
    }

    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: '$v-egg',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    final eggShot = image('$v-egg-photo');
    files.add(eggShot);
    await db.into(db.eggPhotos).insert(EggPhotosCompanion.insert(
          inspectionUuid: '$v-egg',
          kind: 'label',
          filePath: eggShot.path,
          capturedAt: when,
          isUploaded: Value(photosUp),
        ));
    await db.into(db.poultryInspections).insert(PoultryInspectionsCompanion.insert(
          clientUuid: '$v-poultry',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    await poultryPhoto('$v-poultry', 'grading');
    await db.into(db.poultryLabelInspections).insert(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: '$v-label',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    await poultryPhoto('$v-label', 'label');
    await db.into(db.poultryQuidInspections).insert(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: '$v-quid',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    await poultryPhoto('$v-quid', 'quid');
    await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
          clientUuid: '$v-raw',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    await poultryPhoto('$v-raw', 'rawrmp');
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: '$v-pmp',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: Value(v),
          status: const Value('completed'),
          isUploaded: const Value(true),
        ));
    await poultryPhoto('$v-pmp', 'pmp');
    return files;
  }

  Future<int> rowsLeft(String v) async {
    var n = 0;
    n += (await (db.select(db.storeVisits)..where((t) => t.uuid.equals(v))).get()).length;
    n += (await (db.select(db.eggInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.poultryInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.poultryLabelInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.poultryQuidInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.rawRmpInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.pmpInspections)..where((t) => t.visitUuid.equals(v))).get()).length;
    n += (await (db.select(db.eggPhotos)..where((t) => t.inspectionUuid.equals('$v-egg'))).get()).length;
    n += (await db.select(db.poultryPhotos).get())
        .where((p) => p.recordUuid.startsWith('$v-'))
        .length;
    return n;
  }

  test('two weeks after it went up, a visit of every commodity goes, '
      'images and all', () async {
    await visit('old');
    final files = await allCommodities('old');
    await uploadedAgo('old', 15);
    expect(await rowsLeft('old'), 13);

    final repo = VisitRepository(db);
    expect(await repo.purgeUploadedVisits(), 1);

    expect(await rowsLeft('old'), 0);
    for (final f in files) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
  });

  test('thirteen days is too soon, and a photograph not yet up holds it '
      'back',
      () async {
    await visit('recent');
    await allCommodities('recent');
    await uploadedAgo('recent', 13);
    await visit('photo-pending');
    await allCommodities('photo-pending', photosUp: false);
    await uploadedAgo('photo-pending', 20);

    final repo = VisitRepository(db);
    expect(await repo.purgeUploadedVisits(), 0);
    expect(await rowsLeft('recent'), 13);
    expect(await rowsLeft('photo-pending'), 13);
  });

  test('an occurrence report with nothing else under it goes too, with its '
      'photographs and document', () async {
    await visit('occ', occurrence: true);
    final shot = image('occ-photo');
    final document = File('${store.path}/visit_occ_occurrence.pdf')
      ..writeAsBytesSync([37, 80, 68, 70]);
    await db.into(db.visitOccurrencePhotos).insert(
        VisitOccurrencePhotosCompanion.insert(
          visitUuid: 'occ',
          filePath: shot.path,
          capturedAt: when,
        ));
    await uploadedAgo('occ', 15);

    final repo = VisitRepository(db);
    expect(await repo.purgeUploadedVisits(), 1);
    expect(await repo.occurrencePhotos('occ'), isEmpty);
    expect(shot.existsSync(), isFalse);
    expect(document.existsSync(), isFalse);
    expect(await rowsLeft('occ'), 0);
  });

  test('the retention is two weeks', () {
    expect(VisitRepository.localRetention, const Duration(days: 14));
  });
}
