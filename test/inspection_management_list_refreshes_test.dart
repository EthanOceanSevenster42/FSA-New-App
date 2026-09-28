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

/// Inspection Management's list reads its cards again when the visit page
/// closes. It used to draw them from the rows read when it opened, so an
/// approval taken back on the visit page kept showing as given until the
/// list was left and reopened (Ethan, 2026-09-26).
/// Pumps a bounded stretch of frames. Something on these pages keeps
/// animating, so waiting for the tree to go still never returns.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() async {
    // The list's tidy-up of old uploaded visits looks in the photo store,
    // which has no platform under `flutter test`.
    store = Directory.systemTemp.createTempSync('fsa_im_store_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime.now().subtract(const Duration(hours: 2));
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('QUID test'),
          completedAt: Value(when),
          isUploaded: const Value(true),
          approvedAt: Value(when),
          approvalSent: const Value(true),
        ));
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  testWidgets('an approval taken back on the visit page is gone from the '
      'card when the list comes back', (tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
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
    expect(find.text('Approved'), findsOneWidget);

    await tester.tap(find.text('QUID test'));
    await settle(tester);
    await tester.ensureVisible(find.text('UNAPPROVE'));
    await tester.tap(find.text('UNAPPROVE'));
    await settle(tester);
    await tester.tap(find.text('Unapprove'));
    await settle(tester);
    expect((await db.select(db.storeVisits).get()).single.approvedAt, isNull);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('Not approved'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });
}
