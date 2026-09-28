import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/domain/rawrmp_rules.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

/// Raw follows FSA-SOP-APS-001 Annexure A (Ethan, 2026-09-26): a ticked
/// deviation fixes the rectification period, and the deviations the
/// annexure seizes on — batch code, an omitted product name, a container,
/// a failed composition — put the seizure question.
RawRmpChecklistItemRef row(int id, RawRmpSection section, String description) =>
    RawRmpChecklistItemRef(
        id: id,
        section: section,
        originalId: id,
        description: description,
        regulationReference: '');

void main() {
  final items = [
    row(1, RawRmpSection.marking, 'Prescribed Particulars'),
    row(2, RawRmpSection.marking, 'Appropriate Product Name'),
    row(3, RawRmpSection.marking, 'Additions to Appropriate Product Name'),
    row(4, RawRmpSection.marking, 'Name and Address'),
    row(5, RawRmpSection.marking, 'Date Marking/Batch Code/Batch Number'),
    row(6, RawRmpSection.marking, 'Country of Origin'),
    row(7, RawRmpSection.marking, 'Restricted Particulars (section 6 of APS Act)'),
    row(15, RawRmpSection.container, 'Suitable for the Purpose'),
    row(21, RawRmpSection.fridge,
        'Appropriate product name - in immediate vacinity of each class'),
    row(22, RawRmpSection.notice, 'May not convey or create false impressions'),
  ];
  final all = {for (final i in items) i.id};
  final present = {
    RawRmpSection.marking,
    RawRmpSection.container,
    RawRmpSection.fridge,
    RawRmpSection.notice,
  };

  group('Annexure A, row by row', () {
    test('a missing batch code is an immediate seizure', () {
      expect(RawRmpRules.actionFor(items[4], productNameAbsent: false),
          RawRmpAction.seize);
    });

    test('the product name omitted is a seizure; shown but wrong is 30 days',
        () {
      expect(RawRmpRules.actionFor(items[1], productNameAbsent: true),
          RawRmpAction.seize);
      expect(RawRmpRules.actionFor(items[1], productNameAbsent: false),
          RawRmpAction.rectify30Days);
    });

    test('a container that does not comply is seized or put right at once',
        () {
      expect(RawRmpRules.actionFor(items[7], productNameAbsent: false),
          RawRmpAction.seizeOrRectifyNow);
      expect(
          RawRmpRules.seizureRequired(
            items: items,
            present: present,
            compliantItemIds: all.difference({15}),
            productNameAbsent: false,
          ),
          isTrue);
    });

    test('the display fridge is 3 days', () {
      expect(RawRmpRules.actionFor(items[8], productNameAbsent: false),
          RawRmpAction.rectify3Days);
    });

    test('additions, name and address, origin, restricted particulars, the '
        'notice board and prescribed particulars are 30 days', () {
      for (final id in [1, 3, 4, 6, 7, 22]) {
        final item = items.firstWhere((i) => i.id == id);
        expect(RawRmpRules.actionFor(item, productNameAbsent: false),
            RawRmpAction.rectify30Days,
            reason: item.description);
      }
    });

    test('a compositional deviation fails the standard', () {
      expect(
          RawRmpRules.compositionFails(
              const [CompositionAnswer(deviation: true), CompositionAnswer()]),
          isTrue);
      expect(RawRmpRules.compositionFails(CompositionChecklist.blank()),
          isFalse);
    });
  });

  group('what the rejection carries', () {
    test('the shortest period among the deviations wins', () {
      expect(
          RawRmpRules.rectificationDays(
            items: items,
            present: present,
            compliantItemIds: all.difference({6, 21}),
            productNameAbsent: false,
          ),
          3);
      expect(
          RawRmpRules.correctByDate(
              inspectedAt: DateTime(2026, 9, 26, 11), days: 3),
          DateTime(2026, 9, 29));
    });

    test('a failed composition runs from today', () {
      expect(
          RawRmpRules.rectificationDays(
            items: items,
            present: present,
            compliantItemIds: all,
            productNameAbsent: false,
            compositionFailed: true,
          ),
          0);
    });

    test('nothing wrong means no date', () {
      expect(
          RawRmpRules.rectificationDays(
            items: items,
            present: present,
            compliantItemIds: all,
            productNameAbsent: false,
          ),
          isNull);
      expect(RawRmpRules.periodLabel(30), '30-day rectification notice');
    });
  });

  group('on the form', () {
    late LocalDatabase db;
    late Map<String, dynamic> bundle;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      bundle = jsonDecode(await File('assets/reference/rawrmp_reference.json')
          .readAsString()) as Map<String, dynamic>;
    });
    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    /// Opens a draft that already carries its two product photographs: the
    /// checklist stays locked until they are taken.
    Future<void> open(WidgetTester tester, RawRecordKind kind) async {
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repository =
          RawRmpRepository(database: db, baseUrl: 'http://example.test');
      final capture =
          PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundle);
      final when = DateTime.now();
      await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-1',
            inspectedAt: when,
            updatedAt: when,
            recordKind: Value(kind.stored),
          ));
      for (var n = 0; n < 2; n++) {
        await capture.addPhoto(PoultryPhotosCompanion.insert(
          recordUuid: 'raw-1',
          kind: 'rawrmp',
          filePath: '/nowhere/raw_$n.jpg',
          capturedAt: when,
        ));
      }
      await tester.pumpWidget(MaterialApp(
        home: RawRmpInspectionForm(
          repository: repository,
          captureRepository: capture,
          inspectorName: 'ethan',
          recordKind: kind,
          existingUuid: 'raw-1',
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
          await settle(tester);
          return;
        }
      }
      fail('no slider beside "$description"');
    }

    testWidgets('a display fridge deviation sets a 3-day correct-by date',
        (tester) async {
      await open(tester, RawRecordKind.inspection);
      await yes(tester, 'Display Fridge Present');
      await untick(tester, 'Appropriate product name - in immediate');
      expect(find.text('This consignment must be seized'), findsNothing);
      final due = DateTime.now().add(const Duration(days: 3));
      final dmy = '${due.day.toString().padLeft(2, '0')}/'
          '${due.month.toString().padLeft(2, '0')}/${due.year}';
      expect(find.text(dmy), findsOneWidget);
      expect(find.textContaining('3-day rectification notice'),
          findsOneWidget);
    });

    testWidgets('a container deviation puts the seizure question',
        (tester) async {
      await open(tester, RawRecordKind.inspection);
      await yes(tester, 'Container/Outer Container Present');
      await untick(tester, 'Suitable for the Purpose');
      expect(find.text('This consignment must be seized'), findsOneWidget);
      expect(find.textContaining('Regulation 6'), findsWidgets);
    });
  });
}
