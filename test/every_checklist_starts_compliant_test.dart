import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/domain/pmp_rules.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_inspection_form.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

/// Every checklist in the app opens Compliant, on every commodity.
///
/// Eggs were changed to open this way at the FSA's request (2026-09-07) and
/// the other three were left as they were, so the same inspector met the
/// opposite default depending on which form they had opened — and a raw or
/// poultry checklist nobody touched went up as a deviation on every single
/// row.
void main() {
  late LocalDatabase db;
  // Read here, in real time, not inside a testWidgets body: file I/O never
  // completes under the widget test's fake clock, and the form's spinner
  // then waits on rules that never arrive.
  late Map<String, Map<String, dynamic>> bundles;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    bundles = {
      for (final name in [
        'rawrmp_reference.json',
        'pmp_reference.json',
        'poultry_reference.json',
        'eggs_reference.json',
      ])
        name: jsonDecode(
                await File('assets/reference/$name').readAsString())
            as Map<String, dynamic>,
    };
  });
  tearDown(() async => db.close());

  Map<String, dynamic> bundle(String name) => bundles[name]!;

  /// How many slides are showing, and how many of them read Compliant.
  ({int total, int compliant}) slides(WidgetTester tester) {
    final all = tester.widgetList<ComplianceSlider>(
        find.byType(ComplianceSlider));
    return (
      total: all.length,
      compliant: all.where((s) => s.compliant).length,
    );
  }

  void expectAllCompliant(WidgetTester tester, String what) {
    final counted = slides(tester);
    expect(counted.total, greaterThan(0),
        reason: '$what showed no checklist rows at all');
    expect(counted.compliant, counted.total,
        reason: '$what opened with ${counted.total - counted.compliant} of '
            '${counted.total} rows already marked as deviations');
  }

  /// Brings [text] on screen in a lazy list and settles.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  /// Answers the yes/no question headed [label]. The slide sits beside the
  /// words, so it is the YES or NO side that gets tapped, not the words.
  Future<void> answer(WidgetTester tester, String label,
      {required bool yes}) async {
    await scrollTo(tester, label);
    final question = find.ancestor(
        of: find.text(label), matching: find.byType(YesNoQuestion));
    await tester.tap(find.descendant(
        of: question, matching: find.text(yes ? 'YES' : 'NO')));
    await tester.pumpAndSettle();
  }

  /// Raw and PMP keep their rows behind a "present" question, so nothing is
  /// on screen to count until it is answered Yes. That puts the marking rows
  /// directly under it, where the lazy list builds them.
  Future<void> openMarkingRows(WidgetTester tester) =>
      answer(tester, 'Marking Label Present', yes: true);

  testWidgets('a raw processed meat checklist', (tester) async {
    final repository =
        RawRmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('rawrmp_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
    await openMarkingRows(tester);
    expectAllCompliant(tester, 'the raw checklist');
  });

  testWidgets('a processed meat checklist', (tester) async {
    final repository =
        PmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('pmp_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: PmpInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
    await openMarkingRows(tester);
    expectAllCompliant(tester, 'the PMP checklist');
  });

  // The grading form seeds its rows through the same _startCompliant as the
  // label form below, but shows them only once a whole-carcass portion type
  // and a grading location are picked; the label form's inner rows are
  // ungated, so they stand for both.
  testWidgets('a label and container checklist', (tester) async {
    final repository =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('poultry_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
    // Scrolling to the outer-container heading builds every inner-label row
    // on the way down. Section headings render in capitals.
    await scrollTo(tester, 'OUTER CONTAINER LABEL');
    expectAllCompliant(tester, 'the label/container checklist');
  });

  testWidgets('and the egg outer packaging block, the moment it opens',
      (tester) async {
    // Turning "Is the outer labelling available for inspection" on used to
    // mark every row in the block as a deviation, so an inspector who said
    // it was available and moved on served a rejection for the whole outer
    // block without answering a single row.
    final repository = EggsRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('eggs_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(repository: repository, inspectorName: 'ethan'),
    ));
    await tester.pumpAndSettle();

    final before = slides(tester);
    final outerSwitch = find.text('Is the outer labelling available for '
        'inspection');
    await tester.scrollUntilVisible(outerSwitch, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await answer(tester, 'Is the outer labelling available for inspection',
        yes: true);

    final after = slides(tester);
    expect(after.total, greaterThan(before.total),
        reason: 'the outer block should have appeared');
    expectAllCompliant(tester, 'the egg outer packaging block');
  });

  // ------------------------------------------------------------------------
  // A block that is switched off and on again, or resumed from a draft that
  // was saved with it off, has to come back Compliant too. Only the OFF
  // branch of these switches existed, so the second opening of a block was
  // every row a deviation.


  testWidgets('a PMP section switched off and on again', (tester) async {
    final repository =
        PmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('pmp_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: PmpInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
    await answer(tester, 'Marking Label Present', yes: true);
    await answer(tester, 'Marking Label Present', yes: false);
    await answer(tester, 'Marking Label Present', yes: true);
    expectAllCompliant(tester, 'the PMP marking block, opened a second time');
  });

  testWidgets('a PMP draft saved with a section off, then opened',
      (tester) async {
    final repository =
        PmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('pmp_reference.json'));
    // Saved the way the form saves it with marking off: every other row
    // compliant, the marking rows absent.
    final items = await repository.checklistItems();
    final saved = [
      for (final i in items)
        if (i.section != PmpSection.marking) i.id,
    ];
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          inspectorUsername: const Value('ethan'),
          markingLabelsPresent: const Value(false),
          compliantItemIds: Value(saved.join(',')),
        ));
    await tester.pumpWidget(MaterialApp(
      home: PmpInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
        existingUuid: 'pmp-1',
      ),
    ));
    await tester.pumpAndSettle();
    await answer(tester, 'Marking Label Present', yes: true);
    expectAllCompliant(tester, 'the PMP marking block on a resumed draft');
  });

  testWidgets('the poultry outer label block switched off and on again',
      (tester) async {
    final repository =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('poultry_reference.json'));
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
    await answer(tester, 'Outer Container Label Present', yes: true);
    await answer(tester, 'Outer Container Label Present', yes: false);
    await answer(tester, 'Outer Container Label Present', yes: true);
    expectAllCompliant(tester, 'the outer label block, opened a second time');
  });

  testWidgets('a poultry label draft saved with the outer block off, then '
      'opened', (tester) async {
    final repository =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('poultry_reference.json'));
    final items = await repository.checklistItems();
    final saved = [
      for (final i in items)
        if (i.kind != PoultryChecklistKind.labelOuter) i.id,
    ];
    await db
        .into(db.poultryLabelInspections)
        .insert(PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          inspectorUsername: const Value('ethan'),
          outerLabelsPresent: const Value(false),
          compliantItemIds: Value(saved.join(',')),
        ));
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
        existingUuid: 'label-1',
      ),
    ));
    await tester.pumpAndSettle();
    await answer(tester, 'Outer Container Label Present', yes: true);
    expectAllCompliant(tester, 'the outer label block on a resumed draft');
  });

  // ------------------------------------------------------------------------
  // Grading is judged per sample from a set of the rows each carcass PASSED.
  // A fresh sample used to start with an empty set, so a consignment nobody
  // had marked went into the record as failing every grading standard on
  // every carcass, and raised a direction for it.

  testWidgets('a grading sample starts with every standard met', (tester) async {
    final repository =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle('poultry_reference.json'));
    // A whole carcass at an abattoir is what makes the grading block appear;
    // seeded rather than picked, so the test is about the rows, not the
    // pickers above them.
    await db.into(db.poultryInspections).insert(PoultryInspectionsCompanion.insert(
          clientUuid: 'grading-1',
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          inspectorUsername: const Value('ethan'),
          meatTypeId: const Value(1), // Chicken
          portionTypeId: const Value(1), // Whole Carcass
          locationId: const Value(7), // Abattoir
        ));
    await tester.pumpWidget(MaterialApp(
      home: PoultryInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
        existingUuid: 'grading-1',
      ),
    ));
    await tester.pumpAndSettle();

    // Section headings render in capitals; scroll the grading rows into view.
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
          (w) => w is Text && (w.data == 'GRADING' || w.data == 'Grading')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expectAllCompliant(tester, 'the grading rows of a fresh sample');

    // Marking one standard as failed changes that one row and no other -
    // which is only true if the set was seeded rather than empty.
    final before = slides(tester);
    final deviationSide = find.descendant(
      of: find.byType(ComplianceSlider).first,
      matching: find.text('DEVIATION'),
    );
    await tester.tap(deviationSide);
    await tester.pumpAndSettle();
    final after = slides(tester);
    expect(after.total, before.total);
    expect(after.compliant, before.compliant - 1,
        reason: 'one tap should fail exactly one standard');
  });
}
