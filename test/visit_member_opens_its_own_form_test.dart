import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/commodity_inspection_view.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// Continuing an inspection from the visit it belongs to.
///
/// Every row under "captured so far" has to open the screen it was captured
/// on. A row that falls through to another commodity's form does not just
/// show the wrong thing: that form saves against the row's uuid, so it
/// writes one kind of record over another.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 1, 9, 30);
  const visitUuid = 'visit-1';

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
          contactPerson: const Value('T. Dlamini'),
        ));
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: visitUuid,
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture:
            PoultryCaptureRepository(database: db, baseUrl: ''),
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a QUID row opens the QUID weighing screen', (tester) async {
    await db
        .into(db.poultryQuidInspections)
        .insert(PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: when,
          updatedAt: when,
          inspectorUsername: const Value('ethan'),
          visitUuid: const Value(visitUuid),
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
          isWaterChilled: const Value(true),
          setupComplete: const Value(true),
        ));
    await open(tester);

    final row = find.text('Poultry QUID verification');
    await tester.scrollUntilVisible(row, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(row);
    await tester.pumpAndSettle();

    // Its own screen, not the labelling checklist it used to fall through
    // to — which would have saved a label record over the QUID's uuid.
    expect(find.text('QUID Determination'), findsOneWidget);
    expect(find.text('Label/Container Checklist'), findsNothing);
  });

  testWidgets('a QUID record can be read back on its own terms',
      (tester) async {
    await db
        .into(db.poultryQuidInspections)
        .insert(PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-2',
          inspectedAt: when,
          updatedAt: when,
          inspectorUsername: const Value('ethan'),
          visitUuid: const Value(visitUuid),
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
          isWaterChilled: const Value(true),
          isWholeCarcass: const Value(true),
          dispensationQuidPercent: const Value('8.0'),
          quidPercent: const Value('6.963'),
          status: const Value('completed'),
        ));
    await tester.pumpWidget(MaterialApp(
      home: CommodityInspectionViewPage(
        database: db,
        kind: 'quid',
        uuid: 'quid-2',
        title: 'Poultry QUID verification',
        uploaded: false,
        status: 'completed',
      ),
    ));
    await tester.pumpAndSettle();

    // It used to fall to the default, look a QUID uuid up in the grading
    // table and report the record as missing.
    expect(find.textContaining('Water'), findsWidgets);
    expect(find.textContaining('Whole carcass'), findsWidgets);
    expect(find.textContaining('6.963'), findsWidgets);
  });

  testWidgets('a record left over from a plan of nought can still be removed',
      (tester) async {
    // The state an inspector is left in after reducing poultry to nought
    // while a QUID record was captured under it: the plan asks for none and
    // the record is still listed, so the visit cannot be signed off.
    await db
        .into(db.poultryQuidInspections)
        .insert(PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-3',
          inspectedAt: when,
          updatedAt: when,
          inspectorUsername: const Value('ethan'),
          visitUuid: const Value(visitUuid),
          status: const Value('completed'),
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
        ));
    await open(tester);

    await tester.scrollUntilVisible(
        find.text('Poultry QUID verification'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Poultry QUID verification'), findsOneWidget);

    final minus = find
        .descendant(
          of: find.ancestor(
            of: find.text('Poultry Inspections'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.remove_circle_outline),
        )
        .first;
    await tester.ensureVisible(minus);
    await tester.pumpAndSettle();
    await tester.tap(minus);
    await tester.pumpAndSettle();

    // It warns before taking finished work — and offers to take the plan to
    // nought, never to minus one.
    expect(find.textContaining('down to 0'), findsOneWidget);
    expect(find.textContaining('down to -1'), findsNothing);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Poultry QUID verification'), findsNothing);
    expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
  });

  testWidgets('a labelling row still opens the labelling checklist',
      (tester) async {
    await db
        .into(db.poultryLabelInspections)
        .insert(PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          inspectedAt: when,
          updatedAt: when,
          inspectorUsername: const Value('ethan'),
          visitUuid: const Value(visitUuid),
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
        ));
    await open(tester);

    final row = find.text('Label/Container inspection');
    await tester.scrollUntilVisible(row, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('Label/Container Checklist'), findsOneWidget);
  });
}
