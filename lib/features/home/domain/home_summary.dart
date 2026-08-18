import '../../../core/data/local_database.dart';
import '../../../core/session/session_store.dart';
import '../../auth/data/user_sync_repository.dart';

/// Figures shown on the home dashboard.
///
/// Every field is either read from the local store or explicitly marked as not
/// yet recorded. Nothing here is a placeholder number — a dashboard that
/// invents counts is worse than no dashboard, because an inspector will act
/// on it.
class HomeSummary {
  const HomeSummary({
    required this.offlineUsers,
    required this.lastSyncAt,
    this.inspectionsToday = 0,
    this.pendingUpload = 0,
  });

  const HomeSummary.empty()
      : offlineUsers = 0,
        lastSyncAt = null,
        inspectionsToday = 0,
        pendingUpload = 0;

  /// Users that can sign in on this handset without a network.
  final int offlineUsers;

  /// When the device last completed a user sync. Null means never.
  final DateTime? lastSyncAt;

  /// Inspections captured today on this handset.
  ///
  /// A real count, including zero. It used to be left null and drawn as "—",
  /// which reads as "not working" — an inspector who has genuinely done none
  /// today should be shown 0, not a dash.
  final int inspectionsToday;

  /// Inspections and directions captured here that the server does not have.
  /// Zero is the normal, reassuring answer.
  final int pendingUpload;

  bool get hasSynced => lastSyncAt != null;

  static Future<HomeSummary> load(LocalDatabase database) async {
    final users = await database.countUsers();
    final raw = await database.readSyncState(UserSyncRepository.lastSyncAtKey);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    // Scoped to the signed-in inspector, like every other list in the app.
    // Left unscoped, the dashboard reported the whole handset's work as the
    // reader's own — so on a shared device "Inspections today" counted someone
    // else's, and "Pending upload" showed a queue this account could not send.
    final owner = await database.readSyncState(SessionStore.userKey);
    final mine = owner != null && owner.isNotEmpty;

    final inspections = mine
        ? await (database.select(database.eggInspections)
              ..where((t) => t.inspectorUsername.equals(owner)))
            .get()
        : <EggInspection>[];
    final directions = mine
        ? await (database.select(database.eggDirections)
              ..where((t) => t.inspectorUsername.equals(owner)))
            .get()
        : <EggDirection>[];

    return HomeSummary(
      offlineUsers: users,
      lastSyncAt: raw == null ? null : DateTime.tryParse(raw)?.toLocal(),
      // Drafts are excluded: half a capture is not an inspection done.
      inspectionsToday: inspections
          .where((i) =>
              i.status == 'completed' &&
              !i.inspectedAt.toLocal().isBefore(startOfDay))
          .length,
      // Everything finished that the server has not acknowledged, whenever it
      // was captured — a record stuck from yesterday still needs sending.
      pendingUpload: inspections
              .where((i) => i.status == 'completed' && !i.isUploaded)
              .length +
          directions
              .where((d) => d.status == 'completed' && !d.isUploaded)
              .length,
    );
  }
}
