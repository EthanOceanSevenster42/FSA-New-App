import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/local_database.dart';

/// Resolves the identifier that authorises this handset to run the app.
///
/// IMPORTANT: this must be unique per physical device. An earlier version used
/// `AndroidDeviceInfo.id`, which is `ro.build.id` — the AOSP build string. A
/// Samsung A12 and a Xiaomi Redmi 9C both report `SP1A.210812.016`, so device
/// approval would have authorised every handset on that Android build rather
/// than the one an administrator approved.
///
/// Instead an identifier is generated once and stored locally. It is:
///  * unique per install, so approval means what it says;
///  * stable across launches and app updates;
///  * reset by a reinstall or by clearing app data, which deliberately forces
///    re-approval — losing a device should not leave a live credential.
///
/// The hardware description is kept separately, purely so an administrator can
/// recognise the device in the approval list.
class DeviceService {
  DeviceService._(this.deviceId, this.model);

  final String deviceId;
  final String model;

  static const _deviceIdKey = 'device.installId';

  static DeviceService? _instance;
  static DeviceService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('DeviceService.init() must be awaited before use.');
    }
    return i;
  }

  static Future<DeviceService> init(LocalDatabase database) async {
    final plugin = DeviceInfoPlugin();
    var model = 'UNKNOWN';

    try {
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        model = info.userAgent ?? 'Browser';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        model = '${info.manufacturer} ${info.model}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        model = '${info.name} (${info.utsname.machine})';
      }
    } on Object {
      // A missing description must not stop the app starting; the identifier
      // below is what actually matters.
    }

    var id = await database.readSyncState(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await database.writeSyncState(_deviceIdKey, id);
    }

    return _instance = DeviceService._(id, model);
  }

  /// Masks the trailing characters so the full identifier
  /// could not be copied off the login screen. Preserved, but without the
  /// substring arithmetic that threw on short identifiers.
  String get maskedDeviceId => maskIdentifier(deviceId);

  static String maskIdentifier(String value, {int visible = 8}) {
    if (value.length <= visible) return value;
    return value.substring(0, visible) + 'X' * (value.length - visible);
  }
}
