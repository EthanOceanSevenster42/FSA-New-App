import 'package:flutter/material.dart';

import 'date_field.dart';

/// The "Correct by/on Date" on a rejection.
///
/// Opens on the date FSA-SOP-APS-001 Annexure C gives from the deviations,
/// and the inspector may move it to any later day — a correction is always
/// due in the future, never on a day already gone. Where the annexure gives
/// no period to move (nothing to correct yet, or an immediate rectification)
/// the date is shown but locked. Clearing a chosen date puts the annexure's
/// back.
class CorrectByDateField extends StatelessWidget {
  const CorrectByDateField({
    super.key,
    required this.value,
    required this.sopDate,
    required this.onChanged,
    this.helperText,
  });

  /// The date the rejection carries now.
  final DateTime? value;

  /// The date the annexure gives from the deviations.
  final DateTime? sopDate;

  final ValueChanged<DateTime?> onChanged;
  final String? helperText;

  /// Whether [date] is after today — the only dates a correction may be due.
  static bool isFuture(DateTime? date) =>
      date != null && date.isAfter(DateUtils.dateOnly(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final field = DateField(
      label: 'Correct by/on Date',
      value: value,
      firstDate: DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1)),
      helperText: helperText,
      emptyHint: 'Set from the deviations ticked',
      onChanged: (d) => onChanged(d ?? sopDate),
    );
    return isFuture(sopDate) ? field : IgnorePointer(child: field);
  }
}
