import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/app_update_service.dart';

/// Offers the new build and installs it, on the sign-in screen.
///
/// It is deliberately one dialog with one button: an inspector standing at a
/// counter should not be asked to understand versions. It says a new version
/// is ready, downloads it while they watch, and hands it to Android's
/// installer. Everything can be dismissed — a handset on one bar of signal
/// must still be able to get to work.
Future<void> showAppUpdate(
  BuildContext context,
  AppUpdateService service,
  AppUpdate update,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppUpdateDialog(service: service, update: update),
  );
}

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.service, required this.update});

  final AppUpdateService service;
  final AppUpdate update;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  double _progress = 0;
  bool _working = false;
  String? _error;

  /// Whether the one thing standing between this handset and the update is
  /// Android's per-app install switch, which the inspector can be taken
  /// straight to rather than told to hunt for.
  bool _needsInstallPermission = false;

  /// Opens Android's own switch for this app, because an inspector told to
  /// find it in Settings often will not — and a handset that cannot install
  /// is one no release can reach.
  Future<void> _allowInstalls() async {
    final opened = await widget.service.openInstallSettings();
    if (!mounted || opened) return;
    // No such screen on this handset; fall back to telling them where it is.
    setState(() {
      _error = 'Open Settings › Apps › FSA Inspector › Install unknown apps '
          'and allow it, then try again. The update is already downloaded.';
      _needsInstallPermission = false;
    });
  }

  Future<void> _update() async {
    setState(() {
      _working = true;
      _error = null;
      _needsInstallPermission = false;
      _progress = 0;
    });
    try {
      final apk = await widget.service.download(widget.update, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      // Android asks the inspector to allow installs from this app once,
      // per source. Saying so beforehand is better than an installer that
      // appears to do nothing.
      if (!await widget.service.canInstall()) {
        if (!mounted) return;
        setState(() {
          _working = false;
          _needsInstallPermission = true;
          _error = 'This device has not been allowed to install apps from the '
              'FSA Inspector. Allow it once below, then try again — the '
              'update is already downloaded.';
        });
        // Firing the installer anyway is what put Android's own "not
        // allowed" dialog in front of the inspector with nothing useful
        // to do about it.
        return;
      }
      final started = await widget.service.install(apk);
      if (!mounted) return;
      if (!started) {
        setState(() {
          _working = false;
          _error = 'The installer would not open. The update is downloaded; '
              'try again, or carry on and update later.';
        });
        return;
      }
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'The update could not be downloaded. $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating the app'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A newer version of FSA Inspector is ready — '
            '${widget.update.display}.',
            style: const TextStyle(fontSize: 14.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            _working
                ? 'Downloading — keep this screen open.'
                : 'It downloads here; there is no Play Store on these '
                    'handsets.',
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          if (_working) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text(
              _progress == 0 ? 'Starting…' : '${(_progress * 100).round()}%',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.brandRed, height: 1.35),
            ),
          ],
          if (_needsInstallPermission && !_working) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _allowInstalls,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('ALLOW INSTALLS'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working
              ? null
              : () async {
                  // Remembered, so opening the app does not ask again for
                  // the same build.
                  await widget.service.decline(widget.update);
                  if (context.mounted) Navigator.of(context).pop();
                },
          child: const Text('LATER'),
        ),
        FilledButton(
          onPressed: _working ? null : _update,
          child: Text(_error == null ? 'UPDATE NOW' : 'TRY AGAIN'),
        ),
      ],
    );
  }
}
