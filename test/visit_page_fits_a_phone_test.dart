import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// The Inspection page is captured on phones as well as the tablet (Ethan,
/// 2026-10-01): every row has to fit a narrow screen without overflowing.
/// Flutter reports an overflow as a test error, so pumping the page at a
/// phone's width and scrolling through it is the whole check.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 10, 1, 9);

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed({bool occurrence = false, bool captured = false}) async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Checkers Blueberry Square Hypermarket'),
          facilityAddress: const Value('Cnr Beyers Naude and Blueberry St'),
          facilityPhone: const Value('011 251 2755'),
          contactPerson: const Value('Manel'),
          contactEmail: const Value('checkers.blueberry@example.com'),
          travelStart: const Value('07:30'),
          travelEnd: const Value('08:15'),
          additionalEmail1: const Value('second.address@example.com'),
          facilityType: const Value('Retailer'),
          inspectionReason: const Value('Follow Up'),
          distanceTravelledKm: const Value(23),
          plannedEggs: const Value(2),
          plannedPoultry: const Value(1),
          plannedRaw: const Value(2),
          plannedPmp: const Value(1),
          isOccurrenceReport: Value(occurrence),
        ));
    if (captured) {
      await db.into(db.poultryLabelInspections).insert(
          PoultryLabelInspectionsCompanion.insert(
        clientUuid: 'label-1',
        visitUuid: const Value('visit-1'),
        inspectedAt: when,
        updatedAt: when,
        status: const Value('ready'),
        productDetails: const Value('Whole frozen chicken'),
      ));
    }
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: StoreVisitPage(
        visitUuid: 'visit-1',
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: true,
      ),
    ));
    await tester.pumpAndSettle();
    // Asked at the top, before the page is scrolled through.
    expect(find.text('Is this a follow-up inspection?'), findsOneWidget);
    // Top to bottom, so every row is laid out at this width.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  for (final (name, size) in [
    ('a small phone', const Size(360, 780)),
    ('an ordinary phone', const Size(412, 915)),
  ]) {
    testWidgets('the plan page fits $name', (tester) async {
      await seed(captured: true);
      await pumpAt(tester, size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the occurrence report fits $name', (tester) async {
      await seed(occurrence: true);
      await pumpAt(tester, size);
      expect(tester.takeException(), isNull);
    });
  }
}
