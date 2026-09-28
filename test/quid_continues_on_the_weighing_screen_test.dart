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
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// A QUID determination whose set-up is saved carries on at the weighing
/// screen when the visit's main button is pressed — not on a blank set-up
/// form, which is what the button opened on the tablet (2026-09-25): the
/// injectors looked lost, and the only way to the scale was the row's arrow.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;
  final when = DateTime(2026, 9, 25, 9, 30);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('QUID test'),
          facilityAddress: const Value('1 Test Road'),
          contactEmail: const Value('test@example.com'),
          contactPerson: const Value('Tester'),
          facilityType: const Value('Abattoir'),
          inspectionReason: const Value('Inspection'),
          distanceTravelledKm: const Value(5),
          plannedPoultry: const Value(1),
        ));
    // The set-up saved from the door: water, whole carcass, one injector.
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'quid-1',
      inspectedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('ethan'),
      visitUuid: const Value('visit-1'),
      facilityName: const Value('QUID test'),
      isWaterChilled: const Value(true),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
    ));
    await capture.replaceQuidInjectors('quid-1', [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: 'quid-1',
        position: 1,
        name: const Value('Brine 1'),
        quidPercent: const Value('10'),
      ),
    ]);
  });
  tearDown(() => db.close());

  testWidgets('the continue button opens the weighing screen with the set-up',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: 'visit-1',
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: capture,
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();

    const button = 'CONTINUE POULTRY INSPECTION';
    await tester.scrollUntilVisible(find.text(button), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(button));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();

    expect(find.text('QUID Determination'), findsOneWidget,
        reason: 'the weighing screen, not the set-up form');
    expect(find.text('Setup QUID Checklist'), findsNothing);
    expect(find.text('Which poultry inspection?'), findsNothing,
        reason: 'the question was answered when the set-up was made');
    // Its set-up came with it: the record was continued, not replaced.
    expect(find.text('Whole Carcass'), findsOneWidget);
    final injectors = await capture.quidInjectors('quid-1');
    expect(injectors.map((i) => i.name), ['Brine 1']);
  });
}
