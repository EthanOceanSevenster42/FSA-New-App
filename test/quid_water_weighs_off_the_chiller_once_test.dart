import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// On water chilling the weight off the water chiller is the weight going
/// onto the injector, which Step 2 asks. So Step 1 asks the weight before
/// water chilling only, as air asks the weight before chilling, and the
/// carcass is not weighed twice (Ethan, 2026-10-04).
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;
  final when = DateTime(2026, 10, 4, 9, 30);

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
          travelStart: const Value('07:30'),
          travelEnd: const Value('08:15'),
          contactPerson: const Value('Tester'),
          facilityType: const Value('Abattoir'),
          inspectionReason: const Value('Inspection'),
          distanceTravelledKm: const Value(5),
          plannedPoultry: const Value(1),
        ));
    await capture.saveQuidInspection(PoultryQuidInspectionsCompanion.insert(
      clientUuid: 'quid-1',
      inspectedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('ethan'),
      visitUuid: const Value('visit-1'),
      facilityName: const Value('QUID test'),
      productDetails: const Value('Frozen chicken'),
      isWaterChilled: const Value(true),
      isWholeCarcass: const Value(true),
      setupComplete: const Value(true),
    ));
    await capture.replaceQuidInjectors('quid-1', [
      PoultryQuidInjectorsCompanion.insert(
        inspectionUuid: 'quid-1',
        position: 1,
        name: const Value('Brine 1'),
        quidPercent: const Value('15'),
      ),
    ]);
  });
  tearDown(() => db.close());

  testWidgets('water Step 1 asks the weight before water chilling only',
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

    expect(find.text('QUID Determination'), findsOneWidget);
    // Step 1 names the chilling the plant does, and asks nothing else.
    Finder labelled(String label) => find.byWidgetPredicate(
        (w) => w is RequiredLabel && w.label == label);
    expect(labelled('Weight before water chilling (g)'), findsOneWidget);
    expect(labelled('Weight after the water chiller (g)'), findsNothing);
    expect(find.textContaining('before water chilling.'), findsOneWidget);
    expect(find.textContaining('after the water chiller'), findsNothing);
    // The pick-up follows the weight onto the injector, so it is not here.
    expect(find.text('Water this carcass took up (%)'), findsNothing);
  });
}
