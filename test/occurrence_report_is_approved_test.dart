import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/inspection_management_pages.dart';

/// An occurrence report is approved like any other signed-off visit (Ethan,
/// 2026-10-02). One with nothing else captured under it used to fall
/// through both branches of the visit page and show no approval at all.
void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() async {
    store = Directory.systemTemp.createTempSync('fsa_occ_store_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime.now().subtract(const Duration(hours: 2));
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'occ-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Red Cap Hyper'),
          completedAt: Value(when),
          isUploaded: const Value(true),
          isOccurrenceReport: const Value(true),
          occurrenceDescription: const Value('Eggs on the floor.'),
        ));
  });

  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a synced occurrence report offers APPROVE and shows its state',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final visits = VisitRepository(db);
    await tester.pumpWidget(MaterialApp(
      home: InspectionManagementPage(
        visits: visits,
        eggs: EggsRepository(database: db, baseUrl: ''),
        invoices: InvoiceRepository(db, visits),
        database: db,
        inspectorName: 'ethan',
      ),
    ));
    await settle(tester);
    expect(find.text('Not approved'), findsOneWidget);

    await tester.tap(find.text('Red Cap Hyper'));
    await settle(tester);
    expect(find.text('APPROVE'), findsOneWidget);
    // What does not apply to a report with nothing else captured.
    expect(find.text('EDIT VISIT DETAILS'), findsNothing);
    expect(find.text('INSPECTIONS IN THIS GROUP'), findsNothing);
    expect(find.text('VIEW RFI'), findsNothing);
  });
}
