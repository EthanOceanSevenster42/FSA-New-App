import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../../core/widgets/missing_fields.dart';
import '../../../core/widgets/required_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../../sync/auto_sync.dart';
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

  /// Marked required, but checked by the form itself rather than by
  /// `validate()` — for a box that is emptied again once its entry is added
  /// to a list, such as the QUID injector name.
  bool markRequired = false,

  /// Caps how many characters may be typed. The weight fields use it so a
  /// value can never exceed the server's limit and fail on sync (Ethan,
  /// 2026-10-04).
  int? maxLength,
}) =>
    // Labelled above, as the egg form labels: several of these captions are
    // longer than a handset is wide, and Material's floating label rides up
    // onto the border and ellipsises — "Selection of Restricted Particular
    // Ke…" — which reads as two things overlapping.
    LabelledField(
      label: label,
      isRequired: required || markRequired,
      // Builder so the field can see whether its [MissingFieldAnchor] has
      // flagged it, and draw its own border red.
      child: Builder(
        builder: (context) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        maxLines: lines,
        keyboardType: keyboard,
        inputFormatters: maxLength == null
            ? null
            : [LengthLimitingTextInputFormatter(maxLength)],
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
          errorText: MissingFieldScope.errorOf(context),
        ),
        validator: required
            ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
            : null,
        ),
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
/// Shown when a form's reference data is not on the device yet, or a load
/// stalled. It does not merely tell the inspector to go and sync: it starts a
/// background sync itself the moment it appears, so on signal the data arrives
/// with nothing pressed, and — when given [onRetry] — rebuilds the form the
/// instant the sync lands. The button is a fallback, not the normal path
/// (Ethan, 2026-10-14).
class PoultryNoRules extends StatefulWidget {
  const PoultryNoRules({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  State<PoultryNoRules> createState() => _PoultryNoRulesState();
}

class _PoultryNoRulesState extends State<PoultryNoRules> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AutoSync.instance.completedPasses.addListener(_onSynced);
    unawaited(AutoSync.instance.kick());
  }

  void _onSynced() => widget.onRetry?.call();

  @override
  void dispose() {
    AutoSync.instance.completedPasses.removeListener(_onSynced);
    super.dispose();
  }

  Future<void> _tryNow() async {
    setState(() => _busy = true);
    await AutoSync.instance.kick();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              'The rules for this form are still reaching this device.\n'
              'They download on their own when you have signal, then the form '
              'works offline — no need to sync by hand.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _tryNow,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(_busy ? 'Downloading…' : 'Try again'),
            ),
          ],
        ),
      );
}

/// "What are you testing for?" as an in-place dropdown multi-select, built the
/// same way as the Laboratory Testing Category picker (Ethan, 2026-10-06): a
/// summary row that opens to tick Fat / Protein / Calcium / Dna. Stateful so
/// each form need not carry the open/closed flag.
class PoultryTestDropdown extends StatefulWidget {
  const PoultryTestDropdown({
    super.key,
    required this.label,
    required this.options,
  });

  final String label;
  final List<({String label, bool selected, VoidCallback onToggle})> options;

  @override
  State<PoultryTestDropdown> createState() => _PoultryTestDropdownState();
}

class _PoultryTestDropdownState extends State<PoultryTestDropdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final picked = [
      for (final o in widget.options)
        if (o.selected) o.label,
    ].join(', ');
    return LabelledField(
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: Icon(
                    _open ? Icons.arrow_drop_up : Icons.arrow_drop_down),
              ),
              child: Text(
                picked.isEmpty ? 'Select Tests' : picked,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: picked.isEmpty ? AppColors.muted : AppColors.ink,
                ),
              ),
            ),
          ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  for (final o in widget.options)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.brandPrimary,
                      value: o.selected,
                      // The flag lives in the form; toggling it rebuilds the
                      // form, which rebuilds this list with the new value.
                      onChanged: (_) => o.onToggle(),
                      title: Text(o.label,
                          style:
                              const TextStyle(fontSize: 15, height: 1.35)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
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
