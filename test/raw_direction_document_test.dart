import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_assets_bundle.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/record_documents.dart';


/// The notice the client is handed.
///
/// The direction record was being raised and sent, but nothing ever drew the
/// sheet: the data went to the office and the person it was served on had
/// nothing in their hand.
void main() {
  late LocalDatabase db;
  late RawRmpRepository repo;
  final when = DateTime(2026, 9, 22, 10, 30);

  TestWidgetsFlutterBinding.ensureInitialized();
  // The document layer needs the font and logo loader the handset
  // installs at start-up.
  installFsaFormAssets();
  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    final raw =
        await File('assets/reference/rawrmp_reference.json').readAsString();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-1',
            inspectedAt: when,
            updatedAt: when,
            inspectorUsername: const Value('ethan'),
            facilityName: const Value('Kroon Foods'),
            facilityAddress: const Value('12 Bridge Road, Pinetown'),
            contactPerson: const Value('T. Dlamini'),
            contactPersonEmail: const Value('quality@kroon.co.za'),
            producerName: const Value('Kroon Meats'),
            productItem: const Value('Boerewors'),
            batchNumber: const Value('KM-2291'),
            markingLabelsPresent: const Value(true),
            // Nothing ticked in a present section, so every marking row is
            // a deviation and the notice has something to cite.
            compliantItemIds: const Value(''),
            correctByDate: Value(DateTime(2026, 10, 6)),
          ),
        );
  });
  tearDown(() async => db.close());

  Future<void> raiseDirection() =>
      repo.saveDirection(RawRmpDirectionsCompanion.insert(
        clientUuid: 'dir-1',
        issuedAt: when,
        updatedAt: when,
        inspectorUsername: const Value('ethan'),
        sourceInspectionUuid: const Value('raw-1'),
        referenceNumber: const Value('Kroon Foods/37/22/09/2026/01'),
        correctByDate: Value(DateTime(2026, 10, 6)),
        remarks: const Value('Product name absent from the marking label.'),
        facilityName: const Value('Kroon Foods'),
      ));

  test('an inspection with no direction produces no notice', () async {
    expect(await repo.buildDirection('raw-1'), isNull);
  });

  test('the notice is drawn from the record that raised it', () async {
    await raiseDirection();
    final file = await repo.buildDirection('raw-1');

    expect(file, isNotNull);
    expect(await file!.length(), greaterThan(1000));
    await file.delete();
  });

  test('the record offers it alongside the checklists', () async {
    await raiseDirection();
    final offered = await documentsForRecord(db, 'rawrmp', 'raw-1');

    expect(offered.map((d) => d.title), contains('Rejection'));
  });

  test('it is not offered when nothing was directed', () async {
    final offered = await documentsForRecord(db, 'rawrmp', 'raw-1');
    expect(offered.map((d) => d.title), isNot(contains('Rejection')));
  });
}
