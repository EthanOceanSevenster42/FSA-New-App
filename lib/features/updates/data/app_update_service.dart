import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/published_build.dart';

/// A build waiting on the download server.
class AppUpdate {
  const AppUpdate(
      {required this.version, required this.build, required this.url});

  /// What the office published, as written in `latest.json` — "1.0.1+2107".
  final String version;

  /// The part that decides whether it is newer than what is running.
  final int build;

  /// Where the APK itself is.
  final String url;

  /// How it should read to an inspector: "1.0.1.2107".
  String get display => version.replaceAll('+', '.');
}

/// Keeps the handsets on the current build.
///
/// Inspectors are handed a device, not a Play Store account, so a build that
/// fixes a blocked submission has no way to reach them on its own. The app
/// therefore looks for one itself when someone signs in, and offers to
/// install it there and then.
///
/// Nothing here interrupts an inspection: the check is made at sign-in, on a
/// screen where there is no capture to lose, and every failure is silent —
/// an inspector out of signal must never be stopped by an update check.
class AppUpdateService {
  AppUpdateService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  /// Where the office publishes builds. An FSA address, the same one the QR
  /// code hands out.
  static const defaultBaseUrl = 'https://aps-demo.fsa-pty.co.za/downloads';

  static const _channel = MethodChannel('za.co.eclick.fsa_app/downloads');

  /// The build this app was compiled as, passed in at build time.
  ///
  /// It cannot be read off the package: `--split-per-abi` adds the ABI's
  /// own offset to the Android version code (armeabi-v7a 1000, arm64-v8a
  /// 2000, x86_64 3000), so a handset installed from the QR download
  /// reports 4111 for build 2111 — a number larger than anything the office
  /// will ever publish, and the handset would quietly never be offered
  /// another build again.
  ///
  /// Every release build therefore passes
  /// `--dart-define=BUILD_NUMBER=<the same number as --build-number>`.
  static const _bakedBuild = int.fromEnvironment('BUILD_NUMBER');

  /// What this app should call itself when asking whether it is current.
  ///
  /// Falls back to the package's version code, which is right for a build
  /// that was not split per ABI, and is the best guess available when the
  /// define was forgotten.
  Future<String> runningBuild() async {
    if (_bakedBuild > 0) return '$_bakedBuild';
    return (await PackageInfo.fromPlatform()).buildNumber;
  }

  final http.Client _client;
  final String _baseUrl;

  /// The build the inspector last turned down, if any.
  ///
  /// Kept in a file of its own rather than the database: this belongs to
  /// the handset, not to an inspection, and it has to be readable on the
  /// sign-in screen before anyone has signed in.
  Future<int?> declinedBuild() async {
    try {
      final file = File(await _declinedPath());
      if (!file.existsSync()) return null;
      return int.tryParse(file.readAsStringSync().trim());
    } on Object {
      return null;
    }
  }

  /// Remembers that this build was turned down. It will not be offered
  /// again — a newer one still will.
  Future<void> decline(AppUpdate update) async {
    try {
      File(await _declinedPath()).writeAsStringSync('${update.build}');
    } on Object {
      // Not remembering is a nuisance, not a failure.
    }
  }

  Future<String> _declinedPath() async =>
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}update_declined';

  /// The published build, if it is newer than the one running.
  ///
  /// Null when the app is current, when the server cannot be reached, or
  /// when anything at all goes wrong: an update is a convenience, and a
  /// convenience must not stand between an inspector and their work.
  ///
  /// [respectDeclined] is what stops the offer from becoming nagging, and it
  /// is deliberately not applied everywhere. A handset that merely restored a
  /// session — Android killed the app, the inspector reopened it — honours the
  /// decline, so saying "later" quietly holds for the rest of the shift. A
  /// fresh sign-in passes false and asks again, because that is the one
  /// gesture inspectors are told to perform to pick up a release, and because
  /// these handsets have no Play Store: if "later" meant "never", one stray
  /// tap would strand that inspector on an old build until the office happened
  /// to publish a newer number, which is exactly the case a build that fixes a
  /// blocked submission cannot afford.
  Future<AppUpdate?> check({bool respectDeclined = true}) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/latest.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final version = (body['version'] as String? ?? '').trim();
      final running = await runningBuild();
      if (!PublishedBuild.isNewer(published: version, running: running)) {
        return null;
      }
      final published = PublishedBuild.numberOf(version)!;

      // Asked once per sign-in. An inspector who said "later" is not asked
      // again for the same build every time Android restarts the app.
      if (respectDeclined) {
        final declined = await declinedBuild();
        if (declined != null && declined >= published) return null;
      }

      final file =
          (body['file'] as String? ?? 'fsa-inspector-latest.apk').trim();
      return AppUpdate(
        version: version,
        build: published,
        url: '$_baseUrl/$file',
      );
    } on Object {
      return null;
    }
  }

  /// Downloads the build, reporting progress from 0 to 1.
  ///
  /// Written to the app's own cache: Android clears it, and the installer
  /// can be handed the file from there without any storage permission.
  Future<File> download(
    AppUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    final folder = Directory(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}updates');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final out = File('${folder.path}${Platform.pathSeparator}'
        'fsa-inspector-${update.build}.apk');

    final request = http.Request('GET', Uri.parse(update.url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('The download server answered '
          '${response.statusCode}.');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = out.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }

    // A truncated download would fail to install with nothing to explain it.
    if (total > 0 && out.lengthSync() != total) {
      out.deleteSync();
      throw const HttpException('The download did not finish.');
    }
    return out;
  }

  /// Whether this phone will let the app start an install.
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallApks') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens Android on this app's "Install unknown apps" switch.
  ///
  /// False when the handset has no such screen to open, in which case the
  /// inspector is left with the written directions and nothing is lost.
  Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens Android's installer on the downloaded build. The inspector still
  /// confirms it themselves.
  Future<bool> install(File apk) async {
    try {
      return await _channel
              .invokeMethod<bool>('installApk', {'path': apk.path}) ??
          false;
    } on Object {
      return false;
    }
  }
}
