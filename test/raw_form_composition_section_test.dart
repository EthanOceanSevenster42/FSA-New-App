import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The raw form carries the Regulation 5 compositional checklist
/// (SOP-APS-RAW-003): seven requirements, each with a deviation answer, a
/// contribution in grams and a remark, plus comments/actions.
void main() {
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('the checklist is on the form and answers by slider',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 14000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = RawRmpRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await repo.loadBundledRulesIfEmpty();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: RawRmpInspectionForm(
        repository: repo,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'Cinga',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('COMPOSITIONAL REQUIREMENTS CHECKLIST'), findsOneWidget);
    // Total Meat Content is not a numbered requirement with a slide; it is
    // one line showing the percentage (Ethan, 2026-10-01).
    expect(find.textContaining('7. Total Meat Content'), findsNothing);
    final total = find.text('Total meat content');
    expect(total, findsOneWidget);
    expect(
        find.descendant(
            of: find.ancestor(of: total, matching: find.byType(Row)).first,
            matching: find.byType(ComplianceSlider)),
        findsNothing);
    expect(find.textContaining('1. Manufactured from either meat'), findsOneWidget);
    // The group names the representative; the checklist does not ask.
    expect(find.text('Position of Representative', findRichText: true),
        findsNothing);
    expect(find.textContaining('Comments/Actions', findRichText: true), findsOneWidget);
    // Eight rows take a contribution; Total Meat Content is worked out
    // from the meat and the other ingredients instead. The count was last
    // right at six rows — "Food stuff" (2026-10-04) and MDM (2026-10-19)
    // have been added since.
    expect(find.textContaining('Contribution (kg)', findRichText: true), findsNWidgets(8));
    // The last row is only the result; no Meat box (Ethan, 2026-10-01).
    expect(find.textContaining('Meat (kg)', findRichText: true), findsNothing);
    // All other ingredients are the rows added up, not a box of their own.
    expect(find.textContaining('All other ingredients (g)', findRichText: true),
        findsNothing);

    // Typed in kg or grams, as the inspector chooses (Ethan, 2026-10-01).
    final unit = find.byWidgetPredicate(
        (w) => w is TwoWaySlider && w.leftLabel == 'KG');
    expect(unit, findsOneWidget);
    tester.widget<TwoWaySlider>(unit).onChanged!(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Contribution (g)', findRichText: true),
        findsNWidgets(8));
    expect(find.textContaining('Meat (g)', findRichText: true), findsNothing);
    tester.widget<TwoWaySlider>(unit).onChanged!(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Contribution (kg)', findRichText: true),
        findsNWidgets(8));

    // One row, one answer, through the same Compliant/Deviation slide every
    // other checklist in the app uses — the block used to ask it with two
    // chips of its own, which made the same question look different here.
    // Scoped to the row: the form carries a slider for every checklist
    // requirement, not only these seven.
    final row = find.ancestor(
      of: find.textContaining('1. Manufactured from either meat'),
      matching: find.byType(Row),
    );
    final slider =
        find.descendant(of: row, matching: find.byType(ComplianceSlider));
    expect(slider, findsOneWidget);

    // An untouched row is not a finding, so it reads compliant until the
    // inspector moves it.
    expect(tester.widget<ComplianceSlider>(slider).compliant, isTrue);
    await tester.tap(
        find.descendant(of: slider, matching: find.text('DEVIATION')));
    await tester.pumpAndSettle();
    expect(tester.widget<ComplianceSlider>(slider).compliant, isFalse);
  });
}
