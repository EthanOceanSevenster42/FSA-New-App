// Does the update question actually get asked, against the live feed?
//
// This talks to the real download server — the same URL the handsets poll,
// `AppUpdateService.defaultBaseUrl`. It is the one check the unit tests
// cannot make: they feed the service a canned `latest.json`, so they would
// go on passing while the published feed 404s, which is exactly what
// happened to the fleet until 2026-10-20 (no nginx vhost carried
// `aps-demo.fsa-pty.co.za`, and inspectors reported "I'm not getting the
// option to update"). Needs the network; `flutter_test` blocks HTTP by
// default, so the overrides are cleared.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/updates/data/app_update_service.dart';
import 'package:fsa_app/features/updates/domain/published_build.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The build this run expects the office to have published: the one in
/// pubspec.yaml, which is what was just built. Hard-coding it meant the
/// check went stale the moment the next build shipped — it still read 2234
/// two publishes later (Ethan, 2026-10-26).
final _published = int.parse(RegExp(r'^version:\s*\S+\+(\d+)', multiLine: true)
    .firstMatch(File('pubspec.yaml').readAsStringSync())!
    .group(1)!);

class _SupportDir extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _SupportDir(this._path);
  final String _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every request 400 unless the overrides are dropped.
  HttpOverrides.global = null;

  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('fsa_live_update');
    PathProviderPlatform.instance = _SupportDir(support.path);
  });
  tearDown(() => support.deleteSync(recursive: true));

  /// A handset running [build], asking the live server what is current.
  AppUpdateService handsetOn(int build) {
    PackageInfo.setMockInitialValues(
      appName: 'Food Safety Agency',
      packageName: 'za.co.eclick.fsa_app',
      version: '1.0.1',
      buildNumber: '$build',
      buildSignature: '',
    );
    return AppUpdateService();
  }

  test('the published feed answers on the URL the handsets poll', () async {
    final client = HttpClient();
    final request = await client
        .getUrl(Uri.parse('${AppUpdateService.defaultBaseUrl}/latest.json'));
    final response = await request.close();
    expect(response.statusCode, 200,
        reason: 'the feed must answer on aps-demo.fsa-pty.co.za');
    client.close();
  });

  test('a handset on the previous build is offered this one', () async {
    final update = await handsetOn(_published - 1).check();
    expect(update, isNotNull, reason: 'the update question must be asked');
    expect(update!.build, _published);
    expect(update.display, '1.0.1.$_published');
    expect(update.url, endsWith('.apk'));
  });

  test('a handset already on this build is left alone', () async {
    expect(await handsetOn(_published).check(), isNull);
  });

  test('the offered APK really downloads', () async {
    final update = await handsetOn(_published - 1).check();
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(update!.url));
    // Just the headers: the file is ~32 MB.
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(response.contentLength, greaterThan(20 * 1024 * 1024));
    await response.drain<void>();
    client.close();
  });

  test('every handset below this build is offered it', () {
    for (final running in [2174, 2219, 2228, 2230, 2233]) {
      expect(
          PublishedBuild.isNewer(
              published: '1.0.1+$_published', running: '$running'),
          isTrue,
          reason: 'a handset on $running must be prompted');
    }
  });
}
