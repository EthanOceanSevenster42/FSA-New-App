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

/// An occurrence report is corrected the same way an inspection is
/// (Ethan, 2026-10-20).
///
/// Inspection Management skipped its whole edit block for an occurrence
/// report with nothing else captured under it, so a wrong time of visit or
/// a typo in the description of events could not be put right at all — the
/// inspector had to delete the report and capture it again. The visit
/// screen already knew how to show the occurrence's own fields in
/// details-only mode; there was simply no way in.
void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() async {
    store = Directory.systemTemp.createTempSync('fsa_occ_edit_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime.now().subtract(const Duration(hours: 2));
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'occ-edit',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Red Cap Hyper'),
          completedAt: Value(when),
          isUploaded: const Value(true),
          isOccurrenceReport: const Value(true),
          occurrenceTimeOfVisit: const Value('09:15'),
          occurrenceRegistrationCode: const Value('REG-1'),
          occurrenceDescription: const Value('Entry refused at the gate.'),
        ));
    // A plain inspection visit, to prove the usual wording is untouched.
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'plain-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Blue Door Butchery'),
          completedAt: Value(when),
          isUploaded: const Value(true),
        ));
  });

  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> openVisit(WidgetTester tester, String facility) async {
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
        inspectorName: 'ethan',
      ),
    ));
    await settle(tester);
    await tester.tap(find.text(facility));
    await settle(tester);
  }

  testWidgets('an occurrence report on its own can be edited', (tester) async {
    await openVisit(tester, 'Red Cap Hyper');
    expect(find.text('EDIT OCCURRENCE REPORT'), findsOneWidget);
    // Named for what it is. The inspection wording stays off this page.
    expect(find.text('EDIT VISIT DETAILS'), findsNothing);
  });

  testWidgets('it opens the report with its own fields filled in',
      (tester) async {
    await openVisit(tester, 'Red Cap Hyper');
    await tester.tap(find.text('EDIT OCCURRENCE REPORT'));
    await settle(tester);

    // The occurrence block, and the record as it stands.
    expect(find.text('OCCURRENCE REPORT'), findsOneWidget);
    expect(find.text('Entry refused at the gate.'), findsOneWidget);
    // Editable, not the read-only view a signed-off visit otherwise gets.
    final field = find.widgetWithText(TextField, 'Entry refused at the gate.');
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).enabled, isNot(false));
    // Details-only: the visit is being corrected, not re-planned.
    expect(find.text('Is this an occurrence report?'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a correction is saved and queued to go up again',
      (tester) async {
    await openVisit(tester, 'Red Cap Hyper');
    await tester.tap(find.text('EDIT OCCURRENCE REPORT'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Entry refused at the gate.'),
        'Entry refused by the manager, who asked us to return Monday.');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    var saved = await (db.select(db.storeVisits)
          ..where((t) => t.uuid.equals('occ-edit')))
        .getSingle();
    expect(saved.occurrenceDescription,
        'Entry refused by the manager, who asked us to return Monday.');
    // The rest of the report is left alone.
    expect(saved.occurrenceTimeOfVisit, '09:15');
    expect(saved.occurrenceRegistrationCode, 'REG-1');

    // Saving is itself enough to put the visit back in front of the sync —
    // the office gets the corrected Occurrence Document rather than keeping
    // the first one. It does not wait for the inspector to navigate back,
    // so a correction cannot be stranded by closing the screen another way.
    expect(saved.isUploaded, isFalse, reason: 'queued to be sent again');
    await tester.pageBack();
    await settle(tester);
    saved = await (db.select(db.storeVisits)
          ..where((t) => t.uuid.equals('occ-edit')))
        .getSingle();
    expect(saved.isUploaded, isFalse, reason: 'and still queued on the way out');
  });

  testWidgets('a plain visit still says EDIT VISIT DETAILS', (tester) async {
    await openVisit(tester, 'Blue Door Butchery');
    expect(find.text('EDIT VISIT DETAILS'), findsOneWidget);
    expect(find.text('EDIT OCCURRENCE REPORT'), findsNothing);
  });
}
