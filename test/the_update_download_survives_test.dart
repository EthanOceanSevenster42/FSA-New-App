import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/updates/data/app_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// What happens to the downloaded build between arriving and being installed.
///
/// Inspectors on 2234 were offered 2236, pulled the whole 32 MB down — the
/// server log shows 200 and every byte sent — and were then shown
/// "PathNotFoundException ... fsa-inspector-2236.apk (OS Error: No such file
/// or directory)". The APK had been staged in the app's cache, which Android
/// reclaims first when a handset is short of space, and the finished-download
/// check re-read the file off disk, so a file that had been swept away was
/// reported as a path error rather than as anything an inspector could act on
/// (Ethan, 2026-10-26).
class _Dirs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Dirs({required this.support, required this.cache});

  final String support;
  final String cache;

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getTemporaryPath() async => cache;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late Directory cache;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('fsa_update_support');
    cache = await Directory.systemTemp.createTemp('fsa_update_cache');
    PathProviderPlatform.instance =
        _Dirs(support: support.path, cache: cache.path);
  });
  tearDown(() {
    for (final d in [support, cache]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  const update = AppUpdate(
      version: '1.0.1+2237',
      build: 2237,
      url: 'https://example.test/downloads/fsa-inspector-latest.apk');

  /// A server that hands back [body] with a content length, the way nginx
  /// serves the APK.
  AppUpdateService serving(List<int> body, {int? declaredLength}) =>
      AppUpdateService(
        client: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(body),
            200,
            contentLength: declaredLength ?? body.length,
          );
        }),
      );

  test('the build is kept out of the cache Android reclaims', () async {
    final bytes = Uint8List.fromList(List.filled(4096, 7));
    final file = await serving(bytes).download(update);

    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), bytes.length);
    // In the app's own files directory, not the cache.
    expect(file.path.startsWith(support.path), isTrue,
        reason: 'staged at ${file.path}, which Android may clear');
    expect(file.path.startsWith(cache.path), isFalse);
  });

  test('a half-finished download is refused, and says so', () async {
    // The server promises more than it sends — a dropped mobile connection.
    final service = serving(List.filled(100, 1), declaredLength: 5000);

    await expectLater(
      service.download(update),
      throwsA(isA<HttpException>().having((e) => e.message, 'message',
          contains('did not finish'))),
    );
  });

  // The "file vanished mid-update" branch — the October failure itself —
  // is not unit-tested here: simulating it means deleting the file while
  // the sink still holds it open, which Windows refuses. The guard it
  // reaches is `if (!out.existsSync())` in download(), which reports the
  // handset being out of space instead of a PathNotFoundException.

  test('what a failed attempt left behind is cleared first', () async {
    final folder =
        Directory('${support.path}${Platform.pathSeparator}updates')
          ..createSync(recursive: true);
    final stale = File('${folder.path}${Platform.pathSeparator}'
        'fsa-inspector-2236.apk')
      ..writeAsBytesSync(List.filled(999, 9));
    expect(stale.existsSync(), isTrue);

    final bytes = List.filled(1024, 5);
    final file = await serving(bytes).download(update);

    expect(stale.existsSync(), isFalse,
        reason: 'the older part-download is still on the handset');
    expect(file.lengthSync(), bytes.length);
    expect(folder.listSync().whereType<File>().length, 1);
  });
}
