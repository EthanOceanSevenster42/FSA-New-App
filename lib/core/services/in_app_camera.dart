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
  /// Resolutions to try, best first.
  ///
  /// A camera can only run so many streams at once, and camerax asks for
  /// three (preview, capture, analysis). Which sizes it will take together
  /// differs by device: the Lenovo tablet refuses all three at 1080p with
  /// "No supported surface combination is found for camera device", where a
  /// handset takes them happily. Rather than drop every device to the lowest
  /// common denominator, step down until one is accepted — [max] is in the
  /// list because a basic camera guarantees the combination only when the
  /// still capture is at its largest size, not a middling one.
  static const _presets = [
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
    ResolutionPreset.max,
    ResolutionPreset.medium,
    ResolutionPreset.low,
  ];

  CameraController? _controller;
  String? _error;
  bool _shooting = false;
  int _preset = 0;

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
    // camerax races its preview surface on some Samsungs: initialize() can
    // throw IllegalStateException("surfaceProducerHandlesCropAndRotation()
    // cannot be called if the flutterSurfaceProducer ... has not yet been
    // initialized"). A moment later the same call succeeds, so the transient
    // failure earns one quiet retry before the inspector sees anything.
    // Enough attempts to walk the whole resolution list as well as ride out
    // the surface race.
    for (var attempt = 0; attempt < _presets.length + 2; attempt++) {
      final failed = await _tryOpen();
      if (!failed || !mounted) return;
      // Only the retryable states get here; everything else surfaced already.
      if (_error != null) return;
      // A resolution step-down can go straight round again; the surface race
      // needs a moment to settle.
      if (_preset > 0) continue;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    if (mounted && _error == null && _controller == null) {
      setState(() => _error = 'The camera could not start. Please try again.');
    }
  }

  /// One attempt at opening the camera. True means the surface race hit and
  /// a retry is worthwhile; other failures set [_error] themselves.
  /// True when [error] is one of camerax's transient start-up states —
  /// the surface race itself, and the null-state it leaves behind when a
  /// failed controller was still in the plugin's hands.
  static bool _isTransientStartupFailure(String error) =>
      error.contains('surfaceProducerHandlesCropAndRotation') ||
      error.contains('has not yet been initialized') ||
      error.contains('Null check operator');

  /// This camera will not run the three streams at the size just asked for.
  /// Worth retrying at a different size; not worth showing anyone.
  static bool _isUnsupportedCombination(String error) =>
      error.contains('No supported surface combination') ||
      error.contains('too many use cases');

  /// Steps down to the next resolution. False once they are exhausted.
  bool _stepDownResolution() {
    if (_preset + 1 >= _presets.length) return false;
    _preset++;
    return true;
  }

  Future<bool> _tryOpen() async {
    // Held outside the try so a failure part-way through initialisation can
    // still dispose it — a half-built controller left behind is exactly what
    // made the retry crash with "Null check operator used on a null value".
    CameraController? controller;
    Future<void> discard() async {
      final failed = controller;
      controller = null;
      if (failed != null) {
        try {
          await failed.dispose();
        } on Object {
          // Already broken; nothing to release.
        }
      }
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'This handset has no camera.');
        return false;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        back,
        // Enough to read a printed best-before code off a label, without the
        // buffers a full-sensor preset would hold open for the whole capture
        // — stepped down if this camera will not run three streams that big.
        _presets[_preset],
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      // The Android plugin asks for the camera permission here, so there is no
      // separate prompt to manage.
      await controller!.initialize();

      if (!mounted) {
        await discard();
        return false;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      return false;
    } on CameraException catch (e) {
      await discard();
      // The camerax surface race surfaces as a CameraException with the
      // IllegalStateException text in its description — it must retry, not
      // report. (It was only caught in the generic branch below before,
      // which this branch shadowed, so the inspector kept seeing it.)
      final text = '${e.code} ${e.description ?? ''}';
      if (_isTransientStartupFailure(text)) {
        return true;
      }
      if (_isUnsupportedCombination(text) && _stepDownResolution()) {
        return true;
      }
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'CameraAccessDenied' ||
            'CameraAccessDeniedWithoutPrompt' =>
              'The app has not been allowed to use the camera. Enable it in '
                  'Settings › Apps › FSA Inspector › Permissions.',
            'CameraAccessRestricted' =>
              'Camera access is restricted on this handset.',
            _ => e.description ?? e.code,
          },
        );
      }
    } on Object catch (e) {
      await discard();
      // The known transient start-up states retry silently; anything else
      // is reported.
      if (_isTransientStartupFailure(e.toString())) {
        return true;
      }
      if (_isUnsupportedCombination(e.toString()) && _stepDownResolution()) {
        return true;
      }
      if (mounted) setState(() => _error = 'The camera could not start. $e');
    }
    return false;
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
            _CameraError(
                message: _error!,
                onRetry: () {
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
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.brandPrimary),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
