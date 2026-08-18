import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/auth/data/offline_capable_auth_service.dart';
import 'package:fsa_app/features/auth/data/user_sync_repository.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';

/// Pressing "Sync users" must always be able to repair the device.
///
/// The delta cursor is a promise that everything before it was stored. A
/// handset was found holding 5 of the server's 12 users while reporting
/// "already up to date" — the cursor had moved past accounts that were never
/// written, so the server was only ever asked for newer ones and the missing
/// seven could never arrive. Seven inspectors, unable to sign in without a
/// signal, with no action available to fix it.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// A server holding [names], honouring `since` the way the real one does.
  ({http.Client client, List<String?> sinceSeen}) server(List<String> names) {
    final sinceSeen = <String?>[];
    final client = MockClient((request) async {
      // The id set the handset reconciles against after every sync. Answered
      // before `since` is recorded, so it leaves the assertions about the sync
      // feed below untouched.
      if (request.url.path.endsWith('/ids/')) {
        return http.Response(
          jsonEncode({
            'ids': [for (var i = 0; i < names.length; i++) i + 1],
          }),
          200,
        );
      }

      final since = request.url.queryParameters['since'];
      sinceSeen.add(since);
      // Everyone shares a stamp before the cursor below, so a delta sync
      // legitimately returns nobody.
      final rows = since == null
          ? [
              for (final (i, name) in names.indexed)
                {
                  'id': i + 1,
                  'username': name,
                  'first_name': '',
                  'last_name': '',
                  'email': '',
                  'role_name': 'Inspector',
                  'is_active': true,
                  'is_suspended': false,
                  'offline_verifier': 'pbkdf2\$1\$salt\$hash',
                  'updated_at': '2026-08-03T09:00:00Z',
                },
            ]
          : const [];
      return http.Response(
        jsonEncode({'count': rows.length, 'cursor': null, 'results': rows}),
        200,
      );
    });
    return (client: client, sinceSeen: sinceSeen);
  }

  test('a stale cursor leaves the device short and unable to recover',
      () async {
    final s = server(['a', 'b', 'c']);
    final repo = UserSyncRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: s.client,
    );

    // The device believes it is current, but holds nobody.
    await db.writeSyncState(UserSyncRepository.cursorKey, '2026-08-03T09:30:00Z');

    expect(await repo.sync(), 0, reason: 'the delta path finds nothing new');
    expect(await db.countUsers(), 0, reason: 'and the device is still empty');
  });

  test('the manual button ignores the cursor and repairs it', () async {
    final s = server(['a', 'b', 'c']);
    final auth = OfflineCapableAuthService(
      remote: _UnreachableRemote(),
      database: db,
      syncRepository: UserSyncRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: s.client,
      ),
    );

    await db.writeSyncState(UserSyncRepository.cursorKey, '2026-08-03T09:30:00Z');

    expect(await auth.syncUsers(), 3);
    expect(await db.countUsers(), 3);
    expect(await auth.localUserCount(), 3);
    expect(s.sinceSeen.last, isNull,
        reason: 'the manual sync must not send `since`');
  });

  test('the automatic sync after sign-in stays incremental', () async {
    final s = server(['a', 'b', 'c']);
    final repo = UserSyncRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: s.client,
    );

    await db.writeSyncState(UserSyncRepository.cursorKey, '2026-08-03T09:30:00Z');
    await repo.sync();

    expect(s.sinceSeen.last, '2026-08-03T09:30:00Z',
        reason: 'background syncs stay cheap; only the button re-fetches all');
  });

  test('a second press reports nothing new, because nothing is new', () async {
    final s = server(['a', 'b', 'c']);
    final auth = OfflineCapableAuthService(
      remote: _UnreachableRemote(),
      database: db,
      syncRepository: UserSyncRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: s.client,
      ),
    );

    expect(await auth.syncUsers(), 3, reason: 'a bare device gains three');

    // The button re-fetches everyone, so all three arrive over the wire again
    // — but the device already held them. Counting rows written rather than
    // rows new announced "Added 3 new users" on every press, leaving an
    // inspector to ask which three had supposedly just appeared.
    expect(await auth.syncUsers(), 0);
    expect(await db.countUsers(), 3, reason: 'and nothing was duplicated');
  });
}

/// Stands in for a server that cannot be reached, so sign-in is irrelevant here.
class _UnreachableRemote implements AuthService {
  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async =>
      throw const SocketExceptionish();

  @override
  Future<int> syncUsers() async => 0;

  @override
  Future<int> localUserCount() async => 0;
}

class SocketExceptionish implements Exception {
  const SocketExceptionish();
}
