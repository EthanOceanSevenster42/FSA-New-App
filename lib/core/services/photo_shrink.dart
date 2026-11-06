import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// Brings a captured photograph down to what an inspection record needs.
///
/// The camera hands over the sensor's full frame, 4 MB and more a shot, and
/// every one of them went to the server as it was: a visit with a handful
/// of photographs cost tens of megabytes of the inspector's mobile data
/// (Ethan, 2026-09-26: "I am limited on data"). A label, a scale reading or
/// a container face is perfectly legible at [maxEdge] pixels on the long
/// side, which is about a tenth of the size.
///
/// The shrinking is done by the phone's own image codec, which takes a
/// fraction of a second. It used to be done in Dart, decoding and
/// re-encoding every pixel, and a 12-megapixel shot kept "Saving…" on the
/// button for several seconds (Ethan, 2026-10-01). The Dart path stays as
/// the fallback — where the native codec is not there, as in tests — and
/// either way a capture never fails over it: a file that cannot be read as
/// a picture is left exactly as it was.
abstract final class PhotoShrink {
  /// The longest side after shrinking. 1600 px keeps small print on a
  /// label readable when the office zooms in.
  static const maxEdge = 1600;

  /// JPEG quality of the shrunk copy.
  static const quality = 82;

  /// Files under this are already small enough and are left untouched.
  static const leaveAloneBelow = 700 * 1024;

  /// Shrinks the photograph at [path] in place. Returns its size in bytes
  /// afterwards — the original size when nothing was changed.
  static Future<int> shrinkInPlace(String path) async {
    final file = File(path);
    if (!file.existsSync()) return 0;
    final before = file.lengthSync();
    if (before < leaveAloneBelow) return before;
    final native = await _shrinkNatively(path, before);
    if (native != null) return native;
    return compute(_shrink, path);
  }

  /// The phone's codec: scaled so the long side is [maxEdge], rotated the
  /// way the camera held it, and swapped in for the original. Null when
  /// the codec is not available or did not help, so the Dart path runs.
  static Future<int?> _shrinkNatively(String path, int before) async {
    final staging = '$path.shrinking';
    try {
      // The short side the codec is to keep: both minimums the same, so
      // the result has the long side at [maxEdge] whichever way the frame
      // is turned. The header gives the size without decoding the picture.
      final shortSide = _shortSideFor(path);
      final out = await FlutterImageCompress.compressAndGetFile(
        path,
        staging,
        minWidth: shortSide,
        minHeight: shortSide,
        quality: quality,
        autoCorrectionAngle: true,
        keepExif: false,
        format: CompressFormat.jpeg,
      );
      if (out == null) return null;
      final staged = File(out.path);
      final after = staged.lengthSync();
      if (after <= 0 || after >= before) {
        staged.deleteSync();
        return before;
      }
      staged.renameSync(path);
      return after;
    } on Object {
      try {
        final staged = File(staging);
        if (staged.existsSync()) staged.deleteSync();
      } on FileSystemException {
        // Nothing refers to it.
      }
      return null;
    }
  }

  /// What the short side scales to when the long side becomes [maxEdge];
  /// 4:3 assumed when the header cannot be read.
  static int _shortSideFor(String path) {
    try {
      final info = img.JpegDecoder().startDecode(File(path).readAsBytesSync());
      if (info != null && info.width > 0 && info.height > 0) {
        final long = info.width > info.height ? info.width : info.height;
        final short = info.width > info.height ? info.height : info.width;
        if (long <= maxEdge) return short;
        return (short * maxEdge / long).round();
      }
    } on Object {
      // Fall through to the assumption.
    }
    return maxEdge * 3 ~/ 4;
  }

  static int _shrink(String path) {
    final file = File(path);
    if (!file.existsSync()) return 0;
    final before = file.lengthSync();
    if (before < leaveAloneBelow) return before;
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(file.readAsBytesSync());
    } on Object {
      return before;
    }
    if (decoded == null) return before;
    // Phones store the frame as the sensor sees it and note the rotation
    // in EXIF; a resize drops that note, so the rotation is applied first.
    var picture = img.bakeOrientation(decoded);
    final longest =
        picture.width > picture.height ? picture.width : picture.height;
    if (longest > maxEdge) {
      picture = picture.width >= picture.height
          ? img.copyResize(picture,
              width: maxEdge, interpolation: img.Interpolation.average)
          : img.copyResize(picture,
              height: maxEdge, interpolation: img.Interpolation.average);
    }
    final bytes = img.encodeJpg(picture, quality: quality);
    if (bytes.length >= before) return before;
    // Written beside the original and swapped in, so a crash mid-write
    // cannot leave a half photograph on the record.
    final staging = File('$path.shrinking');
    staging.writeAsBytesSync(bytes, flush: true);
    staging.renameSync(path);
    return bytes.length;
  }
}
