import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// What became of a record the moment it was saved.
enum SavedState {
  /// On the server. Nothing further is needed.
  sent,

  /// On the device, waiting for a signal. The sync service will send it.
  queued,

  /// On the device, but this handset has never completed an online sign-in, so
  /// there is nothing to authenticate an upload with. Retrying will not help.
  needsSignIn,

  /// The server understood the record and refused it. Retrying will not help
  /// either, and leaving it silently "pending" would hide that.
  rejected,
}

/// Confirms a record was captured, and says plainly what happened to it.
///
/// The distinction matters in the field: "saved" and "sent" are different
/// promises, and an inspector who assumes the first means the second will not
/// go back for the record when the upload never happens. Equally, telling
/// someone their work "will upload as soon as you are back online" when they
/// are online and it was refused is worse than saying nothing.
Future<void> showSavedDialog(
  BuildContext context, {
  required SavedState state,
  required String noun,
}) {
  final capitalised = noun[0].toUpperCase() + noun.substring(1);

  final (IconData icon, Color colour) = switch (state) {
    SavedState.sent => (Icons.cloud_done_outlined, const Color(0xFF2E7D32)),
    SavedState.queued => (Icons.save_outlined, AppColors.brandTeal),
    SavedState.needsSignIn => (
        Icons.cloud_off_outlined,
        AppColors.noticeForeground
      ),
    SavedState.rejected => (Icons.error_outline, AppColors.brandPrimary),
  };

  final message = switch (state) {
    // Nothing more to say: it is saved and it is on the server. An inspector
    // does not need a paragraph about a job that worked.
    SavedState.sent => 'The $noun has been sent to the server.',
    SavedState.queued => 'The $noun is saved on this device and will be sent '
        'automatically. You do not need to do anything.',
    SavedState.needsSignIn => 'The $noun is saved on this device, but it '
        'cannot be sent yet: no one has signed in on this handset while '
        'online. Sign out and sign in again with a signal, and it will go up.',
    SavedState.rejected => 'The $noun is saved on this device, but the server '
        'would not accept it. This usually means the reference data on this '
        'handset came from a different server — sign out and sign in again to '
        'refresh it, then resend from Inspection Management.',
  };

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon, size: 34, color: colour),
      title: Text('$capitalised saved'),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
