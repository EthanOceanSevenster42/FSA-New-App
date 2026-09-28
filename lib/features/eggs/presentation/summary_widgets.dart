import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';

import '../../../core/theme/app_theme.dart';

/// Presentation pieces shared by the inspection and direction summary screens.

const _uploadedGreen = Color(0xFF2E7D32);
const _uploadedGreenBg = Color(0xFFEAF5EB);

String orDash(String value) => value.trim().isEmpty ? '—' : value;

String _two(int v) => v.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)} at ${_two(d.hour)}:${_two(d.minute)}';

/// Just the clock time. The management lists are already filtered to one date,
/// so repeating it on every card is noise — the time is what tells one visit
/// from another.
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

class SummaryHeader extends StatelessWidget {
  const SummaryHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.uploaded,
    required this.status,
  });

  final String title;
  final String subtitle;
  final bool uploaded;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(
              text: uploaded ? 'Uploaded' : 'Not yet sent',
              foreground:
                  uploaded ? _uploadedGreen : AppColors.noticeForeground,
              background:
                  uploaded ? _uploadedGreenBg : AppColors.noticeBackground,
            ),
            if (status.isNotEmpty && status != 'completed')
              _Pill(
                text: status[0].toUpperCase() + status.substring(1),
                foreground: AppColors.muted,
                background: AppColors.surfaceAlt,
              ),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: foreground,
          ),
        ),
      );
}

class SummarySection extends StatelessWidget {
  const SummarySection({
    super.key,
    required this.title,
    required this.children,
    this.accent,
  });

  final String title;
  final List<Widget> children;

  /// Overrides the heading and border colour. A rejection and the deviations
  /// behind it are red wherever they appear, so a summary that carries them
  /// is not read as one more teal block of detail.
  final Color? accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                color: accent ?? AppColors.brandTeal,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: accent ?? AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      );
}

class SummaryField extends StatelessWidget {
  const SummaryField({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.emphasise = false,
    this.warn = false,
    this.mono = false,
  });

  final String label;
  final String value;
  final String? note;
  final bool emphasise;
  final bool warn;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.muted, height: 1.35),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: emphasise ? 15.5 : 13.5,
                    height: 1.35,
                    fontWeight: emphasise ? FontWeight.w900 : FontWeight.w400,
                    fontFamily: mono ? 'monospace' : null,
                    color: warn ? AppColors.brandRed : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 108, top: 2),
              child: Text(
                note!,
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.noticeForeground),
              ),
            ),
        ],
      ),
    );
  }
}

class SummaryBullet extends StatelessWidget {
  const SummaryBullet({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 5, right: 10),
              child: Icon(Icons.circle, size: 6, color: AppColors.brandRed),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 13.5, color: AppColors.ink, height: 1.35),
              ),
            ),
          ],
        ),
      );
}

class SummaryEmpty extends StatelessWidget {
  const SummaryEmpty({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 13.5, color: AppColors.muted),
      );
}

/// What a direction covers, in words.
///
/// One notice may carry either part or both, so this is not a type but a
/// description of the parts present.
String directionParts(EggDirection d) {
  if (d.qualityPart && d.labellingPart) return 'Quality and labelling';
  if (d.qualityPart) return 'Quality';
  if (d.labellingPart) return 'Labelling';
  return '—';
}
