import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/auth/data/api_auth_service.dart';
import 'package:fsa_app/features/updates/data/version_report.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The office sees which build each inspector runs: the handset says so when
/// it signs in and on every sync (Ethan, 2026-09-29).
void main() {
  test('signing in sends the build the handset runs', () async {
    late Map<String, dynamic> sent;
    final service = ApiAuthService(
      baseUrl: 'http://example.test',
      deviceId: 'DEVICE-123',
      deviceModel: 'Samsung SM-X200',
      appVersion: '1.0.1.2176',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'outcome': 'invalid_credentials'}), 200);
      }),
    );
    await service.signIn(username: 'u', password: 'p');
    expect(sent['app_version'], '1.0.1.2176');
    expect(sent['device_id'], 'DEVICE-123');
  });

  test('without a version the sign-in body is as before', () async {
    late Map<String, dynamic> sent;
    final service = ApiAuthService(
      baseUrl: 'http://example.test',
      deviceId: 'DEVICE-123',
      deviceModel: 'Samsung SM-X200',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'outcome': 'invalid_credentials'}), 200);
      }),
    );
    await service.signIn(username: 'u', password: 'p');
    expect(sent.containsKey('app_version'), isFalse);
  });

  test('a sync reports the version with the inspector\'s token', () async {
    late http.Request seen;
    final report = VersionReport(
      baseUrl: 'http://example.test',
      appVersion: '1.0.1.2176',
      deviceId: 'DEVICE-123',
      deviceModel: 'Samsung SM-X200',
      client: MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'app_version': '1.0.1.2176'}), 200);
      }),
    );
    expect(await report.send(token: 'abc'), isTrue);
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/auth/app-version/');
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(jsonDecode(seen.body), {
      'app_version': '1.0.1.2176',
      'device_id': 'DEVICE-123',
      'device_model': 'Samsung SM-X200',
    });
  });

  test('a server that refuses it is reported as not taken', () async {
    final report = VersionReport(
      baseUrl: 'http://example.test',
      appVersion: '1.0.1.2176',
      deviceId: 'DEVICE-123',
      deviceModel: 'Samsung SM-X200',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    expect(await report.send(token: 'abc'), isFalse);
  });
}
