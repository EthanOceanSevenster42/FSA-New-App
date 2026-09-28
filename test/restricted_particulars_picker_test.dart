import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/widgets/picker_menu_field.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/restricted_particulars_picker.dart';

/// Restricted particulars are added from a dropdown — the same menu as every
/// other picker on the form — not from a sheet sliding up from the bottom.
/// One the list does not have can be typed in, and stays with the inspection.
void main() {
  const options = [
    (1, 'Free Range/Vryloop'),
    (2, 'Vryloop'),
    (3, 'Extra/Ekstra'),
    (4, 'Other'),
  ];

  Future<({Set<int> selected, Set<String> typed})> pump(WidgetTester tester,
      {Future<void> Function()? onDuplicate, bool allowTyping = true}) async {
    final selected = <int>{};
    final typed = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                RestrictedParticularsPicker<(int, String)>(
              options: options,
              optionId: (o) => o.$1,
              optionLabel: (o) => o.$2,
              selected: selected,
              typed: allowTyping ? typed : null,
              onChanged: () => setState(() {}),
              onDuplicate: onDuplicate,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (selected: selected, typed: typed);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Add restricted particular'));
    await tester.pumpAndSettle();
  }

  Future<void> typeIn(WidgetTester tester, String text) async {
    await open(tester);
    await tester.tap(find.text(RestrictedParticularsPicker.typeItInLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('the particulars drop from the field, not up from the bottom',
      (tester) async {
    await pump(tester);
    expect(find.byType(PickerMenuField<int>), findsOneWidget);
    expect(find.text('Add restricted particular'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await open(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Free Range/Vryloop'), findsWidgets);
    expect(find.text('Other'), findsWidgets);
  });

  testWidgets('picking one lists it as a chip and resets the field',
      (tester) async {
    final state = await pump(tester);
    await open(tester);
    await tester.tap(find.text('Vryloop').last);
    await tester.pumpAndSettle();

    expect(state.selected, {2});
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Add restricted particular'), findsOneWidget,
        reason: 'the field is ready for the next particular');
  });

  testWidgets('the chip takes it off again', (tester) async {
    final state = await pump(tester);
    await open(tester);
    await tester.tap(find.text('Extra/Ekstra').last);
    await tester.pumpAndSettle();
    expect(state.selected, {3});

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(state.selected, isEmpty);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('the same one twice is refused, not listed twice',
      (tester) async {
    var refused = 0;
    final state = await pump(tester, onDuplicate: () async => refused++);
    for (var i = 0; i < 2; i++) {
      await open(tester);
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
    }
    expect(state.selected, {4});
    expect(refused, 1);
    expect(find.byType(InputChip), findsOneWidget);
  });

  group('one the list does not have', () {
    testWidgets('is the last entry of the same menu, and opens a typing box',
        (tester) async {
      await pump(tester);
      await open(tester);
      expect(find.text(RestrictedParticularsPicker.typeItInLabel),
          findsOneWidget);

      await tester.tap(find.text(RestrictedParticularsPicker.typeItInLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Restricted particular'), findsOneWidget);
      expect(find.textContaining('this inspection only'), findsOneWidget,
          reason: 'the inspector is told it does not change the list');
    });

    testWidgets('is kept on the inspection as a chip, marked as typed',
        (tester) async {
      final state = await pump(tester);
      await typeIn(tester, 'Grain fed');

      expect(state.typed, {'Grain fed'});
      expect(state.selected, isEmpty);
      expect(find.widgetWithText(InputChip, 'Grain fed'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget,
          reason: 'a typed one is told apart from a chosen one');
    });

    testWidgets('does not join the list the inspectors choose from',
        (tester) async {
      await pump(tester);
      await typeIn(tester, 'Grain fed');

      await open(tester);
      // The menu still holds the four listed ones and the typing entry.
      final menuTexts = find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      expect(menuTexts, isNot(contains('Grain fed')));
      expect(menuTexts, hasLength(options.length + 1));
    });

    testWidgets('typed the same as a listed one, it is the listed one',
        (tester) async {
      final state = await pump(tester);
      await typeIn(tester, '  vryloop ');

      expect(state.selected, {2});
      expect(state.typed, isEmpty);
      expect(find.widgetWithText(InputChip, 'Vryloop'), findsOneWidget);
    });

    testWidgets('typed twice is refused, whatever the case', (tester) async {
      var refused = 0;
      final state = await pump(tester, onDuplicate: () async => refused++);
      await typeIn(tester, 'Grain fed');
      await typeIn(tester, 'GRAIN FED');

      expect(state.typed, {'Grain fed'});
      expect(refused, 1);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('an empty box, or Cancel, adds nothing', (tester) async {
      final state = await pump(tester);
      await typeIn(tester, '   ');
      expect(state.typed, isEmpty);
      expect(find.byType(InputChip), findsNothing);

      await open(tester);
      await tester.tap(find.text(RestrictedParticularsPicker.typeItInLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Grain fed');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.typed, isEmpty);
    });

    testWidgets('its chip takes it off again', (tester) async {
      final state = await pump(tester);
      await typeIn(tester, 'Grain fed');
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(state.typed, isEmpty);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a picker given no place for typed ones offers none',
        (tester) async {
      await pump(tester, allowTyping: false);
      await open(tester);
      expect(
          find.text(RestrictedParticularsPicker.typeItInLabel), findsNothing);
    });
  });

  group('kept on the record', () {
    test('one per line, and back again', () {
      expect(TypedParticulars.pack({'Grain fed', 'Barn laid'}),
          'Grain fed\nBarn laid');
      expect(TypedParticulars.unpack('Grain fed\nBarn laid'),
          {'Grain fed', 'Barn laid'});
      expect(TypedParticulars.pack(const {}), '');
      expect(TypedParticulars.unpack(''), isEmpty);
    });

    test('a keyword box filled in by an older build comes back as one chip',
        () {
      // The forms used to have a free-text "Selection of Restricted
      // Particular Keywords" box in this column. Whatever was written there
      // is kept, as one typed particular.
      expect(TypedParticulars.unpack('  Free Range, Grain fed  '),
          {'Free Range, Grain fed'});
    });
  });
}
