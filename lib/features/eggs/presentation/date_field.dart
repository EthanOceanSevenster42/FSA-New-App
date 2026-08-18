import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'required_label.dart';

/// A tappable date input that looks and behaves like the other fields.
///
/// Dates used to be a bare `ListTile`, which on a form of outlined boxes read
/// as a list row rather than something to fill in — easy to scroll past and
/// easy to leave empty. This uses the same [InputDecorator] chrome as the text
/// and dropdown fields, so it sits in the column as an obvious input.
///
/// The value is shown as `Sat, 15/08/2026` — day-first to match the rest of
/// the app, with the weekday spelled out because "is that a Sunday?" is a
/// question inspectors actually ask of a correction deadline.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.isRequired = false,
    this.errorText,
    this.helperText,
    this.emptyHint = 'Tap to choose a date',
  });

  final String label;
  final DateTime? value;

  /// Null is passed when the inspector clears an optional date.
  final ValueChanged<DateTime?> onChanged;

  final DateTime firstDate;
  final DateTime lastDate;
  final bool isRequired;
  final String? errorText;
  final String? helperText;
  final String emptyHint;

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static String format(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '${_weekdays[d.weekday - 1]}, $day/$month/${d.year}';
  }

  Future<void> _pick(BuildContext context) async {
    final initial = value ?? firstDate;
    final picked = await showDatePicker(
      context: context,
      // A stored value outside the allowed window (a record downloaded from
      // elsewhere, say) would make the picker assert, so clamp it.
      initialDate: initial.isBefore(firstDate)
          ? firstDate
          : (initial.isAfter(lastDate) ? lastDate : initial),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: label.toUpperCase(),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final set = value != null;
    return LabelledField(
      label: label,
      isRequired: isRequired,
      child: InkWell(
        onTap: () => _pick(context),
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            errorText: errorText,
            helperText: helperText,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.event_outlined, size: 20),
            suffixIcon: set
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: 'Clear date',
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            set ? format(value!) : emptyHint,
            style: TextStyle(
              fontSize: 15.5,
              // An unset date is a prompt, not a value, so it is styled as
              // placeholder text rather than as something already entered.
              fontWeight: set ? FontWeight.w700 : FontWeight.w400,
              color: set ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
