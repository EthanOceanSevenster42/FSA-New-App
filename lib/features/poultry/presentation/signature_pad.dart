import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';

/// Captures a signature and returns it as a PNG file path.
///
/// Written rather than pulled from a package: the whole requirement is a
/// finger-drawn line rendered to an image, and a dependency for that is a
/// dependency to keep patched for the life of the app.
///
/// Opened full-screen and landscape-friendly. A signature strip a centimetre
/// tall gets an initial rather than a signature, and the one thing this has to
/// produce is something a person would accept as theirs.
///
/// Returns the PNG path, `null` when the page was cancelled, or
/// [signatureDeclined] when [declineLabel] was offered and chosen — the
/// signer would not or could not sign, which is an outcome, not a blank.
Future<String?> captureSignature(
  BuildContext context, {
  required String title,
  required String outputPath,
  String? caption,
  String? declineLabel,
}) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SignaturePage(
          title: title,
          caption: caption,
          outputPath: outputPath,
          declineLabel: declineLabel,
        ),
      ),
    );

/// What [captureSignature] returns when the signer declined to sign.
const signatureDeclined = '';

class _SignaturePage extends StatefulWidget {
  const _SignaturePage({
    required this.title,
    this.caption,
    required this.outputPath,
    this.declineLabel,
  });

  final String title;

  /// When set, a third choice under the box: the signer declines, and the
  /// page returns [signatureDeclined] instead of a file.
  final String? declineLabel;

  /// A fuller line under the app bar — who is signing and what for — so the
  /// title itself can stay short enough never to truncate.
  final String? caption;
  final String outputPath;

  @override
  State<_SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<_SignaturePage> {
  /// Each stroke is a separate list, so lifting the finger breaks the line
  /// instead of joining the end of one stroke to the start of the next.
  final _strokes = <List<Offset>>[];
  final _boundary = GlobalKey();
  bool _saving = false;

  bool get _hasInk => _strokes.any((s) => s.length > 1);

  Future<void> _save() async {
    if (!_hasInk || _saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // 2x so the signature stays legible when a direction is printed.
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('The signature could not be encoded.');

      final file = File(widget.outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

      if (mounted) Navigator.of(context).pop(widget.outputPath);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('The signature could not be saved. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: ContentWidth(
          child: Column(
        children: [
          if (widget.caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.caption!,
                style: TextStyle(
                    color: AppColors.inkSoft, fontSize: 13.5, height: 1.35),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Sign inside the box.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _boundary,
                child: Container(
                  // White, not the theme surface: the PNG is what gets
                  // printed, and a dark background would print as a black box.
                  color: Colors.white,
                  child: GestureDetector(
                    onPanStart: (d) => setState(
                      () => _strokes.add([d.localPosition]),
                    ),
                    onPanUpdate: (d) => setState(() {
                      if (_strokes.isEmpty) _strokes.add([]);
                      _strokes.last.add(d.localPosition);
                    }),
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            // The system navigation bar draws over the bottom edge, so the
            // buttons sit above it rather than underneath it.
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.declineLabel != null) ...[
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(signatureDeclined),
                      icon: const Icon(Icons.do_not_disturb_alt_outlined,
                          size: 18),
                      label: Text(widget.declineLabel!),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          // Disabled until something is drawn: an empty box
                          // saved as a signature is worse than no signature,
                          // because it looks like consent was given.
                          onPressed: _hasInk && !_saving ? _save : null,
                          child: Text(_saving ? 'Saving…' : 'Next'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
  // Always: the strokes list is the same instance mutated in place, so an
  // identity comparison here would never fire and the ink would never show.
}

/// Bytes of a signature file, for tests and for upload.
Future<Uint8List> readSignature(String path) => File(path).readAsBytes();
