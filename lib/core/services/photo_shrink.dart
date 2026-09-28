import 'dart:io';

import 'package:flutter/foundation.dart';
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
/// The work runs off the UI isolate, and it never fails a capture: a file
/// that cannot be read as a picture is left exactly as it was.
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
  static Future<int> shrinkInPlace(String path) => compute(_shrink, path);

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
