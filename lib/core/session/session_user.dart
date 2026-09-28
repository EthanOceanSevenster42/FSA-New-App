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

  /// Whether this user may remove captured work.
  ///
  /// An inspector adds inspections and edits them; taking one off the
  /// device is the office's call, because a record that disappears is one
  /// nobody can audit. Everything an inspector needs to correct a mistake —
  /// editing, re-capturing, re-uploading — stays open to them.
  bool get canRemoveRecords => isSystemAdministrator;

  /// What to say when the role does not carry it.
  static const removalRefused =
      'Only a system administrator can remove an inspection. Ask the '
      'office — an inspector can edit it instead.';
}
