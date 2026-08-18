/// Who is signed in, carried from the login result into the feature modules.
///
/// Immutable and passed down the tree, so a page can read the role but cannot
/// promote itself.
class SessionUser {
  const SessionUser({required this.userName, required this.roleName});

  final String userName;
  final String roleName;

  /// Gates the bulk export-status actions on the management screens.
  ///
  /// UI convenience only — it hides buttons, it does not protect data. The
  /// server authorises every write independently.
  bool get isSystemAdministrator =>
      roleName.trim().toLowerCase() == 'system administrator';
}
