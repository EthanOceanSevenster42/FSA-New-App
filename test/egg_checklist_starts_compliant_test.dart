import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';

/// The labelling checklist opens Compliant, and the inspector marks the
/// deviations.
///
/// It used to open as deviations throughout, so that nothing was claimed met
/// before anyone had looked. In the field that inverted the work: a compliant
/// pack meant moving twenty rows one at a time, and a row missed in the sweep
/// became a deviation nobody intended. A deviation is the exception on a
/// normal pack, so it is the exception that gets marked (FSA, 2026-09-07).
///
/// What still must not happen is a row arriving already *failed* — that would
/// put a deviation on the record before the label was read.
void main() {
  late LocalDatabase db;
  late EggsRepository repository;

  const rows = [
    (kind: 'label_pack', description: 'The Name of the Country of Origin'),
    (kind: 'label_pack', description: 'Indication of Size and Grade'),
    (kind: 'label_outer', description: 'Be intact and suitable for purpose'),
    (kind: 'packing', description: 'Free from any matter other than eggs'),
  ];

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repository = EggsRepository(baseUrl: 'http://example.test', database: db);
    for (final (index, row) in rows.indexed) {
      await db.into(db.eggRequirements).insert(
            EggRequirementsCompanion.insert(
              kind: row.kind,
              description: row.description,
              sortOrder: Value(index),
            ),
          );
    }
  });
  tearDown(() async => db.close());

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: EggInspectionForm(
          repository: repository,
          inspectorName: 'Armand',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every row starts compliant, and none pre-failed', (tester) async {
    await openForm(tester);

    // The list builds lazily, so the checklist has to be scrolled into
    // existence before it can be read.
    for (var i = 0;
        i < 12 && find.byType(ComplianceSlider).evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    final rows = tester.widgetList<ComplianceSlider>(
      find.byType(ComplianceSlider),
    );
    expect(rows, isNotEmpty, reason: 'the checklist should be on the form');
    expect(
      rows.every((row) => row.compliant == true),
      isTrue,
      reason: 'a deviation is the exception, and no row may arrive pre-failed',
    );
  });
}
