import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/features/auth/data/api_auth_service.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ApiAuthService _serviceReturning(
  String body, {
  int status = 200,
  void Function(http.Request)? onRequest,
}) =>
    ApiAuthService(
      baseUrl: 'http://example.test',
      deviceId: 'DEVICE-123',
      deviceModel: 'Xiaomi M2004J19C',
      client: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          body,
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

void main() {
  group('outcome mapping', () {
    // Every string here must exist in accounts/views.py. If the server adds an
    // outcome and this map is not updated, the client reports `failure` with a
    // diagnostic rather than silently treating it as a login success.
    const cases = <String, AuthOutcome>{
      'invalid_credentials': AuthOutcome.invalidCredentials,
      'account_suspended': AuthOutcome.accountSuspended,
      'account_inactive': AuthOutcome.accountInactive,
    };

    cases.forEach((wire, expected) {
      test('"$wire" maps to $expected', () async {
        final service = _serviceReturning(jsonEncode({'outcome': wire}));
        final result = await service.signIn(username: 'u', password: 'p');
        expect(result.outcome, expected);
      });
    });

    test('success carries the username and role', () async {
      final service = _serviceReturning(
        jsonEncode({
          'outcome': 'success',
          'access': 'token',
          'user': {'username': 'inspector', 'role_name': 'Inspector'},
        }),
      );
      final result = await service.signIn(username: 'u', password: 'p');

      expect(result.isSuccess, isTrue);
      expect(result.userId, 'inspector');
      expect(result.roleName, 'Inspector');
    });

    test('a retired outcome is a failure, never a silent success', () async {
      // `device_not_registered` was removed when handset authorisation was
      // dropped. An old server still sending it must not let anyone through.
      final service =
          _serviceReturning(jsonEncode({'outcome': 'device_not_registered'}));
      final result = await service.signIn(username: 'u', password: 'p');

      expect(result.outcome, AuthOutcome.failure);
    });

    test('an unknown outcome is a failure, never a silent success', () async {
      final service =
          _serviceReturning(jsonEncode({'outcome': 'some_future_state'}));
      final result = await service.signIn(username: 'u', password: 'p');

      expect(result.outcome, AuthOutcome.failure);
      expect(result.message, contains('some_future_state'));
    });

    test('a non-200 response is a failure', () async {
      final service = _serviceReturning('{}', status: 500);
      final result = await service.signIn(username: 'u', password: 'p');

      expect(result.outcome, AuthOutcome.failure);
      expect(result.message, contains('500'));
    });
  });

  test('sends the raw device id, not the masked one', () async {
    http.Request? captured;
    final service = _serviceReturning(
      jsonEncode({'outcome': 'success', 'user': {'username': 'u'}}),
      onRequest: (r) => captured = r,
    );

    await service.signIn(username: 'u', password: 'p');

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['device_id'], 'DEVICE-123');
    expect(body['device_model'], 'Xiaomi M2004J19C');
    expect(captured!.url.path, '/api/auth/login/');
  });

  test('syncUsers throws on a non-200 so the UI can report failure', () async {
    final service = _serviceReturning('{}', status: 503);
    expect(service.syncUsers(), throwsA(isA<http.ClientException>()));
  });
}
