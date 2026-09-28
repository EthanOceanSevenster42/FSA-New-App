import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/presentation/summary_widgets.dart';

/// Deviations and rejections are red, everywhere they show.
///
/// The checklist slide already said so — its DEVIATION side is the app's
/// red — but serving a rejection, which is the one thing an inspector does
/// that stops a consignment, was drawn in the same teal as every ordinary
/// action, so nothing on the screen told them apart.
void main() {
  Future<void> show(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('the deviation side of a checklist slide is red',
      (tester) async {
    await show(
        tester, ComplianceSlider(compliant: false, onChanged: (_) {}));
    final lit = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .toList();
    expect(lit, contains(AppColors.brandRed));
  });

  testWidgets('the compliant side is not', (tester) async {
    await show(tester, ComplianceSlider(compliant: true, onChanged: (_) {}));
    final lit = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .toList();
    expect(lit, isNot(contains(AppColors.brandRed)));
    expect(lit, contains(AppColors.brandPrimary));
  });

  testWidgets('a summary about a rejection carries the colour through',
      (tester) async {
    await show(
      tester,
      const SummarySection(
        title: 'Rejection served',
        accent: AppColors.brandRed,
        children: [SummaryField(label: 'Number', value: 'ABC/1')],
      ),
    );
    final heading = tester.widget<Text>(find.text('REJECTION SERVED'));
    expect(heading.style?.color, AppColors.brandRed);
  });

  testWidgets('an ordinary summary stays teal', (tester) async {
    await show(
      tester,
      const SummarySection(
        title: 'Inspection details',
        children: [SummaryField(label: 'Batch', value: '4471')],
      ),
    );
    final heading = tester.widget<Text>(find.text('INSPECTION DETAILS'));
    expect(heading.style?.color, AppColors.brandTeal);
  });
}
