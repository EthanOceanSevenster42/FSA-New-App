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

/// Inspection Management lists the newest sign-off at the top and the
/// oldest at the bottom (Ethan, 2026-10-04). The list used to follow when
/// each visit was started, so an inspection just finished on the device
/// could sit under older ones because its visit had been opened earlier.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  late LocalDatabase db;
  late Directory store;
  final now = DateTime.now();

  setUp(() async {
    store = Directory.systemTemp.createTempSync('fsa_im_order_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    // Started first, but signed off last: the inspection just finished.
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-early-start',
          inspectorUsername: const Value('ethan'),
          startedAt: now.subtract(const Duration(days: 3)),
          facilityName: const Value('Signed off an hour ago'),
          completedAt: Value(now.subtract(const Duration(hours: 1))),
          isUploaded: const Value(true),
        ));
    // Started later, signed off yesterday.
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-late-start',
          inspectorUsername: const Value('ethan'),
          startedAt: now.subtract(const Duration(days: 1)),
          facilityName: const Value('Signed off yesterday'),
          completedAt: Value(now.subtract(const Duration(hours: 20))),
          isUploaded: const Value(true),
        ));
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  testWidgets('the most recent sign-off is the first card', (tester) async {
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
        inspectorName: 'ethan',
      ),
    ));
    await settle(tester);

    final recent = tester.getTopLeft(find.text('Signed off an hour ago'));
    final older = tester.getTopLeft(find.text('Signed off yesterday'));
    expect(recent.dy, lessThan(older.dy),
        reason: 'the newest sign-off sits above the older one, although '
            'its visit was started two days earlier');
  });
}
