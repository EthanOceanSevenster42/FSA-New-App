import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// Renewing the access token, without racing and without looping.
///
/// Every list page, the menu, the background sync and Server Sync ask for a
/// token — often in the same second — and the server rotates refresh tokens,
/// so each is single-use. Two callers posting the same one meant the second
/// was refused, and a token the server had called invalid was posted again
/// every two minutes for ever with every upload waiting behind it. A tablet
/// last signed in against the deployed server, then given a build pointed at
/// a local one, sat in exactly that loop (2026-09-23).
void main() {
  late LocalDatabase db;

  /// A JWT whose `exp` is [secondsFromNow] away. Only the payload matters:
  /// the handset reads the expiry without verifying the signature.
  String jwt({required int secondsFromNow}) {
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secondsFromNow;
    String b64(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    return '${b64({'alg': 'HS256'})}.${b64({'exp': exp})}.sig';
  }

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    // An access token that has run out, and a refresh token that has not.
    await db.writeSyncState('auth.accessToken', jwt(secondsFromNow: -600));
    await db.writeSyncState('auth.refreshToken', jwt(secondsFromNow: 86400));
  });
  tearDown(() async => db.close());

  EggsRepository repo(MockClient client) =>
      EggsRepository(database: db, baseUrl: 'https://server.test', client: client);

  test('callers arriving together share one refresh', () async {
    var posts = 0;
    final client = MockClient((request) async {
      posts++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response(
          jsonEncode({
            'access': jwt(secondsFromNow: 3600),
            'refresh': jwt(secondsFromNow: 90000),
          }),
          200);
    });
    final r = repo(client);

    final tokens = await Future.wait([
      r.storedToken(),
      r.storedToken(),
      r.storedToken(),
    ]);

    expect(posts, 1, reason: 'three callers, one refresh on the wire');
    expect(tokens.toSet(), hasLength(1));
    expect(tokens.first, isNotNull);
  });

  test('a token the server refuses is dropped, not retried for ever',
      () async {
    var posts = 0;
    final client = MockClient((request) async {
      posts++;
      return http.Response(
          '{"detail":"Token is invalid","code":"token_not_valid"}', 401);
    });
    final r = repo(client);

    expect(await r.storedToken(), isNull);
    expect(await db.readSyncState('auth.refreshToken'), isEmpty);
    expect(await db.readSyncState('auth.accessToken'), isEmpty);

    // The next ask has nothing to post, so it posts nothing.
    expect(await r.storedToken(), isNull);
    expect(posts, 1);
  });

  test('losing the signal keeps the tokens for next time', () async {
    final client = MockClient((request) async {
      throw http.ClientException('no route to host');
    });
    final r = repo(client);

    expect(await r.storedToken(), isNull);
    expect(await db.readSyncState('auth.refreshToken'), isNotEmpty,
        reason: 'a dropped connection says nothing about the token');
  });

  test('a rotated refresh token replaces the one that was used', () async {
    final rotated = jwt(secondsFromNow: 90000);
    final client = MockClient((request) async => http.Response(
        jsonEncode({'access': jwt(secondsFromNow: 3600), 'refresh': rotated}),
        200));
    await repo(client).storedToken();
    expect(await db.readSyncState('auth.refreshToken'), rotated);
  });
}
