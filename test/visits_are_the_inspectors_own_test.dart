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

/// A handset is shared: whoever is signed in sees their own visits and
/// nobody else's (Ethan, 2026-10-02). Ben, signed in on Ethan's tablet, was
/// shown one of Ethan's visits and tried to retract its approval, which the
/// server refused — and the retraction letter never went.
void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() async {
    store = Directory.systemTemp.createTempSync('fsa_own_store_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime.now().subtract(const Duration(hours: 2));
    for (final (uuid, who, shop) in [
      ('v-ethan', 'ethan', 'Shoprite Polokwane'),
      ('v-ben', 'Ben', 'Alzu Eggs'),
    ]) {
      await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: uuid,
            inspectorUsername: Value(who),
            startedAt: when,
            facilityName: Value(shop),
            completedAt: Value(when),
            isUploaded: const Value(true),
          ));
    }
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'open-ben',
          inspectorUsername: const Value('Ben'),
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
        ));
  });

  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  test('the lists are the signed-in inspector\'s own, whatever the case',
      () async {
    final visits = VisitRepository(db);
    expect((await visits.allVisits(owner: 'ben')).map((v) => v.facilityName),
        unorderedEquals(['Kroon Foods', 'Alzu Eggs']));
    expect((await visits.allVisits(owner: 'ethan')).map((v) => v.facilityName),
        ['Shoprite Polokwane']);
    expect(await visits.openVisits(owner: 'Ethan'), isEmpty);
    expect((await visits.openVisits(owner: 'ben')).single.facilityName,
        'Kroon Foods');
    // No owner asked for: everything on the device, which is what the sync
    // sends.
    expect(await visits.allVisits(), hasLength(3));
  });

  testWidgets("Inspection Management lists only the signed-in inspector's",
      (tester) async {
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
        inspectorName: 'Ben',
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.textContaining('Alzu Eggs'), findsOneWidget);
    expect(find.textContaining('Shoprite Polokwane'), findsNothing);
  });
}
