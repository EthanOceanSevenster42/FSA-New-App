import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/updates/data/app_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Whether a handset is ever told about a build the inspector turned down.
///
/// These handsets have no Play Store, so the sign-in prompt is the only way a
/// build reaches an inspector. "Later" therefore has to mean "not now", not
/// "never": an inspector who taps it on the way into a plant must still be
/// offered the build the next time they sign in, or a release that fixes a
/// blocked submission would never arrive. What "later" does buy them is quiet
/// for the rest of the shift — Android restarting the app does not ask again.
class _SupportDir extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _SupportDir(this._path);

  final String _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('fsa_update_offer');
    PathProviderPlatform.instance = _SupportDir(support.path);
    // The running build. A release passes --dart-define=BUILD_NUMBER, which is
    // absent here, so the service falls back to the package's own number.
    PackageInfo.setMockInitialValues(
      appName: 'Food Safety Agency',
      packageName: 'za.co.eclick.fsa_app',
      version: '1.0.1',
      buildNumber: '2160',
      buildSignature: '',
    );
  });

  tearDown(() => support.deleteSync(recursive: true));

  AppUpdateService publishing(String version) => AppUpdateService(
        baseUrl: 'https://example.invalid/downloads',
        client: MockClient(
          (_) async => http.Response(
            '{"version": "$version", "updated": "2026-09-11T00:00:00Z", '
            '"file": "fsa-inspector-latest.apk"}',
            200,
          ),
        ),
      );

  test('a declined build is offered again on the next sign-in', () async {
    final service = publishing('1.0.1+2161');

    final offered = await service.check(respectDeclined: false);
    expect(offered, isNotNull, reason: '2161 is newer than the running 2160');
    expect(offered!.build, 2161);
    expect(offered.display, '1.0.1.2161');

    await service.decline(offered);

    // A restored session stays quiet about it.
    expect(await service.check(), isNull);

    // A deliberate sign-in asks again, so "later" is not a dead end.
    final again = await service.check(respectDeclined: false);
    expect(again, isNotNull);
    expect(again!.build, 2161);
  });

  test('a newer build is offered even after an older one was declined',
      () async {
    final declined = await publishing('1.0.1+2161').check();
    await publishing('1.0.1+2161').decline(declined!);

    expect((await publishing('1.0.1+2162').check())?.build, 2162);
  });

  test('the build already running is never offered', () async {
    expect(await publishing('1.0.1+2160').check(), isNull);
    expect(await publishing('1.0.1+2159').check(), isNull);
  });

  test('an unparseable published version is treated as no update', () async {
    expect(await publishing('1.0.1').check(), isNull);
    expect(await publishing('').check(), isNull);
  });

  test('a download server that cannot be reached is silent', () async {
    final service = AppUpdateService(
      baseUrl: 'https://example.invalid/downloads',
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(await service.check(respectDeclined: false), isNull);
  });
}
