import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'photo_shrink.dart';

/// Where inspection photographs live on the handset.
///
/// Evidence photographs are kept in the application's own private directory —
/// `/data/data/<package>/app_flutter/inspection_photos` on Android. That
/// location is readable only by this app: it does not appear in the gallery,
/// in a file manager, or to any other installed application, and it is removed
/// when the app is uninstalled. Inspection evidence should not be sitting in
/// the camera roll where it can be shared or deleted by accident.
///
/// Photographs are also kept out of the documents root itself, which holds the
/// database — a folder of loose JPEGs next to `fsa_local.sqlite` makes both
/// harder to reason about.
class PhotoStorage {
  PhotoStorage._(this._directory);

  final Directory _directory;

  static PhotoStorage? _instance;

  /// Folder name, under the app's private documents directory.
  static const folderName = 'inspection_photos';

  /// Resolves the folder, creating it on first use.
  static Future<PhotoStorage> instance() async {
    final existing = _instance;
    if (existing != null) return existing;

    final documents = await getApplicationDocumentsDirectory();
    return _instance = _prepare(Directory('${documents.path}/$folderName'));
  }

  /// Creates the folder and marks it as non-media.
  ///
  /// Shared by the real path and the test seam, so a test exercises the same
  /// preparation that ships rather than a hollow stand-in.
  static PhotoStorage _prepare(Directory directory) {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    // Belt and braces: app-private storage is not scanned by the media
    // service, but a `.nomedia` marker means that even if these files were
    // ever moved somewhere scannable, they still would not surface in the
    // gallery.
    final marker = File('${directory.path}/.nomedia');
    if (!marker.existsSync()) {
      marker.createSync();
    }
    return PhotoStorage._(directory);
  }

  String get path => _directory.path;

  /// Takes ownership of a freshly captured file and returns its final path.
  ///
  /// The camera plugin writes into the app's cache directory, which the system
  /// may clear at any time — so the file has to be moved somewhere durable
  /// before it is recorded against an inspection.
  ///
  /// Uses [File.rename] rather than a copy. Both directories are on the same
  /// filesystem, so a rename is a metadata update that completes instantly
  /// whatever the file size, where a copy reads and rewrites every byte. That
  /// second pass over a multi-megabyte JPEG is a visible pause on a cheap
  /// handset, and it left the original behind in the cache as well.
  /// Where a file called [name] would live in this store.
  ///
  /// For callers that write their own bytes — a signature is rendered
  /// straight to PNG rather than captured by the camera, so it has nothing to
  /// [adopt]. Keeps the directory itself private.
  String pathFor(String name) => '${_directory.path}/$name';

  /// How an adopted photograph is brought down to size. Replaced in tests
  /// that only care where the file went.
  static Future<int> Function(String path) shrink = PhotoShrink.shrinkInPlace;

  Future<String> adopt(File captured, {required String name}) async {
    final target = '${_directory.path}/$name';
    String path;
    try {
      final moved = await captured.rename(target);
      path = moved.path;
    } on FileSystemException {
      // Rename fails across filesystems. Fall back to copying, then remove the
      // source so a large photo is not held twice.
      await captured.copy(target);
      try {
        await captured.delete();
      } on FileSystemException {
        // The cache copy is the system's to reclaim; nothing more to do.
      }
      path = target;
    }
    // Down to inspection size before it is recorded, so what is stored and
    // sent is the small copy. Never the reason a capture fails.
    try {
      await shrink(path);
    } on Object {
      // The full-size shot stays; it is only larger.
    }
    return path;
  }

  /// Removes a photograph. Silent when the file has already gone.
  Future<void> delete(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Losing the file matters less than failing the capture that follows.
    }
  }

  /// Total bytes held, for reporting storage use.
  Future<int> bytesUsed() async {
    if (!_directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in _directory.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Raced with a delete; skip it.
        }
      }
    }
    return total;
  }

  /// Test seam: point storage at a temporary directory, prepared exactly as
  /// the real one is.
  static void overrideForTesting(Directory directory) {
    _instance = _prepare(directory);
  }

  static void resetForTesting() => _instance = null;
}
