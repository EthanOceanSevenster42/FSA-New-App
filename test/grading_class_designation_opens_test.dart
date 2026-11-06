import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/picker_menu_field.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// The grading under the labelling: Class Designation Type opens once a
/// poultry type is chosen (Ethan, 2026-09-30).
void main() {
  late Map<String, dynamic> reference;
  setUpAll(() async {
    reference = jsonDecode(
            await File('assets/reference/poultry_reference.json').readAsString())
        as Map<String, dynamic>;
  });

  testWidgets('Class Designation Type opens under the labelling',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final poultry = PoultryRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(reference);
    await db
        .into(db.poultryLabelInspections)
        .insert(PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          visitUuid: const Value('visit-1'),
          inspectedAt: DateTime(2026, 9, 30),
          updatedAt: DateTime(2026, 9, 30),
          gradingToFollow: const Value(true),
        ));
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository: poultry,
        captureRepository: PoultryCaptureRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        existingUuid: 'label-1',
        visit: const VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Shop',
          facilityAddress: '',
          facilityPhone: '',
          contactPerson: '',
          contactEmail: '',
          representative: '',
          managerName: '',
          managerEmail: '',
          facilityType: 'Retailer/Shops/Distr. Centers',
          inspectionReason: 'Routine',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;

    Finder picker(String label) => find.byWidgetPredicate(
        (w) => w is PickerMenuField && w.label == label);

    await tester.scrollUntilVisible(picker('Poultry Type'), 300,
        scrollable: scrollable);
    await tester.tap(picker('Poultry Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(picker('Class Designation Type'), 300,
        scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(picker('Class Designation Type'));
    await tester.pumpAndSettle();
    expect(find.text('Broiler'), findsOneWidget);
  });
}
