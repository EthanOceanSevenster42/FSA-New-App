import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/poultry_rules.dart';

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
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: required
            ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null
            : null,
      ),
    );

/// A picker.
///
/// The menu is capped and its items wrap to two lines: several designations
/// and every direction remark are longer than a handset is wide, and an
/// unbounded menu of 26 rows covers the field it belongs to.
Widget poultryDropdown({
  required String label,
  required int? value,
  required List<PoultryDesignationRef> items,
  required ValueChanged<int?> onChanged,
  bool required = false,
  String? emptyHint,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // alignedDropdown keeps the open menu exactly as wide as the field.
      // Without it, Material inflates the menu 16dp past the field on both
      // sides, which on a full-width field puts it hard against the screen
      // edges.
      child: ButtonTheme(
        alignedDropdown: true,
        child: DropdownButtonFormField<int>(
          initialValue: items.any((i) => i.id == value) ? value : null,
          isExpanded: true,
          menuMaxHeight: 360,
          // The open menu must read as a card, not a full-bleed sheet:
          // rounded corners, and a raised surface tone. Left at the theme
          // default, the menu paints in the page's own colour, so in dark
          // mode its edges vanish and the options look like loose text
          // running into the screen corners.
          borderRadius: BorderRadius.circular(12),
          dropdownColor: AppColors.surfaceAlt,
          elevation: 4,
          decoration: InputDecoration(
            labelText: required ? '$label *' : label,
            border: const OutlineInputBorder(),
            isDense: true,
            // Says why the list is empty rather than showing a dead control.
            helperText: items.isEmpty ? emptyHint : null,
          ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          ],
          onChanged: items.isEmpty ? null : onChanged,
          validator: required ? (v) => v == null ? 'Required' : null : null,
        ),
      ),
    );

Widget poultrySwitch({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) =>
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onChanged: onChanged,
    );

/// A tick-list.
///
/// The header states what a tick means, because it means the opposite of what
/// a reader expects from a compliance checklist: the original's column reads
/// "NO Deviation", so a ticked row is the compliant one and an unticked row is
/// the finding.
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
      poultrySection(title),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          note ?? 'Tick where there is NO deviation.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.noticeForeground,
          ),
        ),
      ),
      for (final item in items)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: compliant.contains(item.id),
          title: Text(
            item.description,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: _rowNote(item),
          onChanged: (_) => onToggle(item.id),
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
    parts.join('   •   '),
    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
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
