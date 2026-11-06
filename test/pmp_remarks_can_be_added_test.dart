import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';

/// Rejection remarks on the PMP form (Neo, 2026-10-26).
///
/// PMP showed the Agency's remark list in a dropdown but gave no way to put
/// a chosen remark on the direction: the "Added Remarks" box beside it was
/// a free-text field the dropdown never wrote to, so picking a remark did
/// nothing and nothing reached the record. The raw form has worked the
/// other way for a year — pick from the list, ADD REMARK, and the chosen
/// lines accumulate — and these tests hold PMP to that behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late Map<String, dynamic> bundle;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    bundle = jsonDecode(
            await File('assets/reference/pmp_reference.json').readAsString())
        as Map<String, dynamic>;
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<PmpRepository> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository =
        PmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: PmpInspectionForm(
        repository: repository,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'neo',
      ),
    ));
    await settle(tester);
    return repository;
  }

  Future<void> yes(WidgetTester tester, String label) async {
    final target = find.descendant(
      of: find.ancestor(
          of: find.text(label), matching: find.byType(YesNoQuestion)),
      matching: find.text('YES'),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> untick(WidgetTester tester, String description) async {
    final slider = find.descendant(
      of: find.ancestor(
          of: find.textContaining(description).first,
          matching: find.byType(Row)),
      matching: find.byType(ComplianceSlider),
    );
    await tester.ensureVisible(slider.first);
    tester.widget<ComplianceSlider>(slider.first).onChanged(false);
    await settle(tester);
  }

  /// A deviation is what raises the Rejection Form the remarks sit on.
  Future<void> deviate(WidgetTester tester) async {
    await yes(tester, 'Marking Label Present');
    await untick(tester, 'Date Marking/Batch Identification');
  }

  Future<void> choose(WidgetTester tester, String remark) async {
    final picker = find.descendant(
      of: find.byWidgetPredicate((w) =>
          w is LabelledField && w.label == 'Label/Pack Rejection Remarks'),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(picker.first);
    // Opened through the handler, as the other form tests drive their
    // sliders: the field sits inside a long scroll view and a synthesised
    // tap lands off it.
    tester.widget<InkWell>(picker.first).onTap!();
    await settle(tester);
    await tester.tap(find.text('• $remark'));
    await settle(tester);
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(OutlinedButton, label);
    await tester.ensureVisible(button);
    tester.widget<OutlinedButton>(button).onPressed!();
    await settle(tester);
  }

  /// Whether the button is offered at all — a disabled one has no handler.
  bool buttonEnabled(WidgetTester tester, String label) =>
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
          .onPressed !=
      null;

  testWidgets('a remark chosen from the list can be added to the direction',
      (tester) async {
    await open(tester);
    await deviate(tester);

    // The list is offered, and nothing is on the direction yet.
    expect(find.text('Label/Pack Rejection Remarks'), findsOneWidget);
    expect(find.text('Added Remarks'), findsOneWidget);
    expect(find.text('None added yet.'), findsOneWidget);
    expect(find.text('ADD REMARK'), findsOneWidget);
    expect(find.text('CLEAR REMARKS'), findsOneWidget);
    // Nothing chosen and nothing added, so neither button does anything.
    expect(buttonEnabled(tester, 'ADD REMARK'), isFalse);
    expect(buttonEnabled(tester, 'CLEAR REMARKS'), isFalse);

    final remarks = await PmpRepository(
            database: db, baseUrl: 'http://example.test')
        .directionRemarks();
    expect(remarks, isNotEmpty, reason: 'the bundle carries the list');

    await choose(tester, remarks.first.name);
    await tapButton(tester, 'ADD REMARK');

    expect(find.text('None added yet.'), findsNothing);
    expect(find.text('• ${remarks.first.name}'), findsOneWidget);

    final saved = (await db.select(db.pmpInspections).get()).single;
    expect(saved.directionRemarks, remarks.first.name,
        reason: 'the added remark is kept on the record');
  });

  testWidgets('several remarks accumulate, one per line, without repeating',
      (tester) async {
    await open(tester);
    await deviate(tester);

    final remarks = await PmpRepository(
            database: db, baseUrl: 'http://example.test')
        .directionRemarks();
    expect(remarks.length, greaterThanOrEqualTo(2));

    await choose(tester, remarks[0].name);
    await tapButton(tester, 'ADD REMARK');
    await choose(tester, remarks[1].name);
    await tapButton(tester, 'ADD REMARK');
    // The same remark twice says nothing twice.
    await tapButton(tester, 'ADD REMARK');

    expect(find.text('• ${remarks[0].name}'), findsOneWidget);
    expect(find.text('• ${remarks[1].name}'), findsOneWidget);

    final saved = (await db.select(db.pmpInspections).get()).single;
    expect(saved.directionRemarks, '${remarks[0].name}\n${remarks[1].name}');
    // The direction itself is only raised when the form is completed, so
    // it is not asserted here; it writes the same joined list.
  });

  testWidgets('CLEAR REMARKS starts the list again', (tester) async {
    await open(tester);
    await deviate(tester);

    final remarks = await PmpRepository(
            database: db, baseUrl: 'http://example.test')
        .directionRemarks();
    await choose(tester, remarks.first.name);
    await tapButton(tester, 'ADD REMARK');
    expect(find.text('• ${remarks.first.name}'), findsOneWidget);

    await tapButton(tester, 'CLEAR REMARKS');
    expect(find.text('None added yet.'), findsOneWidget);

    final saved = (await db.select(db.pmpInspections).get()).single;
    expect(saved.directionRemarks, isEmpty);
  });

  testWidgets('remarks added earlier come back when the draft is reopened',
      (tester) async {
    await open(tester);
    await deviate(tester);

    final remarks = await PmpRepository(
            database: db, baseUrl: 'http://example.test')
        .directionRemarks();
    await choose(tester, remarks[0].name);
    await tapButton(tester, 'ADD REMARK');
    await choose(tester, remarks[1].name);
    await tapButton(tester, 'ADD REMARK');

    final uuid = (await db.select(db.pmpInspections).get()).single.clientUuid;

    final repository =
        PmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: PmpInspectionForm(
        repository: repository,
        captureRepository: PoultryCaptureRepository(
            database: db, baseUrl: 'http://example.test'),
        inspectorName: 'neo',
        existingUuid: uuid,
      ),
    ));
    await settle(tester);

    expect(find.text('• ${remarks[0].name}'), findsOneWidget);
    expect(find.text('• ${remarks[1].name}'), findsOneWidget);
    expect(find.text('None added yet.'), findsNothing);
  });
}
