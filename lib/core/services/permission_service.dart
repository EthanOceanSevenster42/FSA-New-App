import 'package:geolocator/geolocator.dart';

/// Requests the permissions the app needs, once, at start-up.
///
/// Every inspection is located and evidenced, so asking mid-inspection is the
/// wrong moment: the inspector is standing at a consignment, not reading
/// dialogs. Ask once when the app opens, then capture silently thereafter.
abstract final class PermissionService {
  /// Requests location access. Returns true if the app may read a position.
  ///
  /// Deliberately tolerant: a refusal must not stop the app from starting.
  /// Inspections remain capturable without a fix; the location simply goes
  /// unrecorded, and the Photos step says so.
  static Future<bool> ensureLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } on Object {
      // A platform that cannot answer (or a plugin failure) must not block
      // start-up.
      return false;
    }
  }
}
