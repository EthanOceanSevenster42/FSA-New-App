import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/features/visits/domain/inspection_reason_match.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// Opening an egg inspection and working down it.
///
/// The symptom this exists for: an inspector opened the form and found
/// "Reason for Inspection" and "Inspection Facility Type" reading "Not yet",
/// with nothing to choose. "Not yet" is what a picker shows when it has no
/// options at all, so these tests are about the rules being on the device and
/// reaching the pickers — not about the widget's wording.
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester, {VisitPrefill? visit}) async {
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
          repository: eggs, inspectorName: 'ethan', visit: visit),
    ));
    await tester.pumpAndSettle();
  }

  /// A visit as the door hands it over.
  VisitPrefill visitAtTheDoor({
    String type = 'Retail outlet',
    String reason = 'Inspection',
  }) =>
      VisitPrefill(
        uuid: 'visit-1',
        facilityName: 'Kroon Foods',
        facilityAddress: '73 Robinson Street, Queenstown',
        facilityPhone: '045 123 4567',
        contactPerson: 'S. Mabovula',
        contactEmail: '',
        representative: 'S. Mabovula',
        managerName: 'S. Mabovula',
        managerEmail: '',
        facilityType: type,
        inspectionReason: reason,
      );

  test('the rules the form opens on are on the device', () async {
    // Asserted in their own right, so a failure says whether the data or the
    // widget is at fault.
    expect(await eggs.reasons(), isNotEmpty);
    expect(await eggs.facilityTypes(), isNotEmpty);
    expect(await eggs.sizeBands(), isNotEmpty);
    expect(await eggs.requirements('label_pack'), isNotEmpty);
    expect(await eggs.traySizes(), isNotEmpty);
  });

  testWidgets('neither picker opens saying "Not yet"', (tester) async {
    await open(tester);

    expect(find.text('Not yet'), findsNothing,
        reason: '"Not yet" is a picker with nothing to offer');
    // Reason and facility type, both waiting to be chosen from.
    expect(find.text('Select'), findsNWidgets(2));
  });

  testWidgets('the reason picker offers Inspection and Follow-up only',
      (tester) async {
    await open(tester);
    final names = (await eggs.reasons()).map((r) => r.name).toList();
    expect(names, isNotEmpty);

    await tester.tap(find.text('Select').first);
    await tester.pumpAndSettle();

    // Inspection or follow-up, as the original offers them; the device's
    // "Complaint" row is not (Ethan, 2026-09-24).
    for (final name in names) {
      expect(find.text(name),
          InspectionReasonMatch.isOffered(name) ? findsWidgets : findsNothing,
          reason: name);
    }
  });

  testWidgets('a reason can be chosen and stays chosen', (tester) async {
    await open(tester);
    final first = (await eggs.reasons()).first.name;

    await tester.tap(find.text('Select').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(first).last);
    await tester.pumpAndSettle();

    // Shown on the closed picker, and one "Select" left for the facility
    // type that has not been answered yet.
    expect(find.text(first), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
  });

  testWidgets('inside a visit it does not ask either question again',
      (tester) async {
    // Both were answered at the door and travel with the visit. Asking again
    // on the form is the same question a second time, and lets one record
    // disagree with the visit it belongs to.
    await open(tester, visit: visitAtTheDoor());

    expect(find.text('Select'), findsNothing);
    expect(find.text('Not yet'), findsNothing);
    for (final reason in await eggs.reasons()) {
      expect(find.text(reason.name), findsNothing);
    }
  });

  testWidgets('it does not ask even when the door said something eggs do not '
      'offer', (tester) async {
    // "Abattoir" is a poultry answer; the egg rules have no such type. The
    // form carries none rather than asking a question the visit has settled.
    await open(tester, visit: visitAtTheDoor(type: 'Abattoir'));

    expect(find.text('Select'), findsNothing);
  });

  test('the tray sizes run in size order, with the 40-Pack among them', () async {
    final trays = await eggs.traySizes();
    final names = trays.map((t) => t.name).toList();

    // The Agency inspects 40-egg trays; the original's list had no 40, so an
    // inspector meeting one had nothing to choose.
    expect(names, contains('40-Pack'));
    // And it reads as a sequence of sizes rather than an afterthought at the
    // end: 30, then 40, then 48.
    expect(names.indexOf('40-Pack'), names.indexOf('30-Pack') + 1);
    expect(names.indexOf('48-Pack'), names.indexOf('40-Pack') + 1);
  });

  testWidgets('and so can the facility type', (tester) async {
    await open(tester);
    final type = (await eggs.facilityTypes()).first.name;

    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(type).last);
    await tester.pumpAndSettle();

    expect(find.text(type), findsOneWidget);
    expect(find.text('Not yet'), findsNothing);
  });

  testWidgets('the size picker offers "Not indicated", and says so',
      (tester) async {
    // A pack that states no size is a marking deviation, not a question the
    // inspector answers out of their own head — and Egg Size is required, so
    // without this the inspection could not be saved at all.
    await open(tester, visit: visitAtTheDoor());

    // The picker stays shut until a producer is named, and while it is shut
    // it says so — which is what an inspector meets if they reach for the
    // size first.
    expect(find.text('Choose the Egg Producer/Supplier first'), findsWidgets);

    final supplier = (await eggs.suppliers()).first.name;
    await tester.enterText(find.byType(TextField).first, supplier);
    await tester.pumpAndSettle();
    await tester.tap(find.text(supplier).last);
    await tester.pumpAndSettle();

    expect(find.text('Choose "Not indicated" if the pack shows no size.'),
        findsOneWidget,
        reason: 'the note has to say what to do when the pack states none');
  });

  testWidgets('a record saved as "Not indicated" reopens saying so',
      (tester) async {
    // The field shows a value only when that value is among its options, so
    // this fails outright if "Not indicated" is not one of them — and it
    // covers the draft surviving a reopen, which a synthetic id has to.
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: const Value(-1),
        ));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        visit: visitAtTheDoor(),
        resumeUuid: 'egg-1',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not indicated'), findsWidgets);
  });

  testWidgets('the tray picker offers "Not indicated" too', (tester) async {
    // Eggs are met loose and in unmarked trays. Annexure D of
    // FSA-SOP-APS-001 treats an omitted size indication as an omission, so
    // the inspector records that it is missing rather than picking a pack
    // size the tray does not claim.
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-2',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: Value((await eggs.sizeBands()).first.id),
          traySizeId: const Value(-1),
        ));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        visit: visitAtTheDoor(),
        resumeUuid: 'egg-2',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not indicated'), findsWidgets);
  });

  testWidgets('a best-before date already passed is accepted, and said so',
      (tester) async {
    // Expired stock on a shelf is exactly what an inspector is there to
    // find, and the form used to refuse the date on the pack outright.
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-3',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: Value((await eggs.sizeBands()).first.id),
          traySizeId: Value((await eggs.traySizes()).first.id),
          bestBefore: Value(DateTime(2026, 9, 1)),
        ));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        visit: visitAtTheDoor(),
        resumeUuid: 'egg-3',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.textContaining('Best Before/Best Quality Before Date'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("cannot be prior to today"), findsNothing);
    expect(find.textContaining("cannot be set to today"), findsNothing);
    expect(find.textContaining('This date has already passed'), findsOneWidget);
  });
}
