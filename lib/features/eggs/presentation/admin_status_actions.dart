import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bulk upload-status corrections for the selected date, for administrators.
///
/// These change what the device *believes* about records already sent. They
/// exist for the two ways that belief goes wrong: the server lost a batch
/// (re-queue it) or acknowledged one that never got recorded (mark it sent so
/// it is not duplicated). Both are confirmed before they run, and both report
/// how many records actually changed.
class AdminStatusActions extends StatelessWidget {
  const AdminStatusActions({
    super.key,
    required this.dateLabel,
    required this.busy,
    required this.onRequeue,
    required this.onMarkSent,
  });

  final String dateLabel;
  final bool busy;
  final VoidCallback onRequeue;
  final VoidCallback onMarkSent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.noticeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.noticeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  size: 18, color: AppColors.noticeForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ADMINISTRATOR — $dateLabel',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: AppColors.noticeForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Corrects upload status only. Nothing is sent or deleted.',
            style: TextStyle(
                fontSize: 12, color: AppColors.noticeForeground, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: busy ? null : onRequeue,
                    child: const Text(
                      'Re-queue',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: busy ? null : onMarkSent,
                    child: const Text(
                      'Mark as sent',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Confirms a bulk status change. Returns false when the user backs out.
Future<bool> confirmStatusChange(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}
