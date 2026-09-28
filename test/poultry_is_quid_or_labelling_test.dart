import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_user.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_menu_page.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// Poultry is inspected one of two ways: a QUID verification, or labelling
/// with grading to follow when the inspector says so (Ethan, 2026-09-23).
///
/// Grading used to be a third door of its own. Now the label and container
/// checklist is always done, and a YES/NO on that form — "Grading and
/// classification as well?" — opens the grading checklist for the same
/// product once the labelling is complete, or leaves it at the labelling.
void main() {
  late LocalDatabase db;
  late PoultryRepository poultry;
  late PoultryCaptureRepository capture;
  late Directory scratch;
  final when = DateTime(2026, 9, 23, 9, 30);

  // A 1×1 PNG, so a seeded photograph is a real file on disk.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    poultry = PoultryRepository(database: db, baseUrl: 'http://example.test');
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(
        jsonDecode(await File('assets/reference/poultry_reference.json')
            .readAsString()) as Map<String, dynamic>);
    scratch = await Directory.systemTemp.createTemp('fsa-poultry-doors');
    for (final name in ['one.png', 'two.png']) {
      await File('${scratch.path}/$name').writeAsBytes(png);
    }
  });
  tearDown(() async {
    await db.close();
    await scratch.delete(recursive: true);
  });

  Future<void> scrollTo(WidgetTester tester, Finder what) async {
    await tester.scrollUntilVisible(what, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(what);
    await tester.pumpAndSettle();
  }

  YesNoSlider gradingSlider(WidgetTester tester) => tester.widget<YesNoSlider>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Grading and classification as well?'),
            matching: find.byType(YesNoQuestion),
          ),
          matching: find.byType(YesNoSlider),
        ),
      );

  group('the visit offers two doors', () {
    testWidgets('QUID, or labelling with grading to follow', (tester) async {
      await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: 'visit-1',
            inspectorUsername: const Value('ethan'),
            startedAt: when,
            facilityName: const Value('Rainbow Chickens - Hammarsdale'),
            // The door must be complete before an inspection may start.
            facilityAddress: const Value('1 Farm Road, Hammarsdale'),
            contactEmail: const Value('t@rainbow.test'),
            facilityType: const Value('Retailer'),
            inspectionReason: const Value('Inspection'),
            distanceTravelledKm: const Value(42),
            plannedPoultry: const Value(1),
          ));
      await tester.pumpWidget(MaterialApp(
        home: StoreVisitPage(
          visitUuid: 'visit-1',
          visits: VisitRepository(db),
          eggs: EggsRepository(database: db, baseUrl: ''),
          eggsSync: null,
          poultry: poultry,
          poultryCapture: capture,
          rawRmp: RawRmpRepository(database: db, baseUrl: ''),
          pmp: PmpRepository(database: db, baseUrl: ''),
          inspectorName: 'ethan',
          canRemoveRecords: false,
        ),
      ));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('START POULTRY INSPECTION'));
      await tester.tap(find.text('START POULTRY INSPECTION'));
      await tester.pumpAndSettle();

      expect(find.text('Which poultry inspection?'), findsOneWidget);
      expect(find.text('Labelling and grading'), findsOneWidget);
      expect(find.text('QUID verification'), findsOneWidget);
      expect(find.text('Grading and classification'), findsNothing,
          reason: 'grading is asked for on the label form, not at the door');
      expect(find.text('Label and container checklist'), findsNothing);
    });
  });

  group('the label form asks about grading', () {
    Future<void> open(WidgetTester tester,
        {String? existingUuid, VisitPrefill? visit}) async {
      await tester.pumpWidget(MaterialApp(
        home: PoultryLabelChecklistForm(
          repository: poultry,
          captureRepository: capture,
          inspectorName: 'ethan',
          existingUuid: existingUuid,
          visit: visit,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('as a YES/NO on the product, starting at NO', (tester) async {
      await open(tester);
      await scrollTo(tester, find.text('Grading and classification as well?'));
      expect(gradingSlider(tester).value, isFalse);
      expect(find.textContaining('NO records the labelling only'),
          findsOneWidget);
    });

    testWidgets('and a resumed draft remembers the answer', (tester) async {
      await db
          .into(db.poultryLabelInspections)
          .insert(PoultryLabelInspectionsCompanion.insert(
            clientUuid: 'label-yes',
            inspectedAt: when,
            updatedAt: when,
            gradingToFollow: const Value(true),
          ));
      await open(tester, existingUuid: 'label-yes');
      await scrollTo(tester, find.text('Grading and classification as well?'));
      expect(gradingSlider(tester).value, isTrue);
    });

    testWidgets(
        'YES opens the grading checklist for the same product once the '
        'labelling is complete', (tester) async {
      const visit = VisitPrefill(
        uuid: 'visit-1',
        facilityName: 'Rainbow Chickens - Hammarsdale',
        facilityAddress: '1 Farm Road',
        facilityPhone: '031 000 0000',
        contactPerson: 'T. Dlamini',
        contactEmail: 't@rainbow.test',
        representative: 'T. Dlamini',
        managerName: 'S. Naidoo',
        managerEmail: 's@rainbow.test',
      );
      await db
          .into(db.poultryLabelInspections)
          .insert(PoultryLabelInspectionsCompanion.insert(
            clientUuid: 'label-1',
            visitUuid: const Value('visit-1'),
            inspectedAt: when,
            updatedAt: when,
            registrationNumber: const Value('ZA-PM-4471'),
            productDetails: const Value('Whole Frozen Chicken'),
            gradingToFollow: const Value(true),
          ));
      // The two label photographs the checklist is read against.
      for (final name in ['one.png', 'two.png']) {
        await db.into(db.poultryPhotos).insert(PoultryPhotosCompanion.insert(
              recordUuid: 'label-1',
              kind: 'label',
              filePath: '${scratch.path}/$name',
              capturedAt: when,
            ));
      }
      await open(tester, existingUuid: 'label-1', visit: visit);

      await scrollTo(tester, find.text('Complete'));
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();

      // The labelling is saved, waiting for the visit's sign-off…
      final label = (await db.select(db.poultryLabelInspections).get()).single;
      expect(label.status, 'ready');
      // …and the grading checklist is open, on the same pack.
      expect(find.text('Poultry Inspection Details'), findsOneWidget);
      expect(find.text('Label/Container Checklist'), findsNothing);
      expect(find.text('ZA-PM-4471'), findsOneWidget);
      // Further down the grading form's list, so built once scrolled to.
      await scrollTo(tester, find.text('Whole Frozen Chicken'));
      expect(find.text('Whole Frozen Chicken'), findsOneWidget);
    });

    testWidgets('NO leaves it at the labelling', (tester) async {
      const visit = VisitPrefill(
        uuid: 'visit-1',
        facilityName: 'Rainbow Chickens - Hammarsdale',
        facilityAddress: '',
        facilityPhone: '',
        contactPerson: '',
        contactEmail: '',
        representative: '',
        managerName: '',
        managerEmail: '',
      );
      await db
          .into(db.poultryLabelInspections)
          .insert(PoultryLabelInspectionsCompanion.insert(
            clientUuid: 'label-2',
            visitUuid: const Value('visit-1'),
            inspectedAt: when,
            updatedAt: when,
          ));
      for (final name in ['one.png', 'two.png']) {
        await db.into(db.poultryPhotos).insert(PoultryPhotosCompanion.insert(
              recordUuid: 'label-2',
              kind: 'label',
              filePath: '${scratch.path}/$name',
              capturedAt: when,
            ));
      }
      // Under a Navigator with a page beneath, so the form has somewhere to
      // go back to when it is done.
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PoultryLabelChecklistForm(
                      repository: poultry,
                      captureRepository: capture,
                      inspectorName: 'ethan',
                      existingUuid: 'label-2',
                      visit: visit,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Complete'));
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget, reason: 'back where it began');
      expect(find.text('Poultry Inspection Details'), findsNothing);
      expect(await db.select(db.poultryInspections).get(), isEmpty);
    });
  });

  testWidgets('the poultry menu has the same two doors', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PoultryMenuPage(
        repository: poultry,
        captureRepository: capture,
        user: const SessionUser(userName: 'ethan', roleName: 'Inspector'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Labelling and Grading Checklist'), findsOneWidget);
    expect(find.text('Setup QUID Checklist'), findsOneWidget);
    expect(find.text('Continue with QUID Checklist'), findsOneWidget);
    expect(find.text('New Grading and Classification Checklist'), findsNothing);
    expect(find.text('New Label/Container Checklist'), findsNothing);
  });
}
