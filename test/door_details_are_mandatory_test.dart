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

/// A grouped inspection cannot start, or be signed off, without the
/// facility address, the contact email and the distance travelled
/// (Ethan, 2026-09-24).
///
/// Every record in the group carries the address, the documents are sent
/// to the contact email, and the invoice is billed on the distance — so a
/// visit missing any of them produced records the office had to chase.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 24, 9, 30);
  const visitUuid = 'visit-1';

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedVisit({
    String address = '',
    String email = '',
    double? distance,
    String person = 'T. Dlamini',
    String type = 'Retailer',
    String reason = 'Inspection',
  }) =>
      db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: visitUuid,
            inspectorUsername: const Value('ethan'),
            startedAt: when,
            facilityName: const Value('Rainbow Chickens - Hammarsdale'),
            facilityType: Value(type),
            inspectionReason: Value(reason),
            facilityAddress: Value(address),
            contactPerson: Value(person),
            contactEmail: Value(email),
            distanceTravelledKm: Value(distance),
            plannedLabels: const Value(0),
            plannedPoultry: const Value(1),
          ));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: visitUuid,
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
        rawRmp: RawRmpRepository(database: db, baseUrl: ''),
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// A required label is drawn as "label *" in one piece of rich text, so
  /// it is found by the label its widget was given, not by its text.
  Finder label(String text) => find.byWidgetPredicate(
        (w) => w is RequiredLabel && w.label == text,
      );

  bool markedRequired(WidgetTester tester, String text) => tester
      .widget<LabelledField>(find.ancestor(
        of: label(text),
        matching: find.byType(LabelledField),
      ))
      .isRequired;

  testWidgets('the three fields are marked required', (tester) async {
    await seedVisit();
    await open(tester);
    for (final text in [
      'Facility address',
      'Contact email',
      'Distance travelled (km)',
    ]) {
      await tester.scrollUntilVisible(label(text), 250,
          scrollable: find.byType(Scrollable).first);
      expect(markedRequired(tester, text), isTrue, reason: text);
    }
  });

  testWidgets('an inspection will not start while they are empty, and says '
      'which', (tester) async {
    await seedVisit();
    await open(tester);

    await tapText(tester, 'START POULTRY INSPECTION');

    expect(
      find.text('Fill in the facility address, the contact email and the '
          'distance travelled (km) before starting an inspection.'),
      findsOneWidget,
    );
    expect(find.text('Which poultry inspection?'), findsNothing,
        reason: 'nothing was opened');
  });

  testWidgets('one missing is named on its own', (tester) async {
    await seedVisit(address: '1 Farm Road', email: 't@rainbow.test');
    await open(tester);

    await tapText(tester, 'START POULTRY INSPECTION');

    expect(
      find.text('Fill in the distance travelled (km) before starting an '
          'inspection.'),
      findsOneWidget,
    );
  });

  testWidgets('a distance that is not a number is not a distance',
      (tester) async {
    await seedVisit(address: '1 Farm Road', email: 't@rainbow.test');
    await open(tester);
    await tester.scrollUntilVisible(
        label('Distance travelled (km)'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.descendant(
          of: find.ancestor(
            of: label('Distance travelled (km)'),
            matching: find.byType(LabelledField),
          ),
          matching: find.byType(TextField),
        ),
        'far');
    await tester.pumpAndSettle();

    await tapText(tester, 'START POULTRY INSPECTION');
    expect(find.textContaining('the distance travelled (km)'), findsOneWidget);
  });

  testWidgets('the facility type and reason are held to their star too',
      (tester) async {
    await seedVisit(
        address: '1 Farm Road',
        email: 't@rainbow.test',
        distance: 42,
        type: '',
        reason: '');
    await open(tester);

    await tapText(tester, 'START POULTRY INSPECTION');

    expect(
      find.text('Fill in the inspection facility type and the reason for '
          'inspection before starting an inspection.'),
      findsOneWidget,
    );
  });

  testWidgets('with all three filled in, the inspection starts',
      (tester) async {
    await seedVisit(
        address: '1 Farm Road', email: 't@rainbow.test', distance: 42);
    await open(tester);

    await tapText(tester, 'START POULTRY INSPECTION');

    expect(find.textContaining('Fill in'), findsNothing);
    expect(find.text('Which poultry inspection?'), findsOneWidget);
  });

  testWidgets('sign-off is held back the same way', (tester) async {
    // Filled in when the inspection started, cleared afterwards: the
    // sign-off checks again rather than trusting the start.
    await seedVisit(address: '1 Farm Road', person: '');
    await db
        .into(db.poultryLabelInspections)
        .insert(PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          visitUuid: const Value(visitUuid),
          inspectedAt: when,
          updatedAt: when,
          status: const Value('ready'),
          inspectorUsername: const Value('ethan'),
          facilityName: const Value('Rainbow Chickens - Hammarsdale'),
        ));
    await open(tester);

    await tapText(tester, 'SIGN & SUBMIT ALL INSPECTIONS');

    expect(
      find.text('Fill in the person in charge / representative at store, '
          'the contact email and the distance travelled (km) before '
          'signing off.'),
      findsOneWidget,
    );
    expect(find.text('Store / Client Signature'), findsNothing,
        reason: 'the signature pad did not open');
  });
}
