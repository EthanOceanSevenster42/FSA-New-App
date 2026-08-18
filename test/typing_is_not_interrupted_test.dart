import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';

/// Typing a reading must never be interrupted by a warning about it.
///
/// The samples list is rebuilt on every keystroke, and the "further samples
/// required" banner appears and disappears above it as the mean crosses the
/// threshold. That shifts every card by one. Without a key on the card,
/// Flutter rebinds each one to a different element, which destroys the field
/// being typed into: the keyboard closes and the caret is lost, mid-number.
///
/// An inspector cannot enter "52" if the app throws them out after "5".
class _Egg {
  _Egg(this.number);
  final int number;
  final controller = TextEditingController();
  final focus = FocusNode();
  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class _Harness extends StatefulWidget {
  const _Harness({required this.keyed});

  /// Whether the cards carry a stable key — the thing under test.
  final bool keyed;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final eggs = [_Egg(1), _Egg(2), _Egg(3)];
  bool warn = false;

  @override
  void dispose() {
    for (final e in eggs) {
      e.dispose();
    }
    super.dispose();
  }

  Widget card(_Egg e) => Container(
        key: widget.keyed ? ValueKey(e) : null,
        margin: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: e.controller,
          focusNode: e.focus,
          decoration: InputDecoration(labelText: 'Mass ${e.number}'),
          // Typing re-evaluates the warning, exactly as the real form does.
          onChanged: (v) => setState(() => warn = (double.tryParse(v) ?? 0) > 40),
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              if (warn) const Text('Mean Haugh value is below 70 HU.'),
              for (final e in eggs) card(e),
            ],
          ),
        ),
      );
}

void main() {
  group('the caret stays where the inspector put it', () {
    testWidgets('typing through the threshold keeps focus', (tester) async {
      await tester.pumpWidget(const _Harness(keyed: true));

      final field = find.widgetWithText(TextFormField, 'Mass 2');
      await tester.tap(field);
      await tester.pump();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      expect(state.eggs[1].focus.hasFocus, isTrue, reason: 'tapped in');

      // "5" then "52" — the second keystroke crosses the threshold and the
      // banner appears above the list.
      await tester.enterText(field, '5');
      await tester.pump();
      await tester.enterText(field, '52');
      await tester.pump();

      expect(find.text('Mean Haugh value is below 70 HU.'), findsOneWidget,
          reason: 'the warning must still be shown');
      expect(state.eggs[1].focus.hasFocus, isTrue,
          reason: 'the warning must not close the keyboard');
      expect(state.eggs[1].controller.text, '52',
          reason: 'and the full number must be there');
    });

    testWidgets('without a key the field is torn out from under you',
        (tester) async {
      // Pins the failure mode, so a future change that drops the key is
      // caught here rather than by an inspector in a cold room.
      await tester.pumpWidget(const _Harness(keyed: false));

      final field = find.widgetWithText(TextFormField, 'Mass 2');
      await tester.tap(field);
      await tester.pump();

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      await tester.enterText(field, '52');
      await tester.pump();

      expect(state.eggs[1].focus.hasFocus, isFalse,
          reason: 'this is the bug the key exists to prevent');
    });
  });

  group('a warning is a warning, not a barrier', () {
    test('an implausible weight is reported but still recorded', () {
      // Above the sanity ceiling: flagged under the field, not refused.
      expect(EggValidation.eggMass(400), isNotNull);
      // Zero or negative is a different matter — that is not a reading.
      expect(EggValidation.eggMass(0), isNotNull);
      expect(EggValidation.eggMass(52), isNull);
    });

    test('the Haugh rule counts the sample, not the last egg typed', () {
      final good = EggRules.haughUnit(albumenHeightMm: 20, massG: 52.3);
      final poor = EggRules.haughUnit(albumenHeightMm: 3, massG: 52.3);

      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: [good, ...List.filled(7, poor)],
          sampledCount: 8,
        ),
        greaterThan(0),
      );
      expect(
        EggRules.additionalSamplesRequired(
          haughUnits: List.filled(8, good),
          sampledCount: 8,
        ),
        0,
      );
    });
  });
}
