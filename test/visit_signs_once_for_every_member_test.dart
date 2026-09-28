import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// One signature per visit, applied to every record in it.
///
/// A grouped inspection is signed once at the end — the manager and the
/// inspector sign a single pair of pads and those signatures are stamped onto
/// every member. A member that signs itself, or that finishes before the
/// group has signed at all, puts a record on file nobody signed for.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;
  late Directory scratch;
  final when = DateTime(2026, 9, 1, 9, 30);
  const visitUuid = 'visit-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
    scratch = await Directory.systemTemp.createTemp('fsa-signatures');
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
        ));
  });
  tearDown(() async {
    await db.close();
    if (scratch.existsSync()) await scratch.delete(recursive: true);
  });

  Future<String> pad(String name) async {
    final file = File('${scratch.path}/$name.png');
    await file.writeAsBytes(const [0x89, 0x50, 0x4E, 0x47]);
    return file.path;
  }

  /// A QUID determination waiting on the group's sign-off.
  Future<void> seedQuid({String status = 'ready'}) =>
      db.into(db.poultryQuidInspections).insert(
            PoultryQuidInspectionsCompanion.insert(
              clientUuid: 'quid-1',
              inspectedAt: when,
              updatedAt: when,
              inspectorUsername: const Value('ethan'),
              visitUuid: const Value(visitUuid),
              status: Value(status),
              facilityName: const Value('Rainbow Chickens - Hammarsdale'),
            ),
          );

  Future<void> signOff({bool clientSigns = true}) async => visits.complete(
        visitUuid: visitUuid,
        managerSignaturePath: clientSigns ? await pad('manager') : '',
        managerName: 'T. Dlamini',
        inspectorSignaturePath: await pad('inspector'),
        inspectorName: 'CINGA NGONGO',
      );

  test('the visit signature is stamped onto the QUID record', () async {
    await seedQuid();
    await signOff();

    final signatures = await (db.select(db.poultrySignatures)
          ..where((t) => t.recordUuid.equals('quid-1')))
        .get();
    final roles = {for (final s in signatures) s.role: s};
    expect(roles.keys, containsAll(['client', 'inspector']));
    expect(roles['inspector']!.signedName, 'CINGA NGONGO');
    expect(roles['client']!.signedName, 'T. Dlamini');
    // Its own copy of the pad, so a deleted record cannot take another
    // member's signature file with it.
    expect(File(roles['inspector']!.filePath).existsSync(), isTrue);
  });

  test('the QUID record is only completed by that sign-off', () async {
    await seedQuid();
    // Before: waiting, as every other member waits.
    expect((await db.select(db.poultryQuidInspections).get()).single.status,
        'ready');

    await signOff();

    expect((await db.select(db.poultryQuidInspections).get()).single.status,
        'completed');
  });

  test('a refused client signature is recorded on the QUID record too',
      () async {
    await seedQuid();
    await signOff(clientSigns: false);

    final row = (await db.select(db.poultryQuidInspections).get()).single;
    expect(row.noClientSignaturePresent, isTrue);
    final signatures = await (db.select(db.poultrySignatures)
          ..where((t) => t.recordUuid.equals('quid-1')))
        .get();
    expect(signatures.any((s) => s.role == 'no_client' && s.declined), isTrue);
    expect(signatures.any((s) => s.role == 'client'), isFalse);
  });
}
