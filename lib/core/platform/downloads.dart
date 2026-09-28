import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';

/// Where a downloaded document ended up.
class SavedDownload {
  const SavedDownload(this.where, this.uri);

  /// What to tell the inspector — "Downloads/FSA-….pdf".
  final String where;

  /// The document's own address, so it can be opened straight from the
  /// message rather than hunted for. Empty when the platform gave none.
  final String uri;
}

/// Puts a document in the phone's Downloads folder.
///
/// The file plugins write into the app's private external directory, which
/// Android 11 and later hide from every file manager — so a document
/// "downloaded" that way cannot be opened, attached to an email, or handed
/// to anyone. Downloads is a shared collection the platform lets an app add
/// to without asking for storage permission, so that is where these go.
abstract final class Downloads {
  static const _channel = MethodChannel('za.co.eclick.fsa_app/downloads');

  static Future<SavedDownload> save(
    String fileName,
    Uint8List bytes, {
    String mimeType = 'application/pdf',
  }) async {
    if (Platform.isAndroid) {
      final saved = await _channel.invokeMapMethod<String, String>(
        'saveToDownloads',
        {'name': fileName, 'bytes': bytes, 'mimeType': mimeType},
      );
      final where = saved?['where'];
      if (where != null && where.isNotEmpty) {
        return SavedDownload(where, saved?['uri'] ?? '');
      }
    }

    // Anywhere else — and if the platform ever refuses — fall back to the
    // plugin, which at least puts the file somewhere and never throws.
    final stem = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final path = await FileSaver.instance.saveFile(
      name: stem,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
    return SavedDownload(path, '');
  }

  /// Opens a saved download in whatever reads PDFs on this phone. False if
  /// nothing does — the file is saved either way.
  static Future<bool> open(SavedDownload saved,
      {String mimeType = 'application/pdf'}) async {
    if (!Platform.isAndroid || saved.uri.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openDownload',
            {'uri': saved.uri, 'mimeType': mimeType},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// The name a document is saved under, in the Agency's own convention:
  /// `FSA-Kroon-Foods-Test-Store-RFI-260822.pdf`, matching what the office
  /// sees on the record so the two can be told apart at a glance.
  static String documentName(String site, String kind, DateTime date) {
    final slug = site
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stamp = '${date.year % 100}'.padLeft(2, '0') +
        '${date.month}'.padLeft(2, '0') +
        '${date.day}'.padLeft(2, '0');
    return 'FSA-$slug-$kind-$stamp.pdf';
  }
}
