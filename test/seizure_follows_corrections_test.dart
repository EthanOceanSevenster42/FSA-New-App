import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/features/seizures/data/seizure_repository.dart';
import 'package:fsa_app/features/visits/presentation/commodity_inspection_view.dart';

/// A corrected visit prints its corrected details on the seizure sheet,
/// and the seizure's own particulars can be corrected on the record
/// (Ethan, 2026-09-29).
Future<void> settle(WidgetTester tester) async {
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
    store = Directory.systemTemp.createTempSync('fsa_seizure_fix_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
    final when = DateTime(2026, 9, 29, 8);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Checkers Blueberry'),
          facilityAddress: const Value('Old address'),
          facilityType: const Value('Butchery'),
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
          facilityName: const Value('Checkers Blueberry'),
        ));
    await SeizureRepository(database: db).record(SeizuresCompanion.insert(
          clientUuid: 'seizure-1',
          recordUuid: 'pmp-1',
          recordKind: 'pmp',
          visitUuid: const Value('visit-1'),
          issuedAt: when,
          updatedAt: when,
          clientName: const Value('Checkers Blueberry'),
          clientAddress: const Value('Old address'),
          productName: const Value('Venison Boerewors'),
          quantity: const Value('5 packs'),
          receiverName: const Value('Manel'),
          isUploaded: const Value(true),
        ));
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  test('the seizure reads the visit as it is now', () async {
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals('visit-1')))
        .write(const StoreVisitsCompanion(
      facilityName: Value('Checkers Blueberry Square'),
      facilityAddress: Value('Cnr Beyers Naude & Blueberry St, Roodepoort'),
    ));
    final s =
        await SeizureRepository(database: db).currentForRecord('pmp-1');
    expect(s!.clientName, 'Checkers Blueberry Square');
    expect(s.clientAddress, 'Cnr Beyers Naude & Blueberry St, Roodepoort');
    expect(s.inspectionPoint, 'Butchery');
    // What was seized stays the seizure's own.
    expect(s.quantity, '5 packs');
  });

  testWidgets('the particulars are corrected on the record and the visit '
      'goes again', (tester) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CommodityInspectionViewPage(
        database: db,
        kind: 'pmp',
        uuid: 'pmp-1',
        title: 'Processed Meat Product inspection 1',
        uploaded: true,
        status: 'completed',
        onEdit: () async => false,
      ),
    ));
    await settle(tester);
    await tester.ensureVisible(find.text('EDIT SEIZURE PARTICULARS'));
    await tester.tap(find.text('EDIT SEIZURE PARTICULARS'));
    await settle(tester);
    expect(find.text('Edit seizure particulars'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('seizure-quantity')), '6 packs (2.4 kg)');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final s = (await db.select(db.seizures).get()).single;
    expect(s.quantity, '6 packs (2.4 kg)');
    expect(s.isUploaded, isFalse);
    expect((await db.select(db.storeVisits).get()).single.isUploaded, isFalse);
    expect(find.text('6 packs (2.4 kg)'), findsOneWidget);
  });

  testWidgets('a record that cannot be edited offers no seizure edit',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CommodityInspectionViewPage(
        database: db,
        kind: 'pmp',
        uuid: 'pmp-1',
        title: 'Processed Meat Product inspection 1',
        uploaded: true,
        status: 'completed',
      ),
    ));
    await settle(tester);
    expect(find.text('SEIZURE SERVED'), findsOneWidget);
    expect(find.text('EDIT SEIZURE PARTICULARS'), findsNothing);
  });

  test('an egg seizure fills from the inspection at the end', () async {
    // Nothing typed on the seizure: no particulars pop-up any more.
    final when = DateTime(2026, 9, 29, 9);
    await db.into(db.eggSizes).insert(
        EggSizesCompanion.insert(id: const Value(9), name: 'Large', minMassG: 51));
    await db.into(db.eggGrades).insert(
        EggGradesCompanion.insert(id: const Value(4), name: 'Grade 1', rank: 1));
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: const Value('visit-1'),
          declaredSizeId: const Value(9),
          declaredGradeId: const Value(4),
        ));
    await db.into(db.eggDirections).insert(EggDirectionsCompanion.insert(
          clientUuid: 'dir-1',
          inspectionUuid: const Value('egg-1'),
          issuedAt: when,
          updatedAt: when,
          quantityRemoved: const Value(24),
        ));
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals('visit-1')))
        .write(const StoreVisitsCompanion(managerName: Value('T. Dlamini')));
    await SeizureRepository(database: db).record(SeizuresCompanion.insert(
          clientUuid: 'seizure-egg',
          recordUuid: 'egg-1',
          recordKind: 'egg',
          visitUuid: const Value('visit-1'),
          issuedAt: when,
          updatedAt: when,
          productName: const Value('Eggs'),
        ));

    final sheet =
        await SeizureRepository(database: db).currentForRecord('egg-1');
    expect(sheet!.quantity, '24');
    expect(sheet.productClass, 'Size: Large, Grade: Grade 1');
    expect(sheet.receiverName, 'T. Dlamini');
    expect(sheet.receiverDesignation, 'Manager');
  });

  test('particulars the inspector typed stand over the inspection', () async {
    // seizure-1 was given its own quantity and receiver.
    final sheet =
        await SeizureRepository(database: db).currentForRecord('pmp-1');
    expect(sheet!.quantity, '5 packs');
    expect(sheet.receiverName, 'Manel');
  });
}
