import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/widgets/picker_field.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart'
    show PoultryDesignationRef;
import 'package:fsa_app/features/poultry/presentation/poultry_form_widgets.dart';

/// Every commodity asks the same way.
///
/// The poultry grading screen's dropdown is the one the Agency picked: the
/// options drop over the field as a menu. Eggs, raw and processed meat all
/// share this control now, so a picker cannot look like one thing on one
/// screen and another on the next.
void main() {
  const items = [
    PoultryDesignationRef(id: 1, name: 'Frozen'),
    PoultryDesignationRef(id: 2, name: 'Chilled'),
  ];

  Widget host({
    int? value,
    ValueChanged<int?>? onChanged,
    bool required = false,
    List<PoultryDesignationRef> options = items,
    String? emptyHint,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: poultryDropdown(
              label: 'Storage Method',
              value: value,
              items: options,
              onChanged: onChanged ?? (_) {},
              required: required,
              emptyHint: emptyHint,
            ),
          ),
        ),
      );

  testWidgets('shows the label and a prompt until something is chosen',
      (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Storage Method'), findsOneWidget);
    expect(find.text('Frozen'), findsNothing);
  });

  testWidgets('shows the chosen option', (tester) async {
    await tester.pumpWidget(host(value: 2));
    expect(find.text('Chilled'), findsOneWidget);
  });

  testWidgets('drops a menu over the field and reports the pick',
      (tester) async {
    int? picked;
    await tester.pumpWidget(host(onChanged: (v) => picked = v));

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    // Both options are in the open menu…
    expect(find.text('Frozen'), findsWidgets);
    expect(find.text('Chilled'), findsWidgets);

    await tester.tap(find.text('Frozen').last);
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('a required picker left unchosen fails the form',
      (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: key,
          child: poultryDropdown(
            label: 'Storage Method',
            value: null,
            items: items,
            onChanged: (_) {},
            required: true,
          ),
        ),
      ),
    ));

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('an empty list says why, and cannot be opened', (tester) async {
    await tester.pumpWidget(host(
      options: const [],
      emptyHint: 'Sync to download the list.',
    ));

    expect(find.text('Sync to download the list.'), findsOneWidget);

    // Nothing to choose from, so tapping must not open an empty menu over
    // the field — the hint is the whole answer.
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.text('Frozen'), findsNothing);
    expect(find.text('Chilled'), findsNothing);
  });

  testWidgets('is drawn the way every other picker is drawn', (tester) async {
    await tester.pumpWidget(host(value: 1));

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();

    // Options are typed the shared way, and long ones wrap rather than
    // hiding which one is being chosen behind an ellipsis.
    final option = tester
        .widgetList<Text>(find.text('Chilled'))
        .firstWhere((t) => t.style?.fontSize != null);
    expect(option.style!.fontSize, PickerField.itemStyle.fontSize);
    expect(option.maxLines, PickerField.itemMaxLines);
  });
}
