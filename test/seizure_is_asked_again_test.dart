import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';

/// A row marked deviation raised the seizure question; marked back compliant
/// and then deviation again, it did not raise it a second time, because the
/// form remembered it had asked (Ethan, 2026-09-29). An answer now lapses
/// once the finding clears, so the question comes back with the finding.
void main() {
  late LocalDatabase db;
  late EggsRepository repository;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repository = EggsRepository(baseUrl: 'http://example.test', database: db);
    const rows = [
      // First, so the grade/size weighing question stays out of the way.
      'Inner Container-Indication of Sizes and Grade Designation',
      'Inner Container-Indication of "Best Before", "Best Quality Before" '
          'or Abbreviation "BB"',
      'Inner Container-The Expressions: Eggs, Cage, Barn or Free Range*, '
          'Pasteurised',
    ];
    for (final (index, description) in rows.indexed) {
      await db.into(db.eggRequirements).insert(
            EggRequirementsCompanion.insert(
              kind: 'label_pack',
              description: description,
              sortOrder: Value(index),
            ),
          );
    }
  });
  tearDown(() async => db.close());

  Future<void> mark(WidgetTester tester, int row, {required bool compliant}) async {
    final slider = tester.widgetList<ComplianceSlider>(
      find.byType(ComplianceSlider),
    ).elementAt(row);
    slider.onChanged(compliant);
    await tester.pumpAndSettle();
  }

  Future<void> markBestBefore(WidgetTester tester, {required bool compliant}) =>
      mark(tester, 1, compliant: compliant);

  Future<void> openChecklist(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: EggInspectionForm(repository: repository, inspectorName: 'Ethan'),
    ));
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 12 && find.byType(ComplianceSlider).evaluate().length < 3;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('the seizure question returns with the finding', (tester) async {
    await openChecklist(tester);

    // Deviation, not indicated at all: the question is put.
    await markBestBefore(tester, compliant: false);
    await tester.tap(find.text('Not indicated at all'));
    await tester.pumpAndSettle();
    expect(find.text('This consignment must be seized'), findsOneWidget);
    await tester.tap(find.text('Carry on inspecting'));
    await tester.pumpAndSettle();

    // Back to compliant: nothing to seize, nothing asked.
    await markBestBefore(tester, compliant: true);
    expect(find.text('This consignment must be seized'), findsNothing);

    // Deviation again: the question is put again.
    await markBestBefore(tester, compliant: false);
    await tester.tap(find.text('Not indicated at all'));
    await tester.pumpAndSettle();
    expect(find.text('This consignment must be seized'), findsOneWidget);
  });

  testWidgets('a second, different omission is asked about too',
      (tester) async {
    await openChecklist(tester);

    // The best-before date is missing: asked, and the inspector carries on.
    await markBestBefore(tester, compliant: false);
    await tester.tap(find.text('Not indicated at all'));
    await tester.pumpAndSettle();
    expect(find.text('This consignment must be seized'), findsOneWidget);
    await tester.tap(find.text('Carry on inspecting'));
    await tester.pumpAndSettle();

    // Then "Eggs" is missing too: a new reason, so the question comes again
    // — straight away, with nothing to ask first (Ethan, 2026-10-03).
    await mark(tester, 2, compliant: false);
    expect(find.text('Not indicated?'), findsNothing);
    expect(find.text('This consignment must be seized'), findsOneWidget);
    expect(find.textContaining('The expression "Eggs" is not indicated'),
        findsOneWidget);
  });

  testWidgets('a pack with no size or grade to weigh against is a seizure',
      (tester) async {
    await openChecklist(tester);

    // The size and grade row marked deviation, and the eggs cannot be
    // weighed because the grade is not on the pack at all.
    await mark(tester, 0, compliant: false);
    expect(find.text('Can you still weigh the eggs?'), findsOneWidget);
    await tester.tap(find.text('No, skip weighing'));
    await tester.pumpAndSettle();
    expect(find.text('What is missing from the pack?'), findsOneWidget);
    await tester.tap(find.text('The grade'));
    await tester.pumpAndSettle();

    // Annexure D: an omitted designation is an immediate seizure.
    expect(find.text('This consignment must be seized'), findsOneWidget);
    expect(find.textContaining('The grade designation is not indicated'),
        findsOneWidget);
  });
}
