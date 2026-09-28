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

    if (!mine) {
      return HomeSummary(
        offlineUsers: users,
        lastSyncAt: raw == null ? null : DateTime.tryParse(raw)?.toLocal(),
      );
    }

    // One shape for every commodity, so the dashboard counts the whole
    // handset's work. It used to read the egg tables only, which is why an
    // inspector who had just captured and sent a raw or poultry inspection
    // was still shown "0 captured today".
    final captured = <_Captured>[];

    for (final r in await (database.select(database.eggInspections)
          ..where((t) => t.inspectorUsername.equals(owner)))
        .get()) {
      captured.add((
        key: 'egg:${r.clientUuid}',
        status: r.status,
        at: r.inspectedAt,
        uploaded: r.isUploaded,
        grouped: r.visitUuid.isNotEmpty,
      ));
    }
    for (final r in await (database.select(database.poultryInspections)
          ..where((t) => t.inspectorUsername.equals(owner)))
        .get()) {
      captured.add((
        key: 'poultry:${r.clientUuid}',
        status: r.status,
        at: r.inspectedAt,
        uploaded: r.isUploaded,
        grouped: r.visitUuid.isNotEmpty,
      ));
    }
    // The label checklist belongs to the same poultry product as the grading
    // record, so it shares its key and the two count once between them.
    for (final r in await (database.select(database.poultryLabelInspections)
          ..where((t) => t.inspectorUsername.equals(owner)))
        .get()) {
      captured.add((
        key: 'poultry:${r.clientUuid}',
        status: r.status,
        at: r.inspectedAt,
        uploaded: r.isUploaded,
        grouped: r.visitUuid.isNotEmpty,
      ));
    }
    for (final r in await (database.select(database.pmpInspections)
          ..where((t) => t.inspectorUsername.equals(owner)))
        .get()) {
      captured.add((
        key: 'pmp:${r.clientUuid}',
        status: r.status,
        at: r.inspectedAt,
        uploaded: r.isUploaded,
        grouped: r.visitUuid.isNotEmpty,
      ));
    }
    for (final r in await (database.select(database.rawRmpInspections)
          ..where((t) => t.inspectorUsername.equals(owner)))
        .get()) {
      captured.add((
        key: 'rawrmp:${r.clientUuid}',
        status: r.status,
        at: r.inspectedAt,
        uploaded: r.isUploaded,
        grouped: r.visitUuid.isNotEmpty,
      ));
    }

    final doneToday = <String>{};
    final waiting = <String>{};
    for (final one in captured) {
      // Drafts are excluded: half a capture is not an inspection done.
      //
      // `ready` counts. Inside a grouped inspection a finished record waits
      // as `ready` until the one sign-off at the end submits the group, so
      // counting only `completed` showed an inspector 0 all morning while
      // they worked through a store — the tile says "captured today", and a
      // ready record is captured.
      if (one.status != 'completed' && one.status != 'ready') continue;
      if (!one.at.toLocal().isBefore(startOfDay)) doneToday.add(one.key);
      // A record inside a group travels with the group, not on its own, so
      // the group is what is counted as waiting — otherwise every grouped
      // inspection would sit in the queue for ever, already sent.
      if (!one.uploaded && !one.grouped) waiting.add(one.key);
    }

    // Signed-off groups the office has not acknowledged.
    final groups = await (database.select(database.storeVisits)
          ..where((t) => t.inspectorUsername.equals(owner))
          ..where((t) => t.completedAt.isNotNull())
          ..where((t) => t.isUploaded.equals(false)))
        .get();

    // Directions are captured work too, and are sent the same way.
    var directions = 0;
    for (final rows in [
      await (database.select(database.eggDirections)
            ..where((t) => t.inspectorUsername.equals(owner)))
          .get()
          .then((r) => [for (final d in r) (d.status, d.isUploaded)]),
      await (database.select(database.poultryDirections)
            ..where((t) => t.inspectorUsername.equals(owner)))
          .get()
          .then((r) => [for (final d in r) (d.status, d.isUploaded)]),
      await (database.select(database.pmpDirections)
            ..where((t) => t.inspectorUsername.equals(owner)))
          .get()
          .then((r) => [for (final d in r) (d.status, d.isUploaded)]),
      await (database.select(database.rawRmpDirections)
            ..where((t) => t.inspectorUsername.equals(owner)))
          .get()
          .then((r) => [for (final d in r) (d.status, d.isUploaded)]),
    ]) {
      directions += rows.where((d) => d.$1 == 'completed' && !d.$2).length;
    }

    return HomeSummary(
      offlineUsers: users,
      lastSyncAt: raw == null ? null : DateTime.tryParse(raw)?.toLocal(),
      inspectionsToday: doneToday.length,
      pendingUpload: waiting.length + groups.length + directions,
    );
  }
}

/// One captured inspection, whatever commodity it belongs to.
typedef _Captured = ({
  String key,
  String status,
  DateTime at,
  bool uploaded,
  bool grouped,
});
