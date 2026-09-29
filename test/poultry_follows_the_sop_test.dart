import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';

/// Poultry follows FSA-SOP-APS-001 Annexure C (Ethan, 2026-09-26): a ticked
/// deviation fixes the rectification period, and the deviations the
/// annexure seizes on — a missing production lot code, an omitted class or
/// grade designation, a container or packing failure — put the seizure
/// question.
PoultryChecklistItemRef row(
        int id, PoultryChecklistKind kind, String description) =>
    PoultryChecklistItemRef(
        id: id,
        kind: kind,
        originalId: id,
        description: description,
        regulationReference: '');

void main() {
  const inner = PoultryChecklistKind.labelInner;
  final classRow = row(24, inner, 'Class or Other Designation Indication');
  final gradeRow = row(25, inner, 'Grade Designation');
  final packer = row(26, inner, 'Indication of Packer (Physical Address)');
  final origin =
      row(27, inner, 'Country of Origin (Imported)');
  final lot = row(28, inner, 'Number and Code to Identify Production Lot');
  final fresh = row(29, inner, 'The Expression (Freshness)');
  final giblets = row(30, inner, 'The Expression (Giblets)');
  final species = row(31, inner, 'Indication of Poultry Specie');
  final restricted = row(32, inner, 'Restricted Particulars');
  final outerLot = row(37, PoultryChecklistKind.labelOuter,
      'Number and Code to Identify Production Lot');
  final container =
      row(42, PoultryChecklistKind.container, 'Strong and not damage content');
  final pack = row(18, PoultryChecklistKind.pack,
      'Different Classes/grades of poultry carcasses not packed together');
  final grading = row(4, PoultryChecklistKind.grading, 'Breast Blisters');
  final portion = row(15, PoultryChecklistKind.portion,
      'Not more than 20% of the wing tips packed as wings shall be bruised');

  PoultryAction action(PoultryChecklistItemRef item,
          {bool classOmitted = false, bool gradeOmitted = false}) =>
      PoultryRules.actionFor(item,
          classOmitted: classOmitted, gradeOmitted: gradeOmitted);

  group('Annexure C, row by row', () {
    test('container and packing are seized or put right at once', () {
      expect(action(container), PoultryAction.seizeOrRectifyNow);
      expect(action(pack), PoultryAction.seizeOrRectifyNow);
      expect(PoultryRules.daysFor(PoultryAction.seizeOrRectifyNow), 0);
    });

    test('class designation omitted is a seizure; wrong is 30 days', () {
      expect(action(classRow, classOmitted: true), PoultryAction.seize);
      expect(action(classRow), PoultryAction.rectify30Days);
    });

    test('grade designation omitted is a seizure; wrong is 30 days', () {
      expect(action(gradeRow, gradeOmitted: true), PoultryAction.seize);
      expect(action(gradeRow), PoultryAction.rectify30Days);
      // The class answer does not bleed into the grade row.
      expect(action(gradeRow, classOmitted: true), PoultryAction.rectify30Days);
    });

    test('a missing production lot code is an immediate seizure', () {
      expect(action(lot), PoultryAction.seize);
      expect(action(outerLot), PoultryAction.seize);
    });

    test('packer, origin, the expressions, species and restricted '
        'particulars are 30 days', () {
      for (final r in [packer, origin, fresh, giblets, species, restricted]) {
        expect(action(r), PoultryAction.rectify30Days, reason: r.description);
      }
    });

    test('a carcass failing its grade or a portion standard is 30 days', () {
      expect(action(grading), PoultryAction.rectify30Days);
      expect(action(portion), PoultryAction.rectify30Days);
    });
  });

  group('what the rejection carries', () {
    test('the shortest period among the deviations wins', () {
      expect(
          PoultryRules.rectificationDays(
              deviations: [packer, container],
              classOmitted: false,
              gradeOmitted: false),
          0);
      expect(
          PoultryRules.rectificationDays(
              deviations: [packer, origin],
              classOmitted: false,
              gradeOmitted: false),
          30);
      expect(
          PoultryRules.correctByDate(
              inspectedAt: DateTime(2026, 9, 26, 11), days: 30),
          DateTime(2026, 10, 26));
    });

    test('nothing wrong means no date', () {
      expect(
          PoultryRules.rectificationDays(
              deviations: const [], classOmitted: false, gradeOmitted: false),
          isNull);
      expect(PoultryRules.correctByDate(inspectedAt: DateTime(2026), days: null),
          isNull);
      expect(PoultryRules.periodLabel(0), 'Rectify immediately');
      expect(PoultryRules.periodLabel(30), '30-day rectification notice');
    });

    test('the seizure question follows the annexure', () {
      expect(
          PoultryRules.seizureRequired(
              deviations: [lot], classOmitted: false, gradeOmitted: false),
          isTrue);
      expect(
          PoultryRules.seizureRequired(
              deviations: [gradeRow], classOmitted: false, gradeOmitted: true),
          isTrue);
      expect(
          PoultryRules.seizureRequired(
              deviations: [gradeRow, packer, grading],
              classOmitted: false,
              gradeOmitted: false),
          isFalse);
    });
  });

  group('on the label checklist', () {
    late LocalDatabase db;
    late PoultryCaptureRepository capture;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      capture = PoultryCaptureRepository(
          database: db, baseUrl: 'http://example.test');
      final repo =
          PoultryRepository(database: db, baseUrl: 'http://example.test');
      final raw = await File('assets/reference/poultry_reference.json')
          .readAsString();
      await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
    });
    tearDown(() async => db.close());

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: PoultryLabelChecklistForm(
          repository:
              PoultryRepository(database: db, baseUrl: 'http://example.test'),
          captureRepository: capture,
          inspectorName: 'ethan',
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// Slides the row named [description] to a deviation: the nearest Row
    /// above the text that holds exactly one slider is that row.
    Future<void> untick(WidgetTester tester, String description) async {
      final text = find.textContaining(description).first;
      for (final rowElement
          in find.ancestor(of: text, matching: find.byType(Row)).evaluate()) {
        final slider = find.descendant(
          of: find.byElementPredicate((e) => e == rowElement),
          matching: find.byType(ComplianceSlider),
        );
        if (slider.evaluate().length == 1) {
          tester.widget<ComplianceSlider>(slider).onChanged(false);
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('no slider beside "$description"');
    }

    String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    testWidgets('a missing production lot code puts the seizure question',
        (tester) async {
      await open(tester);
      await untick(tester, 'Number and Code to Identify Production Lot');
      expect(find.text('This consignment must be seized'), findsOneWidget);
      expect(find.textContaining('no production lot code'), findsOneWidget);
      await tester.tap(find.text('Proceed with seizure'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Seizure under section 8'), findsOneWidget);
      // Shown by the date field, with its weekday in front.
      expect(find.textContaining(dmy(DateTime.now())), findsOneWidget);
    });

    testWidgets('a packer deviation sets a 30-day correct-by date',
        (tester) async {
      await open(tester);
      await untick(tester, 'Indication of Packer');
      expect(find.text('This consignment must be seized'), findsNothing);
      expect(
          find.textContaining(
              dmy(DateTime.now().add(const Duration(days: 30)))),
          findsOneWidget);
      expect(find.textContaining('30-day rectification notice'),
          findsOneWidget);
    });

    testWidgets('the grade row asks whether the designation is shown at all',
        (tester) async {
      await open(tester);
      await untick(tester, 'Grade Designation');
      expect(find.text('Is the grade designation shown on the label at all?'),
          findsOneWidget);
      await tester.tap(find.text('Not indicated at all'));
      await tester.pumpAndSettle();
      expect(find.text('This consignment must be seized'), findsOneWidget);
      expect(find.textContaining('grade designation is not indicated'),
          findsOneWidget);
      await tester.tap(find.text('Carry on inspecting'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Seizure declined'), findsOneWidget);
    });

    testWidgets('a completed checklist with deviations raises the rejection '
        'with the date', (tester) async {
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // A draft that already carries its two label photographs: the
      // checklist cannot be completed without them.
      final when = DateTime.now();
      // Every row it asks starts Compliant, as a draft the form itself
      // wrote would have them; an empty set reads as every row failed.
      await db.into(db.poultryLabelInspections).insert(
          PoultryLabelInspectionsCompanion.insert(
        clientUuid: 'label-1',
        inspectedAt: when,
        updatedAt: when,
        compliantItemIds: const Value('24,25,26,27,28,29,30,31,32,42,43'),
      ));
      for (var n = 0; n < 2; n++) {
        await capture.addPhoto(PoultryPhotosCompanion.insert(
          recordUuid: 'label-1',
          kind: 'label',
          filePath: '/nowhere/label_$n.jpg',
          capturedAt: when,
        ));
      }
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('base'))));
      final navigator = Navigator.of(tester.element(find.text('base')));
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => PoultryLabelChecklistForm(
          repository:
              PoultryRepository(database: db, baseUrl: 'http://example.test'),
          captureRepository: capture,
          inspectorName: 'ethan',
          existingUuid: 'label-1',
        ),
      )));
      await tester.pumpAndSettle();

      await untick(tester, 'Indication of Packer');
      await tester.scrollUntilVisible(find.text('Complete'), 200,
          scrollable: find.byType(Scrollable).first);
      // scrollUntilVisible stops at the first partly-visible pixel; the
      // button has to be wholly on screen or the tap lands outside it.
      await tester.ensureVisible(find.text('Complete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      expect(find.text('Checklist saved'), findsOneWidget);
      expect(find.textContaining('A rejection has been created'),
          findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final direction = await (db.select(db.poultryDirections)
            ..where((t) => t.clientUuid.equals('label-1')))
          .getSingle();
      expect(direction.nonConformanceIds.split(','), contains('26'));
      expect(direction.correctByDate,
          DateTime(when.year, when.month, when.day)
              .add(const Duration(days: 30)));
      expect(direction.actionTaken,
          'Generated from poultry labelling findings.');
    });
  });
}
