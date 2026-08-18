import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/auth/data/offline_capable_auth_service.dart';
import 'package:fsa_app/features/auth/data/user_sync_repository.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';

/// Removing an inspector centrally must remove them from the handsets.
///
/// The sync feed only ever answers "what changed since this cursor", and a
/// deleted row changes nothing it can see — so a user removed on the server
/// kept a salted, stretched and entirely valid offline credential on every
/// device that had ever synced them, and could go on signing in with no signal
/// indefinitely. Suspending an account propagated correctly, because the row
/// survived to carry the flag; deleting one did not, because nothing was left
/// to carry anything.
///
/// So the client reconciles against the server's id set on every sync.

/// A real credential for the password below, at a deliberately cheap iteration
/// count — the production verifier uses 150,000 and would make this file slow
/// for no extra confidence.
const _verifier =
    r'pbkdf2_sha256$1000$MDEyMzQ1Njc4OWFiY2RlZg==$tiKWHy4FAGCWE8gn6GtKhaxD2OeeAUUWXFT/p1aaNl8=';
const _password = 'secret';

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// A server whose roll can change between syncs. Mutate the returned list to
  /// hire and remove people.
  ({http.Client client, List<int> roll}) server(List<int> initial) {
    final roll = [...initial];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/ids/')) {
        return http.Response(jsonEncode({'ids': roll}), 200);
      }
      return http.Response(
        jsonEncode({
          'count': roll.length,
          'cursor': null,
          'results': [
            for (final id in roll)
              {
                'id': id,
                'username': 'user$id',
                'first_name': '',
                'last_name': '',
                'email': '',
                'role_name': 'Inspector',
                'is_active': true,
                'is_suspended': false,
                'offline_verifier': _verifier,
                'updated_at': '2026-08-03T09:00:00Z',
              },
          ],
        }),
        200,
      );
    });
    return (client: client, roll: roll);
  }

  UserSyncRepository repoFor(http.Client client) => UserSyncRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: client,
      );

  test('a user removed on the server is dropped from the device', () async {
    final s = server([1, 2, 3]);
    final repo = repoFor(s.client);

    await repo.sync(fromScratch: true);
    expect(await db.countUsers(), 3);

    s.roll.remove(2);
    await repo.sync(fromScratch: true);

    expect(await db.countUsers(), 2);
    expect(await db.findUser('user2'), isNull, reason: 'the removed account');
    expect(await db.findUser('user1'), isNotNull, reason: 'and not the others');
    expect(await db.findUser('user3'), isNotNull);
  });

  test('a removed user can no longer sign in offline', () async {
    final s = server([1, 2]);
    final auth = OfflineCapableAuthService(
      remote: _UnreachableRemote(),
      database: db,
      syncRepository: repoFor(s.client),
    );

    await auth.syncUsers();

    // Establish the credential really did work, or the assertion below proves
    // nothing more than a typo in the password.
    var result = await auth.signIn(username: 'user2', password: _password);
    expect(result.outcome, AuthOutcome.success);

    s.roll.remove(2);
    await auth.syncUsers();

    result = await auth.signIn(username: 'user2', password: _password);
    expect(result.outcome, AuthOutcome.invalidCredentials);

    // The inspector who is still employed is unaffected.
    result = await auth.signIn(username: 'user1', password: _password);
    expect(result.outcome, AuthOutcome.success);
  });

  test('the delta sync after sign-in revokes too, not just the button',
      () async {
    final s = server([1, 2]);
    final repo = repoFor(s.client);

    await repo.sync(fromScratch: true);
    s.roll.remove(2);

    // No `fromScratch`: this is the cheap sync that follows a successful
    // online sign-in, and it must still notice the removal.
    await repo.sync();

    expect(await db.findUser('user2'), isNull);
  });

  test('an empty id set is refused rather than wiping the device', () async {
    final s = server([1, 2, 3]);
    final repo = repoFor(s.client);

    await repo.sync(fromScratch: true);
    expect(await db.countUsers(), 3);

    // A misconfigured base URL, an empty database or a half-written response
    // all look like this. Acting on it would strip every handset of offline
    // sign-in at once, in the field, with no way back without signal.
    s.roll.clear();
    expect(await repo.pruneDeleted(), 0);
    expect(await db.countUsers(), 3, reason: 'nobody was removed');
  });

  test('a sync that cannot check for revocations fails rather than reporting success',
      () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/ids/')) {
        return http.Response('nope', 503);
      }
      return http.Response(
        jsonEncode({'count': 0, 'cursor': null, 'results': const []}),
        200,
      );
    });

    await expectLater(repoFor(client).sync(fromScratch: true), throwsA(isA<http.ClientException>()));
  });
}

/// Stands in for a server that cannot be reached, forcing the offline path.
class _UnreachableRemote implements AuthService {
  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async =>
      throw const _Unreachable();

  @override
  Future<int> syncUsers() async => 0;

  @override
  Future<int> localUserCount() async => 0;
}

class _Unreachable implements Exception {
  const _Unreachable();
}
