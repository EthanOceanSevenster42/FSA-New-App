import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Takes a photograph without handing the screen to the phone's camera app.
///
/// Launching the camera app is what was killing this one. Measured on an
/// inspector handset: the camera costs ~97 MB, and free memory halves from
/// 640 MB to 330 MB the moment it opens. This app is backgrounded by the
/// handover, which drops it to `cached` — and with an inspection open it is
/// then the largest reclaimable process on the device at ~196 MB. Android's
/// low-memory killer takes exactly that, so the inspector comes back to a
/// restarted app with the photograph they had just framed gone. The process
/// exit records show it plainly: `reason=3 (LOW_MEMORY) … state=empty`.
///
/// Capturing here keeps the app in the foreground, which is the state the
/// killer reaches last, and skips the app switch altogether — so a photograph
/// is also quicker to take than it was.
///
/// The preview buffers mean this app uses *more* memory while the camera is
/// up, not less. That is the trade being made deliberately: a larger
/// foreground process is far safer than a smaller cached one.
Future<String?> capturePhoto(
  BuildContext context, {
  required String title,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => _CameraPage(title: title),
      fullscreenDialog: true,
    ),
  );
}

class _CameraPage extends StatefulWidget {
  const _CameraPage({required this.title});

  /// What the inspector is being asked to photograph, shown over the preview.
  final String title;

  @override
  State<_CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<_CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Hand the camera and its buffers straight back; holding them after the
    // page is gone would waste the memory this whole change is about.
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Android revokes the camera when the app loses the screen, so release
        // it rather than come back to a dead controller.
        if (controller == null) return;
        setState(() => _controller = null);
        unawaited(controller.dispose());
      case AppLifecycleState.resumed:
        if (controller == null && _error == null) unawaited(_open());
    }
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'This handset has no camera.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        // Enough to read a printed best-before code off a label, without the
        // buffers a full-sensor preset would hold open for the whole capture.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      // The Android plugin asks for the camera permission here, so there is no
      // separate prompt to manage.
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
              'The app has not been allowed to use the camera. Enable it in '
                  'Settings › Apps › FSA Inspector › Permissions.',
            'CameraAccessRestricted' =>
              'Camera access is restricted on this handset.',
            _ => e.description ?? e.code,
          },
        );
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'The camera could not start. $e');
    }
  }

  Future<void> _shutter() async {
    final controller = _controller;
    if (controller == null || _shooting) return;

    setState(() => _shooting = true);
    try {
      final shot = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(shot.path);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _shooting = false;
          _error = 'The photograph could not be taken. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            _CameraError(message: _error!, onRetry: () {
              setState(() => _error = null);
              unawaited(_open());
            })
          else if (controller == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            // Fills the screen the way a camera app does; the preview's aspect
            // ratio rarely matches the phone's, and letterboxing a viewfinder
            // makes framing a label harder than it needs to be.
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1080,
                height: controller.value.previewSize?.width ?? 1920,
                child: CameraPreview(controller),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(title: widget.title),
                const Spacer(),
                if (_error == null && controller != null)
                  _Shutter(busy: _shooting, onPressed: _shutter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Cancel',
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Semantics(
        button: true,
        label: 'Take the photograph',
        child: GestureDetector(
          onTap: busy ? null : onPressed,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.25),
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 44),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
