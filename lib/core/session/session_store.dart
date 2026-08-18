import '../data/local_database.dart';
import 'session_user.dart';

/// Remembers who is signed in, across restarts of the process.
///
/// Android reclaims memory by killing whatever is in the background, and the
/// camera is the hungriest thing an inspector opens. On a 2 GB handset,
/// photographing a label routinely kills this app; Flutter then restarts from
/// `main()`. With nothing persisted, that put the inspector back at the
/// sign-in screen mid-inspection — which reads as the app having logged them
/// out for no reason, and out in the field may mean no signal to sign back in.
///
/// The session is stored alongside the offline user records that already make
/// signing in without a signal possible, so restoring it grants nothing that a
/// fresh sign-in on the same handset would not.
class SessionStore {
  const SessionStore(this._database);

  final LocalDatabase _database;

  /// Where the signed-in username lives in `sync_state`.
  ///
  /// Public because ownership of captured work is keyed on it: the eggs
  /// repository and the home dashboard both scope their queries to whoever
  /// this names. One definition, so the three cannot drift apart.
  static const userKey = 'session.userName';
  static const _roleKey = 'session.roleName';
  static const _atKey = 'session.signedInAt';

  /// How long a restored session stays valid without signing in again.
  ///
  /// Long enough to cover a multi-day trip out of signal, short enough that a
  /// mislaid handset is not open indefinitely.
  static const maxAge = Duration(days: 7);

  Future<void> save(SessionUser user, {DateTime? now}) async {
    await _database.writeSyncState(userKey, user.userName);
    await _database.writeSyncState(_roleKey, user.roleName);
    await _database.writeSyncState(
      _atKey,
      (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
  }

  Future<void> clear() async {
    await _database.writeSyncState(userKey, '');
    await _database.writeSyncState(_roleKey, '');
    await _database.writeSyncState(_atKey, '');
  }

  /// The stored session, or null if there is none or it has aged out.
  Future<SessionUser?> restore({DateTime? now}) async {
    final userName = await _database.readSyncState(userKey);
    if (userName == null || userName.isEmpty) return null;

    final at = await _database.readSyncState(_atKey);
    final signedInAt = at == null ? null : DateTime.tryParse(at);
    // No timestamp means the record is malformed; treat it as no session
    // rather than as one that never expires.
    if (signedInAt == null) return null;
    if ((now ?? DateTime.now()).toUtc().difference(signedInAt) > maxAge) {
      return null;
    }

    return SessionUser(
      userName: userName,
      roleName: await _database.readSyncState(_roleKey) ?? 'Inspector',
    );
  }
}
