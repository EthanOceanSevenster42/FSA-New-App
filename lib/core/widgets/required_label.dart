import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Field label carrying a red asterisk when the field must be filled in.
///
/// The marker is a widget rather than an asterisk inside the label string, so
/// screen readers announce "required" instead of reading a stray punctuation
/// mark.
class RequiredLabel extends StatelessWidget {
  const RequiredLabel({
    super.key,
    required this.label,
    required this.isRequired,
  });

  final String label;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    if (!isRequired) return Text(label);
    return Semantics(
      label: '$label, required',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: label,
          children: const [
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: AppColors.brandRed,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A form field with its label on its own line above the control.
///
/// The fields are grey-filled boxes on a white page. Material's floating label
/// would ride up onto the top border when the field is focused or filled,
/// leaving the text half over the fill and half over the page — it reads as
/// two things overlapping, and the longer the label the worse it looks.
///
/// Labelling above avoids that entirely, keeps the label at a constant size
/// and position rather than animating between two, and matches the sign-in
/// screen, which already labels this way.
class LabelledField extends StatelessWidget {
  const LabelledField({
    super.key,
    required this.label,
    required this.child,
    this.isRequired = false,
  });

  final String label;
  final Widget child;
  final bool isRequired;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                child: RequiredLabel(label: label, isRequired: isRequired),
              ),
            ),
            child,
          ],
        ),
      );
}

/// Explains the asterisk once, at the top of a step that has required fields.
class RequiredLegend extends StatelessWidget {
  const RequiredLegend({super.key, this.noun = 'inspection'});

  final String noun;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            const Text(
              '*',
              style: TextStyle(
                color: AppColors.brandRed,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Required before this $noun can be saved',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          ],
        ),
      );
}
