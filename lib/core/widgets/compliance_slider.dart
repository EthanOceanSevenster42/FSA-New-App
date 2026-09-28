import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A two-position slide with a word on each side; the side in force is lit.
///
/// The app asks two kinds of two-way question and they are drawn the same
/// way. A checklist row is COMPLIANT or DEVIATION. Everything else that used
/// to be an on/off switch — "Is the outer labelling available", "No Haugh
/// readings required", "Is Sampled" — is a YES or a NO, and an inspector
/// reading a form should not have to work out which way a thumb means yes.
///
/// Both answers are always drawn, and the one in force is the one lit. Slide
/// or tap either way; the side you land on is the answer, rather than a
/// toggle that depends on remembering the current state. Compact enough for
/// a list twenty rows long.
class TwoWaySlider extends StatelessWidget {
  const TwoWaySlider({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftOn,
    required this.onChanged,
    this.leftColor = AppColors.brandPrimary,
    this.rightColor = AppColors.brandRed,
    this.enabled = true,
  });

  final String leftLabel;
  final String rightLabel;

  /// Whether the left-hand answer is the one in force.
  final bool leftOn;

  /// Called with `true` when the left side is chosen, `false` for the right.
  /// Null draws the answer but lets nobody move it.
  final ValueChanged<bool>? onChanged;

  final Color leftColor;
  final Color rightColor;

  /// A submitted record still shows its answers; it just cannot be moved.
  final bool enabled;

  static const width = 172.0;
  static const height = 32.0;
  static const _pad = 2.0;

  bool get _live => enabled && onChanged != null;

  @override
  Widget build(BuildContext context) {
    const half = (width - _pad * 2) / 2;
    final lit = leftOn ? leftColor : rightColor;
    return Opacity(
      opacity: _live ? 1 : 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping a side chooses that side, rather than toggling whatever is
        // there: on a long list an inspector reads the answer they want and
        // taps it, and a toggle would make that depend on the current state.
        onTapUp: !_live
            ? null
            : (details) {
                final wantsLeft = details.localPosition.dx < width / 2;
                if (wantsLeft != leftOn) onChanged!(wantsLeft);
              },
        // And it really slides, which is what a thumb this shape invites.
        onHorizontalDragEnd: !_live
            ? null
            : (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity == 0) return;
                final wantsLeft = velocity < 0;
                if (wantsLeft != leftOn) onChanged!(wantsLeft);
              },
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    alignment:
                        leftOn ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      width: half,
                      height: height - _pad * 2,
                      decoration: BoxDecoration(
                        color: lit,
                        borderRadius:
                            BorderRadius.circular((height - _pad * 2) / 2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _side(leftLabel, on: leftOn),
                      _side(rightLabel, on: !leftOn),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _side(String text, {required bool on}) => Expanded(
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: on ? Colors.white : AppColors.muted,
            ),
          ),
        ),
      );
}

/// A two-position slide for one checklist requirement: compliant on the
/// left, deviation on the right.
///
/// The checklists used a single tick box, which said the wrong thing twice
/// over. An empty box reads as "not looked at yet", not "this failed", and
/// the lists had to carry a line of small print — "Leave unticked where
/// there is a deviation" — to undo that impression. On a sheet the office
/// reads as a compliance record, a row that has never been touched and a
/// row that failed cannot look identical.
class ComplianceSlider extends StatelessWidget {
  const ComplianceSlider({
    super.key,
    required this.compliant,
    required this.onChanged,
    this.enabled = true,
  });

  /// Whether this requirement is met. The deviation side is the other one.
  final bool compliant;

  final ValueChanged<bool> onChanged;

  /// A submitted record still shows its answers; it just cannot be moved.
  final bool enabled;

  @override
  Widget build(BuildContext context) => TwoWaySlider(
        leftLabel: 'COMPLIANT',
        rightLabel: 'DEVIATION',
        leftOn: compliant,
        onChanged: onChanged,
        enabled: enabled,
      );
}

/// A yes-or-no answer, drawn the way a checklist row is.
///
/// "No" is an answer, not a deviation, so it is lit in ink rather than the
/// red the checklist keeps for a failed requirement: a form with three
/// honest noes on it must not look like one with three findings.
class YesNoSlider extends StatelessWidget {
  const YesNoSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;

  /// Null draws the answer but lets nobody move it — for a question that,
  /// once answered yes, the original does not let be taken back.
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TwoWaySlider(
        leftLabel: 'YES',
        rightLabel: 'NO',
        leftOn: value,
        onChanged: onChanged,
        rightColor: AppColors.ink,
        enabled: enabled,
      );
}

/// A question with a yes/no slide beside it — what every on/off switch on
/// the forms has become.
///
/// The switches were [SwitchListTile]s, and a thumb to the right says
/// nothing about what it means: an inspector has to know that "No Haugh
/// readings required" lit means readings are *not* wanted. A YES and a NO
/// beside the words say it. Laid out exactly as a checklist row is — the
/// words expanded on the left, the slide on the right — so the whole form
/// reads as one kind of thing.
class YesNoQuestion extends StatelessWidget {
  const YesNoQuestion({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.bold = false,
    this.enabled = true,
  });

  final String label;

  /// What the answer does, where the caption alone does not say.
  final String? helper;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool bold;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (helper != null && helper!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        helper!,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            YesNoSlider(value: value, onChanged: onChanged, enabled: enabled),
          ],
        ),
      );
}
