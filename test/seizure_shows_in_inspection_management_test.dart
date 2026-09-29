import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/seizures/data/seizure_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/inspection_management_pages.dart';

/// A seizure shows in Inspection Management (Ethan, 2026-09-29): on the
/// visit's card in the list, at the top of the grouped inspection, on the
/// member that was seized, and on that record's own page with what the
/// Annexure E sheet carries.
Future<void> settle(WidgetTester tester) async {
  // The pages read the database as they open; give those reads real time
  // to land between frames, since fake time alone does not run them.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() async {
    store = Directory.systemTemp.createTempSync('fsa_seizure_im_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime.now().subtract(const Duration(hours: 2));
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Checkers Blueberry Square'),
          completedAt: Value(when),
          isUploaded: const Value(true),
        ));
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: const Value('visit-1'),
          status: const Value('completed'),
          isUploaded: const Value(true),
          facilityName: const Value('Checkers Blueberry Square'),
        ));
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  Future<void> seize() => SeizureRepository(database: db).record(
        SeizuresCompanion.insert(
          clientUuid: 'seizure-1',
          recordUuid: 'pmp-1',
          recordKind: 'pmp',
          visitUuid: const Value('visit-1'),
          issuedAt: DateTime(2026, 9, 7, 13, 52),
          updatedAt: DateTime(2026, 9, 7, 13, 52),
          clientName: const Value('Checkers Blueberry Square'),
          productName: const Value('Venison Boerewors'),
          quantity: const Value('5 packs (2.106 kg)'),
          receiverName: const Value('Manel'),
          receiverIdNumber: const Value('0747676100'),
          receiverDesignation: const Value('Butchery Manager'),
        ),
      );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final visits = VisitRepository(db);
    await tester.pumpWidget(MaterialApp(
      home: InspectionManagementPage(
        visits: visits,
        eggs: EggsRepository(database: db, baseUrl: ''),
        invoices: InvoiceRepository(db, visits),
        database: db,
      ),
    ));
    await settle(tester);
  }

  testWidgets('a visit with no seizure says nothing of one', (tester) async {
    await open(tester);
    expect(find.text('Checkers Blueberry Square'), findsOneWidget);
    expect(find.text('Seizure served'), findsNothing);
  });

  testWidgets('a seizure shows on the card, the visit, the member and the '
      'record', (tester) async {
    await seize();
    await open(tester);
    expect(find.text('Seizure served'), findsOneWidget);

    await tester.tap(find.text('Checkers Blueberry Square'));
    await settle(tester);
    expect(find.textContaining('A consignment was seized on this visit'),
        findsOneWidget);
    expect(find.text('SEIZURE SERVED'), findsOneWidget);

    await tester.tap(find.text('SEIZURE SERVED'));
    await settle(tester);
    // The record's own page, where section titles are set in capitals.
    expect(find.text('SEIZURE SERVED'), findsOneWidget);
    expect(find.text('Quantity seized'), findsOneWidget);
    expect(find.text('5 packs (2.106 kg)'), findsOneWidget);
    expect(find.text('Manel'), findsOneWidget);
    expect(find.text('Butchery Manager'), findsOneWidget);
  });

  test('purging the visit takes its seizure with it', () async {
    await seize();
    // A visit is only purged once it has been up long enough.
    await db.writeSyncState('visits.uploadedAt.visit-1',
        DateTime.now().toUtc().subtract(const Duration(days: 60)).toIso8601String());
    final visits = VisitRepository(db);
    expect(await visits.purgeUploadedVisits(retention: Duration.zero), 1);
    expect(await db.select(db.seizures).get(), isEmpty);
  });
}
