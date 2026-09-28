/// Outcome of a sign-in attempt.
///
/// An explicit type rather than a chain of `if` branches, so the UI handles
/// each case exactly once and the compiler enforces exhaustiveness.
enum AuthOutcome {
  success,

  /// Username/password did not match a local record.
  invalidCredentials,

  /// Account exists but has been suspended.
  accountSuspended,

  /// Account exists but is no longer active.
  accountInactive,

  // NOTE: there is deliberately no `deviceNotRegistered`. Refusing to sign an
  // inspector in until an administrator has approved their handset blocks
  // people from working. Handsets are recorded server-side for visibility,
  // but they do not gate sign-in.

  /// Unexpected failure. Carries a message rather than being swallowed into a
  /// generic 'try again'.
  failure,
}

class AuthResult {
  const AuthResult(
    this.outcome, {
    this.userId,
    this.roleName,
    this.message,
    this.accessToken,
    this.refreshToken,
  });

  final AuthOutcome outcome;
  final String? userId;
  final String? roleName;
  final String? message;

  /// JWT from an online sign-in. Null for an offline sign-in — which is why
  /// upload is only offered once the device has been online at least once.
  final String? accessToken;

  /// Outlives the access token by weeks, and is what lets a handset mint a
  /// fresh one without asking the inspector to sign in again. The access token
  /// expires in hours; an inspector can be in the field for days.
  final String? refreshToken;

  bool get isSuccess => outcome == AuthOutcome.success;
}

/// Sign-in boundary.
///
/// The real implementation authenticates against the local store (offline-first,
/// as inspectors work without signal) and reconciles with the server on sync.
/// That store does not exist yet, so [LocalStubAuthService] stands in and every
/// caller is already written against this interface.
abstract interface class AuthService {
  Future<AuthResult> signIn(
      {required String username, required String password});

  /// "First Time User" — pulls the organisation's user list so a user who has
  /// never signed in on this handset can be authenticated offline afterwards.
  ///
  /// Returns the number of user records written, so the UI can confirm that
  /// something actually arrived, rather than reporting success
  /// unconditionally including when nothing was synced.
  ///
  /// Note this is a *delta*: the sync asks the server only for accounts changed
  /// since the last one. A return of 0 means "nothing new", not "nothing here" —
  /// pair it with [localUserCount] before telling anyone what they have.
  Future<int> syncUsers();

  /// How many users are stored on this handset and can sign in without signal.
  ///
  /// Exists because [syncUsers] alone cannot answer "what do I have?", and a
  /// message built from the delta alone misreports a routine no-op sync as an
  /// empty device.
  Future<int> localUserCount();
}

/// Placeholder implementation so the login screen is runnable before the data
/// layer lands. Accepts any non-empty credentials.
///
/// TODO(auth): replace with the Drift-backed store + Django token exchange.
class LocalStubAuthService implements AuthService {
  const LocalStubAuthService();

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (username.isEmpty || password.isEmpty) {
      return const AuthResult(AuthOutcome.invalidCredentials);
    }
    return AuthResult(
      AuthOutcome.success,
      userId: username,
      roleName: 'Inspector',
    );
  }

  @override
  Future<int> syncUsers() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return 0;
  }

  @override
  Future<int> localUserCount() async => 0;
}
