import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Readings must survive the list changing shape underneath them.
///
/// The mass and albumen fields used to be uncontrolled, so their contents were
/// held against a *position* in the column rather than against an egg. Three
/// ordinary things reshape that column — the "further samples required" banner
/// appearing above it, an egg being deleted from the middle, and a resumed
/// draft refilling it — and each one shifted readings into the wrong egg or
/// wiped them. An inspector losing weights they have already taken, because a
/// warning appeared, is not an acceptable way to be told about the warning.
///
/// These tests use the same widget shape as the real form: a column whose
/// children shift when a banner is inserted.
class _Egg {
  _Egg(this.number);
  final int number;
  final controller = TextEditingController();
  double? massG;
  void dispose() => controller.dispose();
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final eggs = [_Egg(1), _Egg(2), _Egg(3)];
  bool showBanner = false;

  @override
  void dispose() {
    for (final e in eggs) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              // Exactly the shape that caused the bug: a widget that appears
              // above the list and shifts every child down one.
              if (showBanner) const Text('Mean Haugh value is below 70 HU.'),
              for (final e in eggs)
                TextFormField(
                  controller: e.controller,
                  decoration: InputDecoration(labelText: 'Mass ${e.number}'),
                  onChanged: (v) => e.massG = double.tryParse(v),
                ),
              TextButton(
                onPressed: () => setState(() => showBanner = true),
                child: const Text('trigger'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  final removed = eggs.removeAt(0);
                  removed.dispose();
                }),
                child: const Text('delete first'),
              ),
            ],
          ),
        ),
      );
}

void main() {
  group('a warning appearing must not disturb the readings', () {
    testWidgets('every mass stays with its own egg', (tester) async {
      await tester.pumpWidget(const _Harness());

      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 1'), '52');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 2'), '61');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 3'), '48');
      await tester.pump();

      // The banner appears above the list.
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Mean Haugh value is below 70 HU.'), findsOneWidget);
      // …and nothing typed has moved or vanished.
      expect(find.text('52'), findsOneWidget);
      expect(find.text('61'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
    });

    testWidgets('deleting an egg does not shift the others', (tester) async {
      await tester.pumpWidget(const _Harness());

      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 1'), '52');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 2'), '61');
      await tester.enterText(find.widgetWithText(TextFormField, 'Mass 3'), '48');
      await tester.pump();

      await tester.tap(find.text('delete first'));
      await tester.pumpAndSettle();

      // Egg 1 is gone; 2 and 3 keep their own readings rather than sliding up.
      expect(find.text('52'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'Mass 2'),
        findsOneWidget,
      );
      expect(find.text('61'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
    });
  });

  group('the rule behind the warning', () {
    test('the mean is what matters, not the egg just entered', () {
      // One good reading among poor ones does not clear the requirement: the
      // rule is on the average of the sample.
      const mass = 52.3;
      final good = EggRules.haughUnit(albumenHeightMm: 20, massG: mass);
      final poor = EggRules.haughUnit(albumenHeightMm: 3, massG: mass);

      expect(good, greaterThan(70));
      expect(poor, lessThan(70));

      final mean = EggRules.meanHaughUnit([good, ...List.filled(7, poor)]);
      expect(mean, lessThan(70));

      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [good, ...List.filled(7, poor)],
          sampledCount: 8,
        ),
        EggRules.haughAdditionalSampleCount,
      );
    });

    test('a sample that is fresh throughout needs nothing further', () {
      final fine = EggRules.haughUnit(albumenHeightMm: 7, massG: 52.3);
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: List.filled(8, fine),
          sampledCount: 8,
        ),
        0,
      );
    });
  });
}
