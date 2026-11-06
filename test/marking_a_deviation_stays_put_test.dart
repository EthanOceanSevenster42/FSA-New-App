import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// Marking a deviation leaves the page where it is (Ethan, 2026-09-30).
///
/// A box typed in lower down kept the cursor; the question the deviation
/// put — "Is the grade designation shown on the label at all?" — handed it
/// back when it closed, and the page scrolled down to that box.
void main() {
  late Map<String, dynamic> reference;
  setUpAll(() async {
    reference = jsonDecode(
            await File('assets/reference/poultry_reference.json').readAsString())
        as Map<String, dynamic>;
  });

  testWidgets('after typing lower down, a deviation does not drag the page',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final poultry = PoultryRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(reference);
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository: poultry,
        captureRepository: PoultryCaptureRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
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
    final list = tester.state<ScrollableState>(scrollable);

    // With nothing a deviation there is no rejection, and so no remarks
    // to make (Ethan, 2026-09-30).
    expect(find.text('Labelling Non-Conformance Comments'), findsNothing);
    expect(find.text('Added Remarks'), findsNothing);

    // A first deviation brings the Rejection Form up.
    final packer = find.descendant(
        of: find
            .ancestor(
                of: find.textContaining('Indication of Packer').first,
                matching: find.byType(Row))
            .first,
        matching: find.text('DEVIATION'));
    await tester.scrollUntilVisible(packer, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(packer);
    await tester.pumpAndSettle();

    // Typed into a remark near the foot of the form, then back to the top.
    await tester.scrollUntilVisible(find.text('Added Remarks'), 300,
        scrollable: scrollable);
    final remarks = find
        .descendant(
            of: find
                .ancestor(
                    of: find.text('Added Remarks'),
                    matching: find.byType(Column))
                .first,
            matching: find.byType(TextField))
        .first;
    await tester.ensureVisible(remarks);
    await tester.pumpAndSettle();
    await tester.tap(remarks);
    await tester.enterText(remarks, 'typed');
    await tester.pumpAndSettle();
    list.position.jumpTo(0);
    await tester.pumpAndSettle();

    final row = find
        .ancestor(
            of: find.text('Grade Designation').first,
            matching: find.byType(Row))
        .first;
    final deviation = find.descendant(of: row, matching: find.text('DEVIATION'));
    await tester.scrollUntilVisible(deviation, 200, scrollable: scrollable);
    await tester.pumpAndSettle();
    final before = list.position.pixels;
    await tester.tap(deviation);
    await tester.pumpAndSettle();
    expect(find.text('Shown, but not correct'), findsOneWidget);
    await tester.tap(find.text('Shown, but not correct'));
    await tester.pumpAndSettle();

    expect(list.position.pixels, before);
  });
}
