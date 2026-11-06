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
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// The size and grade row marked deviation, "No, skip weighing", then
/// marked compliant again: the weighing never came back, and the grade
/// stayed "Not indicated" (Ethan, 2026-09-29). Both come back now.
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    final large = (await db.select(db.eggSizes).get())
        .firstWhere((s) => s.name == 'Large');
    final grade1 = (await db.select(db.eggGrades).get())
        .firstWhere((g) => g.name == 'Grade 1');
    final tray = (await db.select(db.eggTraySizes).get())
        .firstWhere((t) => t.name == '12-Pack');
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-weigh',
          inspectedAt: DateTime(2026, 9, 29, 9),
          updatedAt: DateTime(2026, 9, 29, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          batchNumber: const Value('B123'),
          bestBefore: Value(DateTime(2026, 10, 20)),
          declaredSizeId: Value(large.id),
          declaredGradeId: Value(grade1.id),
          traySizeId: Value(tray.id),
          haughNotRequired: const Value(true),
        ));
  });
  tearDown(() async => db.close());

  /// Back to the top, then down until [target] is built — the list only
  /// builds what is on screen.
  Future<bool> onPage(WidgetTester tester, Finder target) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    try {
      await tester.scrollUntilVisible(target, 400,
          scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> markSizeAndGradeRow(WidgetTester tester,
      {required bool compliant}) async {
    final row = find.text('Indication of Sizes and Grades Designations').first;
    expect(await onPage(tester, row), isTrue);
    await tester.pumpAndSettle();
    tester
        .widget<ComplianceSlider>(find.descendant(
          of: find.ancestor(of: row, matching: find.byType(Row)).first,
          matching: find.byType(ComplianceSlider),
        ))
        .onChanged(compliant);
    await tester.pumpAndSettle();
  }

  testWidgets('marking the row compliant again brings the weighing back',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        resumeUuid: 'egg-weigh',
        visit: const VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Kroon Foods',
          facilityAddress: '',
          facilityPhone: '',
          contactPerson: '',
          contactEmail: '',
          representative: '',
          managerName: '',
          managerEmail: '',
          facilityType: 'Packhouse',
          inspectionReason: 'Inspection',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final weight = find.text('Egg Weight (g)');
    expect(await onPage(tester, weight), isTrue);

    // Deviation, and the grade is not on the pack: no weighing.
    await markSizeAndGradeRow(tester, compliant: false);
    await tester.tap(find.text('No, skip weighing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The grade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carry on inspecting'));
    await tester.pumpAndSettle();
    expect(await onPage(tester, weight), isFalse);

    // Compliant again: the weighing and the grade come back.
    await markSizeAndGradeRow(tester, compliant: true);
    expect(await onPage(tester, find.text('Grade 1')), isTrue);
    expect(await onPage(tester, weight), isTrue);
    final saved = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-weigh')))
        .getSingle();
    expect(saved.weighingNotRequired, isFalse);
  });
}
