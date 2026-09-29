import 'dart:convert';

import 'package:http/http.dart' as http;

/// Tells the server which build this handset runs, so the office can see
/// who is on which version (Ethan, 2026-09-29).
///
/// Signing in online reports it too, but a session carried over from the
/// day before, or one begun with no signal, never reaches the login
/// endpoint. Every sync therefore reports it again: one small request.
class VersionReport {
  VersionReport({
    required this.baseUrl,
    required this.appVersion,
    required this.deviceId,
    required this.deviceModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;

  /// As the login screen shows it, e.g. "1.0.1.2176".
  final String appVersion;
  final String deviceId;
  final String deviceModel;
  final http.Client _client;

  /// Returns true when the server took it.
  Future<bool> send({required String token}) async {
    if (baseUrl.isEmpty || appVersion.isEmpty) return false;
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/auth/app-version/'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'app_version': appVersion,
            'device_id': deviceId,
            'device_model': deviceModel,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return response.statusCode == 200;
  }
}
