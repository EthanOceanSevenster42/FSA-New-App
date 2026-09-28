import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'missing_fields.dart';
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
  DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    DateTime? firstDate,
    DateTime? lastDate,
    this.isRequired = false,
    this.errorText,
    this.helperText,
    this.emptyHint = 'Tap to choose a date',
  })  : firstDate = firstDate ?? _openFrom(),
        lastDate = lastDate ?? _openTo();

  /// Where the calendar opens when a caller sets no bounds: five years
  /// either side of today.
  ///
  /// Every date an inspector enters is one read off a pack or a document —
  /// a best-before, a packed date, the date on a record being verified — and
  /// the form's job is to take it down as written. The bounds used to differ
  /// from field to field (tomorrow onwards here, two years back there), and
  /// each was a way the form could refuse what the pack said. One open
  /// window on every calendar (Ethan, 2026-09-23); a caller that truly needs
  /// a narrower one still passes its own.
  static DateTime _openFrom() => DateTime(DateTime.now().year - 5);
  static DateTime _openTo() => DateTime(DateTime.now().year + 5, 12, 31);

  /// `dd/MM/yyyy`, the form the meat forms keep a packed date in.
  static String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The date a `dd/MM/yyyy` string holds, or null for anything else — an
  /// old free-typed value stays in the box as text rather than being lost.
  static DateTime? parseDmy(String text) {
    final parts = text.trim().split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null || y < 1900) return null;
    final date = DateTime(y, m, d);
    return date.month == m && date.day == d ? date : null;
  }

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
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String format(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '${_weekdays[d.weekday - 1]}, $day/$month/${d.year}';
  }

  Future<void> _pick(BuildContext context) async {
    // Nothing picked yet opens on today rather than on the earliest date
    // allowed: a verification date two years back had the inspector paging
    // forward month by month to reach last week. Where today is outside the
    // window — a deadline, which cannot be earlier than tomorrow — the
    // clamp below moves it to the nearest date the field will take.
    final initial = value ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // A stored value outside the allowed window (a record downloaded from
      // elsewhere, say) would make the picker assert, so clamp it.
      initialDate: initial.isBefore(firstDate)
          ? firstDate
          : (initial.isAfter(lastDate) ? lastDate : initial),
      firstDate: firstDate,
      lastDate: lastDate,
      // Not uppercased: the long field names only fit the header in their
      // natural case at the themed size.
      helpText: label,
      // Material's calendar is one fixed size, which is small on a tablet:
      // drawn bigger there to use the width (Ethan, 2026-09-25). A phone
      // keeps it as it is.
      builder: (context, child) {
        final scale = calendarScale(MediaQuery.sizeOf(context).width);
        if (child == null || scale == 1) return child ?? const SizedBox();
        return Transform.scale(scale: scale, child: child);
      },
    );
    if (picked != null) onChanged(picked);
  }

  /// How much bigger the calendar is drawn than Material draws it: as it is
  /// on a phone, up to half as big again on a tablet, from the screen width.
  static double calendarScale(double screenWidth) =>
      (screenWidth / 720).clamp(1.0, 1.5).toDouble();

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
            errorText: errorText ?? MissingFieldScope.errorOf(context),
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
