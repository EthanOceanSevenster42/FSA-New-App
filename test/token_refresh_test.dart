import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Uploads must not stop working the moment the access token lapses.
///
/// The access token lives about half a day; an inspector can be out for
/// several. Until now the handset kept only that token and threw the refresh
/// token away, so once it expired every upload silently did nothing while the
/// app told the inspector their work "will upload automatically as soon as you
/// are back online". It never would.
String jwt({required Duration expiresIn}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().toUtc().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return '${seg({'alg': 'HS256'})}.${seg({'exp': exp})}.signature';
}

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  EggsRepository repo({http.Client? client}) => EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: client,
      );

  test('a token still in date is used as it is', () async {
    final good = jwt(expiresIn: const Duration(hours: 6));
    await db.writeSyncState('auth.accessToken', good);

    expect(await repo().storedToken(), good);
  });

  test('an expired token is exchanged for a new one', () async {
    await db.writeSyncState('auth.accessToken', jwt(expiresIn: const Duration(hours: -1)));
    await db.writeSyncState('auth.refreshToken', jwt(expiresIn: const Duration(days: 20)));
    final minted = jwt(expiresIn: const Duration(hours: 12));

    var refreshCalls = 0;
    final r = repo(
      client: MockClient((request) async {
        if (request.url.path.contains('refresh')) {
          refreshCalls++;
          return http.Response(jsonEncode({'access': minted}), 200);
        }
        return http.Response('{}', 404);
      }),
    );

    expect(await r.storedToken(), minted);
    expect(refreshCalls, 1);
    // …and kept, so the next upload does not refresh again.
    expect(await db.readSyncState('auth.accessToken'), minted);
  });

  test('a rotated refresh token replaces the old one', () async {
    await db.writeSyncState('auth.accessToken', jwt(expiresIn: const Duration(hours: -1)));
    await db.writeSyncState('auth.refreshToken', jwt(expiresIn: const Duration(days: 20)));
    final rotated = jwt(expiresIn: const Duration(days: 30));

    final r = repo(
      client: MockClient((_) async => http.Response(
            jsonEncode({'access': jwt(expiresIn: const Duration(hours: 12)),
                        'refresh': rotated}),
            200,
          )),
    );

    await r.storedToken();
    expect(await db.readSyncState('auth.refreshToken'), rotated);
  });

  group('when there is no way to authenticate', () {
    test('a handset that has never signed in online has no token', () async {
      // Exactly the state a restored session leaves behind: the app knows who
      // the inspector is, but holds no credentials for the server.
      expect(await repo().storedToken(), isNull);
    });

    test('an expired refresh token is not even tried', () async {
      await db.writeSyncState('auth.accessToken', jwt(expiresIn: const Duration(hours: -1)));
      await db.writeSyncState('auth.refreshToken', jwt(expiresIn: const Duration(days: -1)));

      var called = false;
      final r = repo(client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));

      expect(await r.storedToken(), isNull);
      expect(called, isFalse, reason: 'no point asking with a dead token');
    });

    test('a refused refresh yields null rather than a bad token', () async {
      await db.writeSyncState('auth.accessToken', jwt(expiresIn: const Duration(hours: -1)));
      await db.writeSyncState('auth.refreshToken', jwt(expiresIn: const Duration(days: 20)));

      final r = repo(
        client: MockClient((_) async => http.Response('{"detail":"invalid"}', 401)),
      );

      expect(await r.storedToken(), isNull);
    });

    test('a token whose expiry cannot be read is still sent', () async {
      // The expiry check only skips a round trip that is certain to fail. If
      // it cannot be read, the server decides — refusing to try would strand
      // an inspector over a parsing quirk rather than a real rejection.
      await db.writeSyncState('auth.accessToken', 'not-a-jwt');
      expect(await repo().storedToken(), 'not-a-jwt');
    });
  });
}
