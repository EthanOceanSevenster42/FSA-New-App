import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/auth/data/offline_capable_auth_service.dart';
import 'package:fsa_app/features/auth/data/user_sync_repository.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Real verifier produced by the Django backend for password "inspector123",
/// at a low iteration count so tests stay fast. Same format the server emits.
const _verifier =
    r'pbkdf2_sha256$1000$c2FsdHNhbHRzYWx0MTI=$IwXaOSzGFd6OhmcgGE6Id6YqKZXYjD/onpTqcmq4M3k=';

class _UnreachableRemote implements AuthService {
  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async =>
      throw const SocketishException();

  @override
  Future<int> syncUsers() async => throw const SocketishException();

  @override
  Future<int> localUserCount() async => 0;
}

class SocketishException implements Exception {
  const SocketishException();
}

class _RemoteReturning implements AuthService {
  _RemoteReturning(this.result);
  final AuthResult result;
  int calls = 0;

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    calls++;
    return result;
  }

  @override
  Future<int> syncUsers() async => 0;

  @override
  Future<int> localUserCount() async => 0;
}

void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  UserSyncRepository repoReturning(List<Map<String, dynamic>> pages) {
    var call = 0;
    return UserSyncRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        final page = call < pages.length ? pages[call] : {'results': []};
        call++;
        return http.Response(
          jsonEncode(page),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  Map<String, dynamic> user({
    int id = 1,
    String username = 'inspector',
    bool active = true,
    bool suspended = false,
    String verifier = _verifier,
  }) =>
      {
        'id': id,
        'username': username,
        'first_name': 'Thabo',
        'last_name': 'Mokoena',
        'email': 'inspector@fsa.co.za',
        'role_name': 'Inspector',
        'is_active': active,
        'is_suspended': suspended,
        'offline_verifier': verifier,
        'updated_at': '2026-07-30T10:00:00Z',
      };

  group('sync', () {
    test('persists downloaded users and reports the count', () async {
      final repo = repoReturning([
        {
          'results': [user(), user(id: 2, username: 'supervisor')],
          'cursor': '2026-07-30T10:00:00Z',
        },
      ]);

      expect(await repo.sync(), 2);
      expect(await db.countUsers(), 2);
      expect((await db.findUser('inspector'))?.roleName, 'Inspector');
    });

    test('stores the cursor so the next sync is a delta', () async {
      final repo = repoReturning([
        {
          'results': [user()],
          'cursor': '2026-07-30T10:00:00Z',
        },
      ]);
      await repo.sync();

      expect(
        await db.readSyncState(UserSyncRepository.cursorKey),
        '2026-07-30T10:00:00Z',
      );
    });

    test('is idempotent — re-syncing the same user updates, not duplicates',
        () async {
      final page = {
        'results': [user()],
        'cursor': 'a',
      };
      await repoReturning([page]).sync();
      await repoReturning([page]).sync();

      expect(await db.countUsers(), 1);
    });

    test('does not loop forever when the server repeats a cursor', () async {
      final repo = repoReturning([
        {
          'results': [user()],
          'cursor': 'same',
        },
        {
          'results': [user(id: 2, username: 'b')],
          'cursor': 'same',
        },
      ]);
      // Terminates rather than hanging.
      expect(await repo.sync(), 1);
    });

    test('throws on a server error so the UI reports failure', () {
      final repo = UserSyncRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      expect(repo.sync(), throwsA(isA<http.ClientException>()));
    });
  });

  group('offline sign-in', () {
    Future<void> seed({
      bool active = true,
      bool suspended = false,
      String verifier = _verifier,
    }) =>
        repoReturning([
          {
            'results': [
              user(active: active, suspended: suspended, verifier: verifier),
            ],
            'cursor': 'a',
          },
        ]).sync();

    OfflineCapableAuthService service(AuthService remote) =>
        OfflineCapableAuthService(
          remote: remote,
          database: db,
          syncRepository: repoReturning([]),
        );

    test('succeeds with the correct password when the server is unreachable',
        () async {
      await seed();
      final result = await service(_UnreachableRemote())
          .signIn(username: 'inspector', password: 'inspector123');

      expect(result.isSuccess, isTrue);
      expect(result.userId, 'inspector');
      expect(result.message, contains('offline'));
    });

    test('rejects a wrong password offline', () async {
      await seed();
      final result = await service(_UnreachableRemote())
          .signIn(username: 'inspector', password: 'wrong');

      expect(result.outcome, AuthOutcome.invalidCredentials);
    });

    test('username match is case-insensitive, as the server is', () async {
      await seed();
      final result = await service(_UnreachableRemote())
          .signIn(username: 'INSPECTOR', password: 'inspector123');

      expect(result.isSuccess, isTrue);
    });

    test('refuses a user who was never synced', () async {
      final result = await service(_UnreachableRemote())
          .signIn(username: 'ghost', password: 'inspector123');

      expect(result.outcome, AuthOutcome.invalidCredentials);
    });

    test('honours suspension offline, matching server precedence', () async {
      await seed(suspended: true);
      final result = await service(_UnreachableRemote())
          .signIn(username: 'inspector', password: 'inspector123');

      expect(result.outcome, AuthOutcome.accountSuspended);
    });

    test('honours inactive offline', () async {
      await seed(active: false);
      final result = await service(_UnreachableRemote())
          .signIn(username: 'inspector', password: 'inspector123');

      expect(result.outcome, AuthOutcome.accountInactive);
    });

    test('a user with a blank verifier can never sign in offline', () async {
      // Guards against a null security stamp causing the
      // app to accept whatever password was typed and store it as the credential.
      await seed(verifier: '');
      final result = await service(_UnreachableRemote())
          .signIn(username: 'inspector', password: 'literally anything');

      expect(result.outcome, AuthOutcome.invalidCredentials);
    });
  });

  group('server precedence', () {
    test('a reachable server rejection is final — no offline second chance',
        () async {
      // Otherwise a suspended inspector could be let in by stale local data.
      await repoReturning([
        {
          'results': [user()],
          'cursor': 'a',
        },
      ]).sync();

      final remote = _RemoteReturning(
        const AuthResult(AuthOutcome.accountSuspended),
      );
      final result = await OfflineCapableAuthService(
        remote: remote,
        database: db,
        syncRepository: repoReturning([]),
      ).signIn(username: 'inspector', password: 'inspector123');

      expect(result.outcome, AuthOutcome.accountSuspended);
      expect(remote.calls, 1);
    });
  });
}
