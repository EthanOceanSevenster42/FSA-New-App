import 'dart:async';

import '../../../core/data/local_database.dart';
import '../../../core/security/password_verifier.dart';
import '../domain/auth_service.dart';
import 'user_sync_repository.dart';

/// Offline-first sign-in.
///
/// Tries the server first — it is authoritative, and only it can approve a
/// handset. If the server cannot be reached, falls back to the locally synced
/// users so an inspector in the field is never locked out. That is the whole
/// point of the "First time on this device" sync.
///
/// Order matters: server first, not local-first, so account suspensions and
/// device revocations take effect the moment a device has signal.
class OfflineCapableAuthService implements AuthService {
  OfflineCapableAuthService({
    required this.remote,
    required this.database,
    required this.syncRepository,
  });

  /// Where the JWT from an online sign-in is kept, so uploads can authenticate
  /// after the app has been reopened.
  static const accessTokenKey = 'auth.accessToken';

  /// The long-lived token used to mint a new access token when the short one
  /// runs out. Without it, uploads stop working silently a few hours after
  /// sign-in and the inspector is told their work "will upload automatically".
  static const refreshTokenKey = 'auth.refreshToken';

  final AuthService remote;
  final LocalDatabase database;
  final UserSyncRepository syncRepository;

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final result =
          await remote.signIn(username: username, password: password);
      // A reachable server is authoritative — including for rejections.
      if (result.outcome != AuthOutcome.failure) {
        // Persist the token so captured work can be uploaded later, possibly
        // after the app has been closed and reopened offline.
        if (result.accessToken != null) {
          await database.writeSyncState(accessTokenKey, result.accessToken!);
        }
        if (result.refreshToken != null) {
          await database.writeSyncState(refreshTokenKey, result.refreshToken!);
        }
        // Opportunistically refresh the offline store so the next sign-in
        // works without signal. Never let this failure break a good login.
        unawaited(syncRepository.sync().catchError((_) => 0));
        return result;
      }
    } on Object {
      // Unreachable/timed out — fall through to the local store.
    }

    return _signInOffline(username: username, password: password);
  }

  Future<AuthResult> _signInOffline({
    required String username,
    required String password,
  }) async {
    final user = await database.findUser(username);
    if (user == null || user.offlineVerifier.isEmpty) {
      // Never synced, or synced before verifiers existed. Cannot prove
      // identity, so refuse rather than guess.
      return const AuthResult(AuthOutcome.invalidCredentials);
    }

    final matches = await PasswordVerifier.verify(
      password,
      user.offlineVerifier,
    );
    if (!matches) return const AuthResult(AuthOutcome.invalidCredentials);

    // Same precedence as the server, so an inspector sees the same message
    // whether or not they have signal.
    if (user.isSuspended) return const AuthResult(AuthOutcome.accountSuspended);
    if (!user.isActive) return const AuthResult(AuthOutcome.accountInactive);

    return AuthResult(
      AuthOutcome.success,
      userId: user.username,
      roleName: user.roleName,
      message: 'Signed in offline.',
    );
  }

  @override

  /// The "Sync users" button. Deliberately a full re-fetch — see
  /// [UserSyncRepository.sync]. The automatic sync after a successful sign-in
  /// stays incremental.
  Future<int> syncUsers() => syncRepository.sync(fromScratch: true);

  @override
  Future<int> localUserCount() => database.countUsers();
}
