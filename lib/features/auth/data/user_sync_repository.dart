import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';

/// Downloads organisation users and persists them for offline sign-in.
///
/// Uses a single cursor-based endpoint rather than a pattern of
/// four hand-rolled endpoints per entity (`GetX`, `GetXInBlocks`,
/// `GetXBlockSize`, `GetXSinceLastDate`).
class UserSyncRepository {
  UserSyncRepository({
    required this.baseUrl,
    required this.database,
    http.Client? client,
    this.pageSize = 200,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  static const cursorKey = 'users.cursor';

  /// Wall-clock time of the last successful sync. The cursor is a server
  /// `updated_at` value, which is not the same thing and is useless for
  /// telling an inspector how stale their device is.
  static const lastSyncAtKey = 'users.lastSyncAt';

  final String baseUrl;
  final LocalDatabase database;
  final int pageSize;
  final Duration timeout;
  final http.Client _client;

  /// Pulls everything changed since the stored cursor and returns how many
  /// users were new to this device — not how many rows were written. The two
  /// diverge on the manual button below, which re-fetches everyone: rows
  /// written is then always the full organisation, and reporting that as the
  /// number added announced "5 new users" on every press.
  ///
  /// A full sync happens automatically the first time, because the cursor is
  /// absent.
  ///
  /// [fromScratch] ignores the cursor and re-fetches every user. The cursor is
  /// a promise that everything before it was stored; if that promise is ever
  /// broken — a write that failed, a sync cut short, local data cleared while
  /// the cursor survived — the missing users become unreachable, because the
  /// server is only ever asked for newer ones. A handset was found holding 5 of
  /// 12 users while cheerfully reporting "already up to date", and no amount of
  /// pressing Sync users could have repaired it.
  ///
  /// So the manual button re-fetches everything. It is a rare, deliberate act,
  /// the payload is small, and it is precisely what someone presses when they
  /// suspect something is wrong. The automatic sync after sign-in still uses
  /// the cursor.
  Future<int> sync({bool fromScratch = false}) async {
    var added = 0;
    var cursor = fromScratch ? null : await database.readSyncState(cursorKey);

    // Loop until the server stops returning rows, so a large first sync is not
    // silently truncated to one page.
    while (true) {
      final uri = Uri.parse('$baseUrl/api/auth/sync-users/').replace(
        queryParameters: {
          'limit': '$pageSize',
          if (cursor != null && cursor.isNotEmpty) 'since': cursor,
        },
      );

      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Sync failed with status ${response.statusCode}.',
          uri,
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      if (results.isEmpty) break;

      added += await database.upsertUsers(results.map(_toCompanion).toList());

      final next = body['cursor'] as String?;
      // Guard against a server that returns the same cursor forever.
      if (next == null || next == cursor) break;
      cursor = next;
      await database.writeSyncState(cursorKey, cursor);

      if (results.length < pageSize) break;
    }

    // Additions and updates arrive above. Removals cannot: a row deleted on
    // the server changes nothing a cursor can see, and even a full re-fetch
    // only ever writes what it is given. Reconcile explicitly, so an inspector
    // removed centrally stops being able to sign in here too.
    await pruneDeleted();

    await database.writeSyncState(
      lastSyncAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return added;
  }

  /// Drops locally held users the server no longer lists. Returns how many.
  ///
  /// Deliberately part of every sync, not just the manual button: an account
  /// removed in Admin must lose its offline credential at the next opportunity,
  /// and signing in is the opportunity that reliably happens.
  ///
  /// Throws if the set cannot be fetched. A sync that could not check for
  /// revocations has not finished, and reporting success would be a lie about
  /// the one thing this protects.
  Future<int> pruneDeleted() async {
    final uri = Uri.parse('$baseUrl/api/auth/sync-users/ids/');
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Reconcile failed with status ${response.statusCode}.',
        uri,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final ids = (body['ids'] as List<dynamic>? ?? const []).cast<int>();

    // An empty set is far likelier a misconfigured base URL, an empty
    // database or a half-written response than an organisation that genuinely
    // employs nobody — and acting on it strips every handset of offline
    // sign-in at once, in the field, with no way back without signal.
    // Deleting the last inspector is not a case worth optimising for; wrongly
    // wiping a working device is a case worth refusing.
    if (ids.isEmpty) return 0;

    return database.deleteUsersNotIn(ids);
  }

  static SyncedUsersCompanion _toCompanion(Map<String, dynamic> json) =>
      SyncedUsersCompanion.insert(
        id: Value(json['id'] as int),
        username: json['username'] as String,
        firstName: Value(json['first_name'] as String? ?? ''),
        lastName: Value(json['last_name'] as String? ?? ''),
        email: Value(json['email'] as String? ?? ''),
        roleName: Value(json['role_name'] as String?),
        isActive: Value(json['is_active'] as bool? ?? true),
        isSuspended: Value(json['is_suspended'] as bool? ?? false),
        offlineVerifier: Value(json['offline_verifier'] as String? ?? ''),
        updatedAt: Value(json['updated_at'] as String? ?? ''),
      );

  void dispose() => _client.close();
}
