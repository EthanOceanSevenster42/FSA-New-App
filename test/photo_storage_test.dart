import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/services/photo_storage.dart';

/// Where evidence photographs are kept and how they get there.
void main() {
  late Directory root;
  late Directory cache;
  late PhotoStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fsa_photos_');
    cache = await Directory.systemTemp.createTemp('fsa_cache_');
    PhotoStorage.overrideForTesting(root);
    storage = await PhotoStorage.instance();
  });

  tearDown(() {
    PhotoStorage.resetForTesting();
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  File captured(String name, {int bytes = 2048}) =>
      File('${cache.path}/$name')..writeAsBytesSync(List.filled(bytes, 7));

  group('adopting a captured photo', () {
    test('moves the file into private storage', () async {
      final source = captured('IMG_0001.jpg');

      final path = await storage.adopt(source, name: 'egg_label.jpg');

      expect(File(path).existsSync(), isTrue);
      expect(path, startsWith(root.path));
      expect(File(path).lengthSync(), 2048);
    });

    test('does not leave a copy behind in the cache', () async {
      // The camera plugin writes to the cache directory. Copying instead of
      // moving held every photograph twice until the system cleared it.
      final source = captured('IMG_0002.jpg');

      await storage.adopt(source, name: 'egg_egg.jpg');

      expect(source.existsSync(), isFalse);
    });

    test('the contents survive the move intact', () async {
      final source = File('${cache.path}/IMG_0003.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final path = await storage.adopt(source, name: 'egg_deviation.jpg');

      expect(File(path).readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('two photos with different names both survive', () async {
      final a = await storage.adopt(captured('a.jpg'), name: 'one.jpg');
      final b = await storage.adopt(captured('b.jpg'), name: 'two.jpg');

      expect(File(a).existsSync(), isTrue);
      expect(File(b).existsSync(), isTrue);
      expect(a, isNot(b));
    });
  });

  group('kept away from the gallery', () {
    test('photos live in their own folder, not beside the database', () async {
      // The documents root holds fsa_local.sqlite; loose JPEGs next to it make
      // both harder to reason about.
      expect(PhotoStorage.folderName, 'inspection_photos');
      expect(storage.path, root.path);
    });

    test('a .nomedia marker is written', () async {
      // App-private storage is not scanned, but the marker means these never
      // surface in the gallery even if the location were ever to change.
      expect(File('${root.path}/.nomedia').existsSync(), isTrue);
    });
  });

  group('removing a photo', () {
    test('deletes the file', () async {
      final path = await storage.adopt(captured('x.jpg'), name: 'x.jpg');
      expect(File(path).existsSync(), isTrue);

      await storage.delete(path);

      expect(File(path).existsSync(), isFalse);
    });

    test('deleting something already gone is not an error', () async {
      // A record downloaded from another handset names files that were never
      // on this one.
      await storage.delete('${root.path}/never_existed.jpg');
    });
  });

  group('storage accounting', () {
    test('reports the bytes held', () async {
      await storage.adopt(captured('a.jpg', bytes: 1000), name: 'a.jpg');
      await storage.adopt(captured('b.jpg', bytes: 2000), name: 'b.jpg');

      // The .nomedia marker is empty, so it adds nothing.
      expect(await storage.bytesUsed(), 3000);
    });

    test('an empty folder reports zero', () async {
      expect(await storage.bytesUsed(), 0);
    });
  });
}
