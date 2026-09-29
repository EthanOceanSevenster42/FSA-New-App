import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_service.dart';

/// [AuthService] backed by the Django/DRF API.
///
/// The server returns an explicit `outcome` string rather than encoding the
/// result in an HTTP status, so business results (suspended, inactive,
/// unapproved handset) are cleanly distinguishable from transport failures.
/// Anything that is *not* a recognised outcome is a genuine error and is
/// allowed to throw.
class ApiAuthService implements AuthService {
  ApiAuthService({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceModel,
    this.appVersion = '',
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String deviceId;
  final String deviceModel;

  /// The build this handset runs, so the office can see who is on which
  /// version. Empty sends nothing.
  final String appVersion;
  final Duration timeout;
  final http.Client _client;

  /// Server outcome strings -> client enum. Kept in one place so a server-side
  /// addition surfaces as an unmapped value here rather than silently
  /// degrading to "failure" in three different call sites.
  static const _outcomes = <String, AuthOutcome>{
    'success': AuthOutcome.success,
    'invalid_credentials': AuthOutcome.invalidCredentials,
    'account_suspended': AuthOutcome.accountSuspended,
    'account_inactive': AuthOutcome.accountInactive,
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    final response = await _client
        .post(
          _uri('/api/auth/login/'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': username,
            'password': password,
            'device_id': deviceId,
            'device_model': deviceModel,
            if (appVersion.isNotEmpty) 'app_version': appVersion,
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      return AuthResult(
        AuthOutcome.failure,
        message: 'Server returned ${response.statusCode}.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final outcome = _outcomes[body['outcome']];

    if (outcome == null) {
      return AuthResult(
        AuthOutcome.failure,
        message: 'Unrecognised server response: ${body['outcome']}.',
      );
    }
    if (outcome != AuthOutcome.success) {
      return AuthResult(outcome);
    }

    final user = body['user'] as Map<String, dynamic>?;
    return AuthResult(
      AuthOutcome.success,
      userId: user?['username'] as String?,
      roleName: user?['role_name'] as String?,
      accessToken: body['access'] as String?,
      refreshToken: body['refresh'] as String?,
    );
  }

  /// Persistence lives in [UserSyncRepository]; this client only speaks HTTP.
  /// In the composed [OfflineCapableAuthService] the repository handles sync,
  /// so this path is only used when the API client is wired up on its own.
  @override

  /// Always 0: this service talks only to the server and owns no local
  /// store. The offline-capable wrapper is what holds synced users.
  Future<int> localUserCount() async => 0;

  @override
  Future<int> syncUsers() async {
    final response =
        await _client.get(_uri('/api/auth/sync-users/')).timeout(timeout);

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Sync failed with status ${response.statusCode}.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['results'] as List<dynamic>? ?? const []).length;
  }

  void dispose() => _client.close();
}
