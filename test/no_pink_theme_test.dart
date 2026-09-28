import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';

/// A red seed gives Material 3 pale pinks for its container roles. FSA's
/// palette has none: selections are the logo's teal, red means wrong.
void main() {
  bool pinkish(Color c) => c.r > c.g + 0.15 && c.r > c.b + 0.15 && c.r > 0.85;

  for (final brightness in Brightness.values) {
    test('no pink containers in the $brightness theme', () {
      final theme = AppTheme.build(brightness);
      final s = theme.colorScheme;
      for (final c in [
        s.primaryContainer,
        s.secondaryContainer,
        s.tertiaryContainer,
      ]) {
        expect(pinkish(c), isFalse,
            reason: 'container ${c.toARGB32().toRadixString(16)}');
      }
      expect(s.surfaceTint, Colors.transparent);
      expect(theme.chipTheme.selectedColor, AppColors.brandTeal);
      expect(theme.chipTheme.checkmarkColor, Colors.white);
      expect(
        theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
        AppColors.brandTeal,
      );
      expect(
        theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}),
        AppColors.brandTeal,
      );
    });
  }

  testWidgets('a chosen chip is teal by theme; a deviation chip asks for red',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: Row(children: [
          ChoiceChip(
              label: const Text('Is Sampled'),
              selected: true,
              onSelected: (_) {}),
          ChoiceChip(
              label: const Text('Deviation - Yes'),
              selected: true,
              selectedColor: AppColors.brandRed,
              onSelected: (_) {}),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final chipTheme =
        ChipTheme.of(tester.element(find.byType(ChoiceChip).first));
    expect(chipTheme.selectedColor, AppColors.brandTeal);
    final deviation = tester.widget<ChoiceChip>(find.byType(ChoiceChip).last);
    expect(deviation.selectedColor, AppColors.brandRed);
  });
}
