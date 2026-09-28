import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_form_widgets.dart';

/// Every on/off switch on the forms is a YES / NO slide, drawn as the
/// checklist rows are.
///
/// A thumb to one side said nothing about what it meant — "No Haugh readings
/// required" lit had to be read as readings *not* wanted. Both answers are
/// now written on the control and the one in force is lit (Ethan,
/// 2026-09-23).
void main() {
  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))));

  Color? litColour(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.color)
      .whereType<Color>()
      .firstWhere((c) => c != AppColors.surfaceAlt, orElse: () => Colors.transparent);

  testWidgets('both answers are written on it, and the side tapped is the '
      'answer', (tester) async {
    bool? heard;
    await show(tester, YesNoSlider(value: true, onChanged: (v) => heard = v));
    expect(find.text('YES'), findsOneWidget);
    expect(find.text('NO'), findsOneWidget);

    await tester.tap(find.text('NO'));
    await tester.pumpAndSettle();
    expect(heard, isFalse);
  });

  testWidgets('tapping the side already in force changes nothing',
      (tester) async {
    var calls = 0;
    await show(tester, YesNoSlider(value: true, onChanged: (_) => calls++));
    await tester.tap(find.text('YES'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('a No is lit in ink, not the red kept for a deviation',
      (tester) async {
    await show(tester, YesNoSlider(value: false, onChanged: (_) {}));
    expect(litColour(tester), AppColors.ink);
    await show(tester, YesNoSlider(value: true, onChanged: (_) {}));
    expect(litColour(tester), AppColors.brandPrimary);
  });

  testWidgets('a question that cannot be taken back is drawn but will not '
      'move', (tester) async {
    // "No Haugh readings required": once Yes, the original never lets it
    // go back, so the slide has no handler and a tap on NO does nothing.
    await show(tester, const YesNoQuestion(
      label: 'No Haugh readings required',
      value: true,
      onChanged: null,
    ));
    expect(find.text('No Haugh readings required'), findsOneWidget);
    await tester.tap(find.text('NO'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('YES'), findsOneWidget); // still drawn, still yes
  });

  testWidgets('the shared poultry switch is one of these, not a Switch',
      (tester) async {
    await show(tester, poultrySwitch(
      label: 'Is Sampled',
      value: false,
      onChanged: (_) {},
      helper: 'A sample goes to the laboratory.',
    ));
    expect(find.byType(YesNoQuestion), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Is Sampled'), findsOneWidget);
    expect(find.text('A sample goes to the laboratory.'), findsOneWidget);
  });

  testWidgets('the checklist slide still reads COMPLIANT / DEVIATION',
      (tester) async {
    await show(tester, ComplianceSlider(compliant: false, onChanged: (_) {}));
    expect(find.text('COMPLIANT'), findsOneWidget);
    expect(find.text('DEVIATION'), findsOneWidget);
    expect(litColour(tester), AppColors.brandRed);
  });
}
