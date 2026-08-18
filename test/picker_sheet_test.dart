import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/presentation/picker_sheet.dart';

/// Choosing one option from a sheet, rather than a menu drawn over the form.
void main() {
  const trays = ['6-egg tray', '12-egg tray', '18-egg tray', '24-egg tray'];

  Future<String?> open(
    WidgetTester tester, {
    List<String> items = trays,
    String? selected,
    String Function(String)? subtitle,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPickerSheet<String>(
                    context: context,
                    title: 'Tray packaging size',
                    items: items,
                    itemLabel: (t) => t,
                    itemSubtitle: subtitle,
                    selected: selected,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  group('the sheet', () {
    testWidgets('names what is being chosen', (tester) async {
      await open(tester);
      // A dropdown menu showed a bare list with no indication of which field
      // it belonged to.
      expect(find.text('Tray packaging size'), findsOneWidget);
    });

    testWidgets('lists every option', (tester) async {
      await open(tester);
      for (final tray in trays) {
        expect(find.text(tray), findsOneWidget);
      }
    });

    testWidgets('ticks the current choice', (tester) async {
      await open(tester, selected: '18-egg tray');
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('nothing is ticked when nothing is chosen yet',
        (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('shows a second line when one is supplied', (tester) async {
      await open(tester, subtitle: (t) => 'holds ${t.split('-').first} eggs');
      expect(find.text('holds 6 eggs'), findsOneWidget);
    });
  });

  group('choosing', () {
    testWidgets('tapping an option returns it and closes the sheet',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('12-egg tray'));
      await tester.pumpAndSettle();

      // The sheet is gone.
      expect(find.text('Tray packaging size'), findsNothing);
    });

    testWidgets('closing without choosing returns nothing', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Tray packaging size'), findsNothing);
      // The field keeps whatever it had; nothing was selected by opening.
      expect(find.text('6-egg tray'), findsNothing);
    });
  });

  testWidgets('a long list scrolls instead of covering the screen',
      (tester) async {
    final many = [for (var i = 1; i <= 60; i++) 'Option $i'];
    await open(tester, items: many);

    // Capped at 70% of the viewport, so the page behind stays visible and it
    // never reads as a second screen drawn over the first.
    final sheet = tester.getRect(find.byType(ListView));
    expect(sheet.height, lessThan(800 * 0.75));

    expect(find.text('Option 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Option 60'), 200);
    expect(find.text('Option 60'), findsOneWidget);
  });
}
