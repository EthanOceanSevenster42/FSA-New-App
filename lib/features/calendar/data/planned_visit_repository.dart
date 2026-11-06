import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/domain/facility_address.dart';

/// The commodities a planned visit names, as a list.
///
/// They are kept in one column, comma-separated, because nothing queries
/// them — they are read back onto the screen and onto the inspection that
/// is started from the plan. Blanks are dropped so a trailing comma, or a
/// plan saved with nothing chosen, reads as no commodities rather than one
/// empty one.
List<String> commoditiesOf(PlannedVisit plan) => [
      for (final part in plan.commodity.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];

/// The inspector's own entries on the follow-up calendar.
///
/// Reads and writes only; the calendar decides what to do with them. Plans
/// stay on the handset — nothing here is uploaded, because a plan is not a
/// record of anything that happened.
class PlannedVisitRepository {
  PlannedVisitRepository(this.database, {this.baseUrl = '', http.Client? client})
      : _client = client ?? http.Client();

  final LocalDatabase database;

  /// Where the office's copy lives. Empty on a device that has never been
  /// pointed at a server, in which case planning simply stays local.
  final String baseUrl;

  final http.Client _client;

  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whose plans to show.
  ///
  /// The same reading of ownership the inspection tables use: a row with no
  /// owner belongs to whoever is holding the handset, because it was written
  /// before anyone was signed in. Matched without case, so a name typed
  /// `Lwandile.D` at sign-in still finds work saved as `lwandile.d`.
  Expression<bool> _ownedBy(GeneratedColumn<String> column, String? owner) =>
      owner == null || owner.trim().isEmpty
          ? column.isNull() | column.equals('')
          : column.isNull() |
              column.equals('') |
              column.lower().equals(owner.trim().toLowerCase());

  /// Every plan this inspector has made, soonest first.
  Future<List<PlannedVisit>> all(String? inspector) =>
      (database.select(database.plannedVisits)
            ..where((t) =>
                _ownedBy(t.inspectorUsername, inspector) &
                t.removed.equals(false))
            ..orderBy([
              (t) => OrderingTerm(expression: t.plannedFor),
              (t) => OrderingTerm(expression: t.facilityName),
            ]))
          .get();

  Future<PlannedVisit?> byUuid(String uuid) =>
      (database.select(database.plannedVisits)
            ..where((t) => t.uuid.equals(uuid)))
          .getSingleOrNull();

  /// Writes a plan, creating it when [uuid] is null.
  ///
  /// Returns the uuid either way so the caller can go straight back to the
  /// row it just saved.
  Future<String> save({
    String? uuid,
    required String inspector,
    required DateTime plannedFor,
    String facilityName = '',
    String facilityAddress = '',
    String facilityPhone = '',
    List<String> commodities = const [],
    String note = '',
  }) async {
    final now = DateTime.now();
    final id = uuid ?? const Uuid().v4();
    final existing = uuid == null ? null : await byUuid(uuid);
    await database.into(database.plannedVisits).insertOnConflictUpdate(
          PlannedVisitsCompanion.insert(
            uuid: id,
            inspectorUsername: Value(inspector),
            plannedFor: day(plannedFor),
            facilityName: Value(facilityName.trim()),
            // Written back in the one spelling of itself, so the
            // office is not sorting "kzn" from "KwaZulu-Natal" later.
            facilityAddress: Value(FacilityAddress.tidy(facilityAddress)),
            facilityPhone: Value(facilityPhone.trim()),
            commodity: Value([
              for (final c in commodities)
                if (c.trim().isNotEmpty) c.trim(),
            ].join(', ')),
            note: Value(note.trim()),
            // Keep the link to a visit already started from this plan — an
            // inspector correcting the details must not un-start it.
            startedVisitUuid: Value(existing?.startedVisitUuid ?? ''),
            // Changed here, so the office's copy is now behind.
            isUploaded: const Value(false),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Moves a plan to another day — what a drag onto a new date amounts to.
  Future<void> reschedule(String uuid, DateTime to) =>
      (database.update(database.plannedVisits)
            ..where((t) => t.uuid.equals(uuid)))
          .write(PlannedVisitsCompanion(
        plannedFor: Value(day(to)),
        isUploaded: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));

  /// Notes the store visit opened from this plan, which marks it done.
  Future<void> markStarted(String uuid, String visitUuid) =>
      (database.update(database.plannedVisits)
            ..where((t) => t.uuid.equals(uuid)))
          .write(PlannedVisitsCompanion(
        startedVisitUuid: Value(visitUuid),
        isUploaded: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));

  /// Removes a plan.
  ///
  /// Marked rather than deleted, because the office has a copy and has to
  /// be told. The row is hidden from the app immediately and swept off the
  /// device once the server has acknowledged it.
  Future<void> delete(String uuid) =>
      (database.update(database.plannedVisits)
            ..where((t) => t.uuid.equals(uuid)))
          .write(PlannedVisitsCompanion(
        removed: const Value(true),
        isUploaded: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));

  // ---- the office's copy --------------------------------------------------

  /// Plans whose row on the server is out of date, removals included.
  ///
  /// Owner-tolerant in the same way the calendar is: a plan made before a
  /// session was recorded has no owner and still belongs to whoever is
  /// holding the handset. It is never owner-agnostic, though — the server
  /// files each plan under the inspector whose token sent it, so another
  /// inspector's week going up under this one's name would be a lie about
  /// who is doing what.
  Future<List<PlannedVisit>> pendingUploads(String? inspector) =>
      (database.select(database.plannedVisits)
            ..where((t) =>
                _ownedBy(t.inspectorUsername, inspector) &
                t.isUploaded.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.plannedFor)]))
          .get();

  /// Sends the planning the office has not got, and returns how many rows
  /// went up.
  ///
  /// Everything or nothing: the endpoint takes the batch in one request,
  /// so a handset on a thin signal makes one call rather than one per
  /// plan. A plan that the server refuses is left marked as pending and
  /// tried again on the next sync rather than being dropped.
  Future<int> uploadPending({
    required String token,
    required String? inspector,
  }) async {
    if (baseUrl.isEmpty) return 0;
    final pending = await pendingUploads(inspector);
    if (pending.isEmpty) return 0;

    final response = await _client.post(
      Uri.parse('$baseUrl/api/planning/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'plans': [
          for (final p in pending)
            {
              'uuid': p.uuid,
              'planned_for':
                  '${p.plannedFor.year.toString().padLeft(4, '0')}-'
                      '${p.plannedFor.month.toString().padLeft(2, '0')}-'
                      '${p.plannedFor.day.toString().padLeft(2, '0')}',
              'facility_name': p.facilityName,
              'facility_address': p.facilityAddress,
              'facility_phone': p.facilityPhone,
              'commodities': p.commodity,
              'note': p.note,
              'started_visit_uuid': p.startedVisitUuid,
              'removed': p.removed,
              'created_at': p.createdAt.toUtc().toIso8601String(),
              'updated_at': p.updatedAt.toUtc().toIso8601String(),
            },
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Planning upload refused (${response.statusCode})');
    }

    // Only the rows that were in this batch: an edit made while the
    // request was in flight must not be marked as sent.
    final sent = [for (final p in pending) p.uuid];
    await (database.update(database.plannedVisits)
          ..where((t) => t.uuid.isIn(sent)))
        .write(const PlannedVisitsCompanion(isUploaded: Value(true)));

    // A removal the office now knows about has done its job.
    await (database.delete(database.plannedVisits)
          ..where((t) => t.uuid.isIn(sent) & t.removed.equals(true)))
        .go();

    return pending.length;
  }

  /// Brings down the planning the office holds for this inspector.
  ///
  /// Two things arrive this way. A visit the office scheduled, which has
  /// never been on this handset and is the whole point of the office being
  /// able to schedule at all; and the inspector's own week coming back
  /// after a reinstall, which is why the endpoint existed before anything
  /// called it.
  ///
  /// Returns how many rows changed, so the sync can say something useful
  /// rather than "done".
  Future<int> downloadPlans({
    required String token,
    required String? inspector,
  }) async {
    if (baseUrl.isEmpty) return 0;

    final response = await _client.get(
      Uri.parse('$baseUrl/api/planning/'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Planning download refused (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final plans = (body['plans'] as List?) ?? const [];
    var changed = 0;

    for (final raw in plans) {
      final plan = raw as Map<String, dynamic>;
      final uuid = (plan['uuid'] ?? '').toString();
      if (uuid.isEmpty) continue;

      final serverUpdated =
          DateTime.tryParse((plan['updated_at'] ?? '').toString())?.toLocal();
      final mine = await byUuid(uuid);

      // The handset wins while it has unsent changes of its own. An
      // inspector who moved a visit on the tablet this morning and has not
      // synced yet must not have it dragged back by the copy the office
      // still holds — their edit is going up in the same sync.
      if (mine != null && !mine.isUploaded) continue;

      // Otherwise the newer of the two wins. Equal timestamps mean the
      // same row, so there is nothing to write.
      if (mine != null &&
          serverUpdated != null &&
          !serverUpdated.isAfter(mine.updatedAt)) {
        continue;
      }

      // A plan the office withdrew, or the inspector removed on another
      // handset, goes off this one too.
      if (plan['removed'] == true) {
        if (mine != null) {
          await (database.delete(database.plannedVisits)
                ..where((t) => t.uuid.equals(uuid)))
              .go();
          changed++;
        }
        continue;
      }

      final plannedFor =
          DateTime.tryParse((plan['planned_for'] ?? '').toString());
      if (plannedFor == null) continue;

      await database.into(database.plannedVisits).insertOnConflictUpdate(
            PlannedVisitsCompanion.insert(
              uuid: uuid,
              // Filed under whoever is holding the handset: the server
              // only ever sends this inspector their own.
              inspectorUsername: Value(inspector ?? ''),
              plannedFor: day(plannedFor),
              facilityName: Value((plan['facility_name'] ?? '').toString()),
              facilityAddress: Value(FacilityAddress.tidy(
                  (plan['facility_address'] ?? '').toString())),
              facilityPhone: Value((plan['facility_phone'] ?? '').toString()),
              commodity: Value((plan['commodities'] ?? '').toString()),
              note: Value((plan['note'] ?? '').toString()),
              startedVisitUuid: Value(
                  // Never un-start a visit that was opened here. The
                  // office's copy can lag, and clearing this would offer
                  // the inspector a second inspection for a call they have
                  // already made.
                  mine?.startedVisitUuid.isNotEmpty == true
                      ? mine!.startedVisitUuid
                      : (plan['started_visit_uuid'] ?? '').toString()),
              scheduledByOffice:
                  Value(plan['scheduled_by_office'] == true),
              scheduledBy: Value((plan['scheduled_by'] ?? '').toString()),
              // Matches what the server holds, so it is not sent straight
              // back up as though it were a local edit.
              isUploaded: const Value(true),
              createdAt:
                  DateTime.tryParse((plan['created_at'] ?? '').toString())
                          ?.toLocal() ??
                      DateTime.now(),
              updatedAt: serverUpdated ?? DateTime.now(),
            ),
          );
      changed++;
    }

    return changed;
  }
}
