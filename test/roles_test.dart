import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/session/session_user.dart';

/// Who may do what.
///
/// An inspector adds inspections and edits them. Removing one is the
/// office's call: a record that disappears off a handset is one nobody can
/// audit, and the inspector who made a mistake can correct it by editing.
void main() {
  const inspector = SessionUser(userName: 'Cinga', roleName: 'Inspector');
  const admin =
      SessionUser(userName: 'Ethan', roleName: 'System Administrator');

  test('an inspector cannot remove captured work', () {
    expect(inspector.canRemoveRecords, isFalse);
  });

  test('a system administrator can', () {
    expect(admin.canRemoveRecords, isTrue);
  });

  test('the role is read regardless of case or padding', () {
    const same = SessionUser(
        userName: 'Ethan', roleName: '  system ADMINISTRATOR  ');
    expect(same.canRemoveRecords, isTrue);
  });

  test('an unknown role is treated as an inspector, not an administrator', () {
    const other = SessionUser(userName: 'Ben', roleName: 'Office');
    expect(other.canRemoveRecords, isFalse,
        reason: 'the safe default is the one that removes nothing');
  });

  test('the refusal says who can do it and what the inspector can do', () {
    expect(SessionUser.removalRefused, contains('system administrator'));
    expect(SessionUser.removalRefused, contains('edit'));
  });
}
