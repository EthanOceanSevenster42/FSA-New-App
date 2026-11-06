import 'local_database.dart';

/// The inspector as every document names them: name and surname (Ethan,
/// 2026-09-30), never the login name — the username only when this device
/// holds no name for them.
extension InspectorName on LocalDatabase {
  Future<String> inspectorFullName(String username) async {
    final login = username.trim();
    if (login.isEmpty) return '';
    final user = await findUser(login);
    final full =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    return full.isEmpty ? login : full;
  }
}
