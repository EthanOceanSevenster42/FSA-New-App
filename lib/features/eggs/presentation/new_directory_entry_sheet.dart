import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/required_label.dart';

/// One field on the sheet.
class DirectoryField {
  const DirectoryField({
    required this.label,
    required this.key,
    this.initial = '',
    this.isRequired = false,
    this.keyboardType,
  });

  final String label;
  final String key;
  final String initial;
  final bool isRequired;
  final TextInputType? keyboardType;
}

/// Captures a client or premises the directory does not hold.
///
/// Inspectors arrive at places that are not on the list — a new packer, a depot
/// nobody has registered. Without this the name goes onto the inspection as
/// loose text and is never seen again, so the next inspector at the same depot
/// types it afresh and slightly differently, and the two visits never line up.
///
/// Returns the entered values, or null if the inspector backed out.
Future<Map<String, String>?> showNewDirectoryEntrySheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<DirectoryField> fields,
  required String saveLabel,
}) async {
  // The boxes belong to the sheet, which disposes them when it leaves the
  // tree. Disposing them here instead tore them down while the sheet was
  // still animating out, and the closing frame then used a controller that
  // was already gone — an assertion in debug, and in release a sheet whose
  // last frame is drawn from freed state.
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => _Sheet(
      title: title,
      subtitle: subtitle,
      fields: fields,
      saveLabel: saveLabel,
    ),
  );
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.saveLabel,
  });

  final String title;
  final String subtitle;
  final List<DirectoryField> fields;
  final String saveLabel;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  String? _issue;

  /// One box per field, owned here so they live exactly as long as the sheet
  /// does — including the frames it takes to animate away.
  late final Map<String, TextEditingController> _boxes = {
    for (final f in widget.fields)
      f.key: TextEditingController(text: f.initial),
  };

  @override
  void dispose() {
    for (final box in _boxes.values) {
      box.dispose();
    }
    super.dispose();
  }

  void _save() {
    for (final f in widget.fields) {
      if (f.isRequired && (_boxes[f.key]?.text.trim() ?? '').isEmpty) {
        setState(() => _issue = '${f.label} is required.');
        return;
      }
    }
    Navigator.of(context).pop({
      for (final f in widget.fields) f.key: _boxes[f.key]!.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sits above the keyboard rather than under it — and above the system
    // navigation bar when the keyboard is down, which is what used to leave
    // Cancel half-hidden behind the gesture bar.
    final media = MediaQuery.of(context);
    final inset = math.max(media.viewInsets.bottom, media.viewPadding.bottom);
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LabelledField(
                  label: f.label,
                  isRequired: f.isRequired,
                  child: TextField(
                    controller: _boxes[f.key],
                    keyboardType: f.keyboardType,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 15.5),
                  ),
                ),
              ),
            if (_issue != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _issue!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPrimary,
                  ),
                ),
              ),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(widget.saveLabel),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
