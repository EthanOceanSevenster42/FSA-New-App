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

/// An inspector can have several inspections going at once (Ethan,
/// 2026-11-05): with one still in progress, the visit's main button starts
/// the next planned one rather than reopening the first. Once every planned
/// one is begun, it carries on with what is unfinished.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;
  final when = DateTime(2026, 11, 5, 9, 30);

  Future<void> seed({required int plannedPoultry}) async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Several at once'),
          facilityAddress: const Value('1 Test Road'),
          contactEmail: const Value('test@example.com'),
          travelStart: const Value('07:30'),
          travelEnd: const Value('08:15'),
          contactPerson: const Value('Tester'),
          facilityType: const Value('Abattoir'),
          inspectionReason: const Value('Inspection'),
          distanceTravelledKm: const Value(5),
          plannedPoultry: Value(plannedPoultry),
        ));
    // A QUID determination begun and stepped out of part-way.
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'quid-1',
      inspectedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('ethan'),
      visitUuid: const Value('visit-1'),
      facilityName: const Value('Several at once'),
      isWaterChilled: const Value(true),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
    ));
  }

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
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
  }

  testWidgets('with one in progress, the button starts the next',
      (tester) async {
    await seed(plannedPoultry: 2);
    await open(tester);

    const button = 'START POULTRY INSPECTION';
    await tester.scrollUntilVisible(find.text(button), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('CONTINUE POULTRY INSPECTION'), findsNothing);
    expect(find.textContaining('1 inspection is still in progress'),
        findsOneWidget);
    await tester.ensureVisible(find.text(button));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();

    expect(find.text('Which poultry inspection?'), findsOneWidget,
        reason: 'a fresh inspection is being started, not the QUID resumed');
  });

  testWidgets('a commodity can be started out of the plan order',
      (tester) async {
    await seed(plannedPoultry: 2);
    // Eggs first in the plan, so the main button names eggs.
    await (db.update(db.storeVisits)..where((t) => t.uuid.equals('visit-1')))
        .write(const StoreVisitsCompanion(
            plannedEggs: Value(1), planOrder: Value('egg,poultry')));
    await open(tester);

    expect(find.text('START EGG INSPECTION'), findsOneWidget,
        reason: 'by default the main button follows the plan order');
    // Every planned inspection is listed at the bottom — the poultry not yet
    // started as well as the egg — and tapping poultry opens poultry.
    expect(find.text('Not started — tap to start'), findsNWidgets(2));
    expect(find.text('Egg Inspection'), findsOneWidget);
    final start = find.text('Poultry Inspection');
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text('Which poultry inspection?'), findsOneWidget);
  });

  testWidgets('once every planned one is begun, it carries on the unfinished',
      (tester) async {
    await seed(plannedPoultry: 1);
    await open(tester);

    await tester.scrollUntilVisible(
        find.text('CONTINUE POULTRY INSPECTION'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('START POULTRY INSPECTION'), findsNothing);
  });
}
