import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../../core/widgets/required_label.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../domain/poultry_rules.dart';
import '../../../core/widgets/picker_menu_field.dart';

/// The controls every poultry capture screen is built from.
///
/// Shared rather than copied per screen: the tick-lists in particular have a
/// sense that is easy to invert, and one implementation is one place to get it
/// right.

Widget poultrySection(String title) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.3,
          color: AppColors.ink,
        ),
      ),
    );

Widget poultryField(
  TextEditingController controller,
  String label, {
  bool required = false,
  int lines = 1,
  TextInputType? keyboard,
  ValueChanged<String>? onChanged,
  String? helper,

  /// Lets the form tidy what was typed when the field loses focus.
  FocusNode? focusNode,

  /// Whether the inspector may type in it.
  ///
  /// A disabled field is greyed rather than hidden, the way the original
  /// greys one out: the inspector can see the box is there and what it is
  /// waiting for, instead of it appearing from nowhere.
  bool enabled = true,

  /// Shown, but filled in by the form rather than by hand.
  bool readOnly = false,
}) =>
    // Labelled above, as the egg form labels: several of these captions are
    // longer than a handset is wide, and Material's floating label rides up
    // onto the border and ellipsises — "Selection of Restricted Particular
    // Ke…" — which reads as two things overlapping.
    LabelledField(
      label: label,
      isRequired: required,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        maxLines: lines,
        keyboardType: keyboard,
        onChanged: onChanged,
        enabled: enabled,
        readOnly: readOnly,
        decoration: InputDecoration(
          // Height, fill and borders come from the theme, as the egg form's
          // fields take them: a raw inspection and an egg inspection in the
          // same visit should not be two different-looking forms.
          helperText: helper,
          // Three, not two: a line that explains what a field means rather
          // than nudging the format runs longer, and a clipped explanation
          // is worse than none.
          helperMaxLines: 3,
        ),
        validator: required
            ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
            : null,
      ),
    );

/// A picker.
///
/// The options drop over the field as a menu, which is the control the
/// poultry grading screen has always used and the one every commodity now
/// uses: same look, same behaviour, whichever form an inspector opens.
Widget poultryDropdown({
  required String label,
  required int? value,
  required List<PoultryDesignationRef> items,
  required ValueChanged<int?> onChanged,
  bool required = false,
  String? emptyHint,
}) =>
    PickerMenuField<int>(
      label: label,
      value: items.any((i) => i.id == value) ? value : null,
      options: [
        for (final item in items) (value: item.id, text: item.name),
      ],
      onChanged: onChanged,
      isRequired: required,
      emptyHint: emptyHint,
    );

/// A yes/no question on a poultry, raw or PMP form.
///
/// Was an on/off [SwitchListTile]. A thumb to one side says nothing about
/// what it means, so every switch on the forms is now drawn as the checklist
/// rows are — the words, and a YES / NO slide beside them (Ethan,
/// 2026-09-23). One helper, so the twenty-odd questions across the forms
/// changed together.
Widget poultrySwitch({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,

  /// What the answer actually does, where the caption alone does not say.
  /// Several of these captions are the original's own wording and read as
  /// jargon to anyone who has not used it.
  String? helper,
}) =>
    YesNoQuestion(
      label: label,
      helper: helper,
      value: value,
      onChanged: onChanged,
    );

/// Restricted particulars, added from the same dropdown every other picker
/// on the form uses and listed as chips.
Widget poultryRestrictedParticulars({
  required BuildContext context,
  required List<PoultryDesignationRef> options,
  required Set<int> selected,
  required VoidCallback onChanged,
  Set<String>? typed,
  List<String> shared = const [],
  String? note,
}) =>
    RestrictedParticularsPicker<PoultryDesignationRef>(
      options: options,
      optionId: (p) => p.id,
      optionLabel: (p) => p.name,
      selected: selected,
      onChanged: onChanged,
      typed: typed,
      shared: shared,
      note: note,
    );

/// A tick-list, drawn as the egg form draws its requirement lists: the
/// section name in small caps, one dense row per requirement with the
/// regulation underneath, and the tick box on the right in the Agency's red.
///
/// The header states what a tick means, because it means the opposite of
/// what a reader expects from a compliance checklist: the original's column
/// reads "NO Deviation", so a ticked row is the compliant one and an
/// unticked row is the finding.
Widget poultryChecklist({
  required String title,
  required List<PoultryChecklistItemRef> items,
  required Set<int> compliant,
  required ValueChanged<int> onToggle,
  String? note,
}) {
  if (items.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.ink,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          note ?? 'Slide each requirement to Compliant or Deviation.',
          style: TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
      ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    if (_rowNote(item) != null) _rowNote(item)!,
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ComplianceSlider(
                compliant: compliant.contains(item.id),
                onChanged: (_) => onToggle(item.id),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The regulation and, where the row states one, the minimum lettering height.
///
/// The height is what the inspector measures against, so it is shown beside
/// the requirement rather than left in the reference data.
Widget? _rowNote(PoultryChecklistItemRef item) {
  final parts = [
    if (item.regulationReference.isNotEmpty) item.regulationReference,
    if (item.minLetteringHeight.isNotEmpty)
      'Min lettering ${item.minLetteringHeight} mm',
  ];
  if (parts.isEmpty) return null;
  return Text(
    parts.join('  ·  '),
    style: const TextStyle(fontSize: 11.5),
  );
}

/// Shown when the device holds no poultry rules at all.
class PoultryNoRules extends StatelessWidget {
  const PoultryNoRules({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              'This device has no poultry rules yet.\n'
              'Connect once and sync, then the form works offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      );
}

/// A named either/or, where a bare switch would leave the alternative
/// unspoken. The original stores these as a single boolean; naming both
/// states is a readability fix, not a change to what is recorded.
Widget poultryChoice({
  required String label,
  required List<String> options,
  required int selectedIndex,
  required ValueChanged<int> onChanged,

  /// A colour for an option once chosen, where the theme's teal would say
  /// the wrong thing — red for an answer that means a deviation.
  List<Color?>? selectedColors,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < options.length; i++)
                ChoiceChip(
                  label: Text(options[i]),
                  selected: selectedIndex == i,
                  selectedColor:
                      selectedColors == null || i >= selectedColors.length
                          ? null
                          : selectedColors[i],
                  onSelected: (_) => onChanged(i),
                ),
            ],
          ),
        ],
      ),
    );
