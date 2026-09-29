import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/domain/pmp_rules.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';

/// Processed meat follows FSA-SOP-APS-001 Annexure B (Ethan, 2026-09-26):
/// a ticked deviation fixes the rectification period, and the deviations
/// the annexure seizes on put the seizure question to the inspector.
PmpChecklistItemRef row(int id, PmpSection section, String description) =>
    PmpChecklistItemRef(
        id: id,
        section: section,
        originalId: id,
        description: description,
        regulationReference: '');

void main() {
  final items = [
    row(1, PmpSection.marking, 'Prescribed Particulars'),
    row(2, PmpSection.marking, 'Product Name'),
    row(3, PmpSection.marking, 'Additions to Product Name'),
    row(4, PmpSection.marking, 'Manufacturer/Seller'),
    row(5, PmpSection.marking, 'Date Marking/Batch Identification'),
    row(6, PmpSection.marking, 'Country of Origin'),
    row(7, PmpSection.marking, 'Restricted Particulars'),
    row(15, PmpSection.container, 'Suitable for the Purpose'),
    row(21, PmpSection.fridge,
        'Appropriate product name - in immediate vacinity of each class'),
    row(22, PmpSection.notice,
        'May not convey or create false or misleading impressions'),
  ];
  final all = {for (final i in items) i.id};
  final present = {
    PmpSection.marking,
    PmpSection.container,
    PmpSection.fridge,
    PmpSection.notice,
  };

  group('Annexure B, row by row', () {
    test('a batch code missing is an immediate seizure', () {
      expect(PmpRules.actionFor(items[4], productNameAbsent: false),
          PmpAction.seize);
    });

    test('the product name omitted is a seizure; shown but wrong is 30 days',
        () {
      expect(PmpRules.actionFor(items[1], productNameAbsent: true),
          PmpAction.seize);
      expect(PmpRules.actionFor(items[1], productNameAbsent: false),
          PmpAction.rectify30Days);
      // The additions row is not the product-name row.
      expect(PmpRules.isProductNameRow(items[2]), isFalse);
    });

    test('additions, name and address, origin, restricted particulars and '
        'the notice board are 30 days', () {
      for (final id in [1, 3, 4, 6, 7, 22]) {
        final item = items.firstWhere((i) => i.id == id);
        expect(PmpRules.actionFor(item, productNameAbsent: false),
            PmpAction.rectify30Days,
            reason: item.description);
      }
    });

    test('the display fridge is 3 days', () {
      expect(PmpRules.actionFor(items[8], productNameAbsent: false),
          PmpAction.rectify3Days);
    });

    test('a container that does not comply is seized or put right at once',
        () {
      expect(PmpRules.actionFor(items[7], productNameAbsent: false),
          PmpAction.seizeOrRectifyNow);
      expect(PmpRules.daysFor(PmpAction.seizeOrRectifyNow), 0);
    });
  });

  group('what the rejection carries', () {
    test('the shortest period among the deviations wins', () {
      // Country of origin (30) and the fridge (3): three days.
      final compliant = all.difference({6, 21});
      final days = PmpRules.rectificationDays(
        items: items,
        present: present,
        compliantItemIds: compliant,
        productNameAbsent: false,
      );
      expect(days, 3);
      expect(
          PmpRules.correctByDate(
              inspectedAt: DateTime(2026, 9, 26, 14, 30), days: days),
          DateTime(2026, 9, 29));
    });

    test('nothing wrong means no date', () {
      expect(
          PmpRules.rectificationDays(
            items: items,
            present: present,
            compliantItemIds: all,
            productNameAbsent: false,
          ),
          isNull);
      expect(PmpRules.correctByDate(inspectedAt: DateTime(2026), days: null),
          isNull);
    });

    test('a seizure not taken runs from today', () {
      final compliant = all.difference({5});
      expect(
          PmpRules.rectificationDays(
            items: items,
            present: present,
            compliantItemIds: compliant,
            productNameAbsent: false,
          ),
          0);
      expect(
          PmpRules.seizureRequired(
            items: items,
            present: present,
            compliantItemIds: compliant,
            productNameAbsent: false,
          ),
          isTrue);
    });

    test('a section not present raises nothing', () {
      expect(
          PmpRules.seizureRequired(
            items: items,
            present: {PmpSection.marking},
            compliantItemIds: all.difference({15}),
            productNameAbsent: false,
          ),
          isFalse);
    });

    test('the period reads as the annexure words it', () {
      expect(PmpRules.periodLabel(0), 'Rectify immediately');
      expect(PmpRules.periodLabel(3), '3-day rectification notice');
      expect(PmpRules.periodLabel(30), '30-day rectification notice');
    });
  });

  group('on the form', () {
    late LocalDatabase db;
    late Map<String, dynamic> bundle;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      bundle = jsonDecode(
              await File('assets/reference/pmp_reference.json').readAsString())
          as Map<String, dynamic>;
    });
    tearDown(() => db.close());

    /// Bounded pumps: the form keeps something ticking, so waiting for it
    /// to go still never returns.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repository =
          PmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundle);
      await tester.pumpWidget(MaterialApp(
        home: PmpInspectionForm(
          repository: repository,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'ethan',
        ),
      ));
      await settle(tester);
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

    /// Slides the row named [description] to a deviation.
    Future<void> untick(WidgetTester tester, String description) async {
      // The exact row where there is one: "Product Name" is also inside the
      // "Processed Meat Product Name" field caption, higher up the page.
      final exact = find.text(description);
      final label = exact.evaluate().isNotEmpty
          ? exact.first
          : find.textContaining(description).first;
      final slider = find.descendant(
        of: find.ancestor(of: label, matching: find.byType(Row)),
        matching: find.byType(ComplianceSlider),
      );
      await tester.ensureVisible(slider.first);
      final widget = tester.widget<ComplianceSlider>(slider.first);
      widget.onChanged(false);
      await settle(tester);
    }

    testWidgets('a missing batch code puts the seizure question',
        (tester) async {
      await open(tester);
      await yes(tester, 'Marking Label Present');
      await untick(tester, 'Date Marking/Batch Identification');
      expect(find.text('This consignment must be seized'), findsOneWidget);
      expect(find.textContaining('no batch code is indicated'),
          findsOneWidget);
      await tester.tap(find.text('Proceed with seizure'));
      await settle(tester);
      expect(find.textContaining('Seizure under section 8'), findsOneWidget);
    });

    testWidgets('a display fridge deviation sets a 3-day correct-by date',
        (tester) async {
      await open(tester);
      await yes(tester, 'Display Fridge Present');
      await untick(tester, 'Appropriate product name');
      expect(find.text('This consignment must be seized'), findsNothing);
      final due = DateTime.now().add(const Duration(days: 3));
      final dmy = '${due.day.toString().padLeft(2, '0')}/'
          '${due.month.toString().padLeft(2, '0')}/${due.year}';
      // Shown by the date field, with its weekday in front.
      expect(find.textContaining(dmy), findsOneWidget);
      expect(find.textContaining('3-day rectification notice'),
          findsOneWidget);
    });

    testWidgets('the product-name row asks whether the name is shown at all',
        (tester) async {
      await open(tester);
      await yes(tester, 'Marking Label Present');
      await untick(tester, 'Product Name');
      expect(find.text('Is the appropriate product name shown on the label '
          'at all?'), findsOneWidget);
      await tester.tap(find.text('Shown, but not correct'));
      await settle(tester);
      expect(find.text('This consignment must be seized'), findsNothing);
      expect(find.textContaining('30-day rectification notice'),
          findsOneWidget);
    });
  });
}
