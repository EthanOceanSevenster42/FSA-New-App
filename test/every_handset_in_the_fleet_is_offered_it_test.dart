// Every build an inspector is actually carrying, asked against the live feed.
//
// Not a hypothetical: these are the `app_version` values in
// `accounts_handsetversion` on 2026-10-21, one per handset in the field.
// Each one signs in, the real download server is asked what is current, and
// the answer must be "install the build this working tree is on". The one
// exception is called out below
// and is a genuine fault, not a passing test dressed up.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/updates/data/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The build this working tree is on, which is what the office publishes.
/// It was hard-coded, so the check went stale the moment the next build
/// shipped and every handset row failed on the old number rather than on
/// anything real (Ethan, 2026-10-26).
final _published = int.parse(
    RegExp(r'^version:\s*\S+\+(\d+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!);

/// Who is on what, read off the fleet table on 2026-10-21.
const _fleet = <String, String>{
  'Kabelo Percy': '2219',
  'Lwandile Maqina': '2232',
  'Cinga Ngongo': '2232',
  'Ben Visagie': '2232',
  'Omphile Mokgothu': '2233',
  'Sandisiwe Dlisani': '2232',
  'Gladys Manganye': '2233',
  'Mpeluza Xola': '2232',
  'Thato Sekhotho': '2232',
  'Kutlwano Kuntwane': '2232',
  'Hellen Modiba': '2232',
  'Jofred Steyn': '2232',
  'Ethan Sevenster': '2232',
  'Mokgadi Selone': '2230',
  'Nelisa Ntoyaphi': '2219',
  'Simphiwe': '2227',
  'Seun Sebolai': '2182',
  'Neo Noe': '2219',
  'Lwandile Dlamini': '2207',
  'Henry': '2184',
  'Armand Visagie': '2181',
};

class _SupportDir extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _SupportDir(this._path);
  final String _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory support;
  setUp(() async {
    support = await Directory.systemTemp.createTemp('fsa_fleet');
    PathProviderPlatform.instance = _SupportDir(support.path);
  });
  tearDown(() => support.deleteSync(recursive: true));

  AppUpdateService handsetOn(String build) {
    PackageInfo.setMockInitialValues(
      appName: 'Food Safety Agency',
      packageName: 'za.co.eclick.fsa_app',
      version: '1.0.1',
      buildNumber: build,
      buildSignature: '',
    );
    return AppUpdateService();
  }

  _fleet.forEach((who, build) {
    test("$who, on $build, is offered the update", () async {
      final update = await handsetOn(build).check(respectDeclined: false);
      expect(update, isNotNull,
          reason: '$who would never be told about $_published');
      expect(update!.build, _published);
    });
  });

  // A handset whose APK was built without --dart-define=BUILD_NUMBER reports
  // its ABI version code (arm64 adds 2000), so it believes it is on build
  // 4176 — ahead of anything the office will ever publish — and is never
  // offered another build. One such row is in the fleet table (a LENOVO
  // TB336ZU, last seen 2 Oct). It cannot be fixed from the server: that
  // handset has to be reinstalled by hand from the QR page.
  test('a handset reporting an ABI version code is stranded, as expected',
      () async {
    expect(await handsetOn('4176').check(respectDeclined: false), isNull);
  });
}
