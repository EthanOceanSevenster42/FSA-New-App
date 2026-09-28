import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';
import '../../../core/session/session_store.dart';
import '../domain/egg_rules.dart';
import '../../../core/documents/direction_pdf.dart';
import '../../../core/documents/fsa_checklist_pdf.dart';
import '../../../core/documents/fsa_documents.dart';
import 'egg_weighing_checklist_pdf.dart';
import '../../visits/domain/facility_type_match.dart';
import '../../visits/domain/inspection_reason_match.dart';

/// What the server holds that this device does not.
class ReferenceUpdates {
  const ReferenceUpdates({
    required this.clients,
    required this.facilities,
    required this.total,
  });

  const ReferenceUpdates.none()
      : clients = 0,
        facilities = 0,
        total = 0;

  /// New or amended client records.
  final int clients;

  /// New or amended premises.
  final int facilities;

  /// Everything changed, including rules an inspector never sees directly.
  final int total;

  bool get hasAny => total > 0;

  /// One line for the prompt.
  ///
  /// Leads with [total] because that is exactly what the download will write,
  /// so the prompt and the "Downloaded N records" confirmation always agree.
  /// Clients and facilities are then named because they are the two an
  /// inspector picks from a list; the rest are rules and lookups they never
  /// see directly, and those are counted but not itemised.
  String get summary {
    final unit = total == 1 ? 'record' : 'records';
    final named = <String>[
      if (clients > 0) '$clients client${clients == 1 ? '' : 's'}',
      if (facilities > 0) '$facilities facilit${facilities == 1 ? 'y' : 'ies'}',
    ];
    if (named.isEmpty) return '$total $unit to download';

    final itemised = clients + facilities;
    // "including" only when the named parts do not account for the whole,
    // so the wording never implies a breakdown that does not add up.
    return itemised == total
        ? '$total $unit: ${named.join(' and ')}'
        : '$total $unit, including ${named.join(' and ')}';
  }
}

/// The server understood the request and refused the record.
///
/// Distinct from a dropped connection: retrying changes nothing, so the sync
/// service must stop and the inspector must be told. The usual cause is a
/// reference id the server does not have — the handset holding lookup rows
/// from a different server.
class RecordRejected implements Exception {
  const RecordRejected(this.statusCode, this.detail);

  final int statusCode;
  final String detail;

  @override
  String toString() => 'Rejected by the server ($statusCode): $detail';
}

/// How many eggs in one inspection carry a given deviation.
class DeviationTally {
  const DeviationTally({
    required this.deviationId,
    required this.description,
    required this.category,
    required this.eggsAffected,
  });

  final int deviationId;
  final String description;
  final String category;
  final int eggsAffected;
}

/// Syncs Poultry Egg reference data and reads it back for the form.
class EggsRepository {
  EggsRepository({
    required this.baseUrl,
    required this.database,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  /// Rules shipped inside the app. Regenerate with the backend's
  /// `export_egg_reference` command whenever the rules change.
  static const bundledRulesAsset = 'assets/reference/eggs_reference.json';

  static const cursorKey = 'eggs.cursor';
  static const lastSyncAtKey = 'eggs.lastSyncAt';

  /// Which server the reference data on this device came from.
  ///
  /// Reference rows are keyed by the server's own ids, and a captured
  /// inspection stores those ids. Point the app at a different server and
  /// those ids mean different rows — or nothing at all — so every upload comes
  /// back "Invalid pk … object does not exist", forever, while the app retries
  /// and says nothing. Recording the origin lets a change of server force a
  /// clean re-download instead.
  static const referenceOriginKey = 'eggs.referenceOrigin';

  /// True when the reference data on this device cannot be trusted to match
  /// this server.
  ///
  /// Unknown provenance counts as foreign. A device that was set up before the
  /// origin was recorded is exactly the case that goes wrong — it holds rows
  /// from whichever server it last spoke to, and there is no way to tell which.
  /// One full download settles it, once.
  Future<bool> get referenceIsForeign async {
    final origin = await database.readSyncState(referenceOriginKey);
    if (origin == null || origin.isEmpty) {
      // Nothing stored at all is only fine on a device with no data yet.
      return await hasReferenceData;
    }
    return origin != baseUrl;
  }

  /// Throws away reference rows and the sync cursor, so the next sync fetches
  /// the new server's ids from scratch.
  ///
  /// Captured inspections are left alone: they are the inspector's work, and
  /// discarding them to fix a lookup table would be the wrong trade. They are
  /// re-pointed by the inspector picking the client and facility again.
  Future<void> clearReferenceData() async {
    await database.transaction(() async {
      await _emptyReferenceTables();
      await database.writeSyncState(cursorKey, '');
    });
  }

  /// Every lookup table the reference feed owns. Captured inspections and
  /// their samples are not on this list and are never touched.
  List<TableInfo<Table, dynamic>> get _referenceTables => [
        database.eggClients,
        database.eggFacilities,
        database.eggSuppliers,
        database.eggFacilityTypes,
        database.eggInspectionReasons,
        database.eggTraySizes,
        database.eggSizes,
        database.eggGrades,
        database.eggDeviationCategories,
        database.eggDeviations,
        database.eggDeviationTolerances,
        database.eggRequirements,
        database.eggRestrictedParticulars,
        database.eggDirectionRemarks,
      ];

  /// Must run inside a transaction, so the tables are never seen empty.
  Future<void> _emptyReferenceTables() async {
    for (final t in _referenceTables) {
      await database.delete(t).go();
    }
  }

  final String baseUrl;
  final LocalDatabase database;
  final Duration timeout;
  final http.Client _client;

  /// The pass currently running, if any.
  ///
  /// Reference syncs must not overlap. Sign-in asks for a full one while the
  /// background pass asks for an incremental one, and interleaved they
  /// destroy the tables: the full pass clears the rows, the incremental
  /// pass writes its handful and advances the cursor, and the clear lands
  /// last — leaving sizes and grades empty with a cursor that says there is
  /// nothing left to fetch. The second caller waits for the first instead.
  Future<int>? _referenceSyncInFlight;

  Future<int> syncReference({bool full = false}) async {
    final running = _referenceSyncInFlight;
    if (running != null) return running;
    final pass = _syncReference(full: full);
    _referenceSyncInFlight = pass;
    try {
      return await pass;
    } finally {
      _referenceSyncInFlight = null;
    }
  }

  Future<int> _syncReference({bool full = false}) async {
    // Ids from another server are worse than no ids: they upload as valid and
    // are rejected as unknown.
    if (await referenceIsForeign) {
      // Ask for everything, but do NOT empty the tables first. The write
      // below replaces them inside its own transaction once the new rows are
      // in hand; wiping here and then failing to reach the server left the
      // handset with no rules at all — "Not yet" in every picker and no way
      // to open an inspection — which is worse than rules from the wrong
      // server, and is what an inspector out of signal actually hit.
      full = true;
    }
    // Self-heal: rules missing means an interrupted pass emptied them, and
    // an incremental fetch against an advanced cursor would never bring them
    // back. Ask for everything instead.
    if (!full && !await hasReferenceData) full = true;
    final cursor = full ? null : await database.readSyncState(cursorKey);
    // No cursor means the server is sending everything it has — so what it
    // sends is the whole truth, and the tables are rebuilt from it rather
    // than merged into. Merging is what left the bundled rules' rows standing
    // beside the server's ("Jumbo" twice) when the two landed together on a
    // first launch, and what kept rows the server had since deleted.
    final everything = cursor == null || cursor.isEmpty;
    final uri = Uri.parse('$baseUrl/api/eggs/reference/').replace(
      queryParameters: {
        if (!everything) 'since': cursor,
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Egg reference sync failed with status ${response.statusCode}.',
        uri,
      );
    }

    final written = await _writeReference(
      jsonDecode(response.body) as Map<String, dynamic>,
      replace: everything,
      recordOrigin: baseUrl,
    );
    return written;
  }

  /// Loads the rules shipped inside the app, if the device has none.
  ///
  /// The grading rules, deviations, sizes and requirements are what the
  /// capture form cannot work without. Fetching them on first run left a
  /// brand-new handset useless until it found signal — the situation an
  /// inspector is least likely to be in. They are small (tens of kilobytes)
  /// and change rarely, so they travel in the APK.
  ///
  /// Returns the number of rows written; zero when the device already has
  /// rules, which is the normal case after the first launch.
  ///
  /// Clients and facilities are deliberately not bundled: thousands of rows
  /// that change weekly would be stale before the build shipped. Those arrive
  /// on the sync path.
  /// Writes a reference payload read from disk rather than the asset bundle.
  ///
  /// The bundle is the only thing that makes a brand-new handset usable, so
  /// the tests read the real exported file through the same writer the app
  /// uses — a test cannot then pass against a path the app does not take.
  @visibleForTesting
  Future<int> writeReferenceForTest(Map<String, dynamic> body) =>
      _writeReference(body, advanceCursor: false);

  Future<int> seedRulesFromBundle() async {
    if (await hasReferenceData) return 0;

    final raw = await rootBundle.loadString(bundledRulesAsset);
    return _writeReference(
      jsonDecode(raw) as Map<String, dynamic>,
      // Checked again inside the write: a first sync racing this seed may
      // have filled the tables in the meantime, and the bundle's ids must
      // never land on top of the server's.
      onlyIfEmpty: true,
      // Deliberately does NOT advance the sync cursor.
      //
      // One cursor governs every collection, so adopting the bundle's stamp
      // would make the first delta ask only for rows changed after the build —
      // silently skipping every client and facility created before it, which
      // would then never arrive on the handset at all. Those are not in the
      // bundle, so they must all still be fetched.
      //
      // The cost is re-downloading the rules once, on the first sync: tens of
      // kilobytes, written idempotently over what is already there.
      advanceCursor: false,
    );
  }

  /// Writes a reference payload, from the network or from the bundle.
  ///
  /// Both sources use the same shape, so the row handling lives in one place
  /// and cannot drift between them.
  Future<int> _writeReference(
    Map<String, dynamic> body, {
    bool advanceCursor = true,
    bool replace = false,
    bool onlyIfEmpty = false,
    String? recordOrigin,
  }) async {
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    var written = 0;
    var skipped = false;

    List<Map<String, dynamic>> rows(String key) =>
        ((data[key] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>();

    double? asDouble(Object? v) =>
        v == null ? null : double.tryParse(v.toString());

    await database.transaction(() async {
      if (onlyIfEmpty && await hasReferenceData) {
        skipped = true;
        return;
      }
      if (replace) await _emptyReferenceTables();
      for (final j in rows('clients')) {
        await database.into(database.eggClients).insertOnConflictUpdate(
              EggClientsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                tradingName: Value(j['trading_name'] as String? ?? ''),
                physicalAddress: Value(j['physical_address'] as String? ?? ''),
                contactPerson: Value(j['contact_person'] as String? ?? ''),
                telephone: Value(j['telephone'] as String? ?? ''),
                email: Value(j['email'] as String? ?? ''),
                isRegistered: Value(j['is_registered'] as bool? ?? true),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('direction_remarks')) {
        await database
            .into(database.eggDirectionRemarks)
            .insertOnConflictUpdate(
              EggDirectionRemarksCompanion.insert(
                id: Value(j['id'] as int),
                directionType: j['direction_type'] as String,
                remarkText: j['text'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('suppliers')) {
        await database.into(database.eggSuppliers).insertOnConflictUpdate(
              EggSuppliersCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                physicalAddress: Value(j['physical_address'] as String? ?? ''),
                contactPerson: Value(j['contact_person'] as String? ?? ''),
                telephone: Value(j['telephone'] as String? ?? ''),
                email: Value(j['email'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('facilities')) {
        await database.into(database.eggFacilities).insertOnConflictUpdate(
              EggFacilitiesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                facilityTypeId: Value(j['facility_type'] as int?),
                physicalAddress: Value(j['physical_address'] as String? ?? ''),
                telephone: Value(j['telephone'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('sizes')) {
        await database.into(database.eggSizes).insertOnConflictUpdate(
              EggSizesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                minMassG: asDouble(j['min_mass_g']) ?? 0,
                maxMassG: Value(asDouble(j['max_mass_g'])),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                // Absent on a payload from an older server: treat it as a real
                // band, which is what every size was before declarations.
                isMassBand: Value(j['is_mass_band'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('grades')) {
        await database.into(database.eggGrades).insertOnConflictUpdate(
              EggGradesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                rank: j['rank'] as int,
                description: Value(j['description'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('deviation_categories')) {
        await database
            .into(database.eggDeviationCategories)
            .insertOnConflictUpdate(
              EggDeviationCategoriesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('deviations')) {
        await database.into(database.eggDeviations).insertOnConflictUpdate(
              EggDeviationsCompanion.insert(
                id: Value(j['id'] as int),
                categoryId: j['category'] as int,
                description: j['description'] as String,
                downgradesToGradeId: Value(j['downgrades_to'] as int?),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('deviation_tolerances')) {
        await database
            .into(database.eggDeviationTolerances)
            .insertOnConflictUpdate(
              EggDeviationTolerancesCompanion.insert(
                id: Value(j['id'] as int),
                deviationId: j['deviation'] as int,
                sizeId: j['size'] as int,
                gradeId: j['grade'] as int,
                minimum: Value(j['minimum'] as int? ?? 0),
                maximum: Value(j['maximum'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('requirements')) {
        await database.into(database.eggRequirements).insertOnConflictUpdate(
              EggRequirementsCompanion.insert(
                id: Value(j['id'] as int),
                kind: j['kind'] as String,
                description: j['description'] as String,
                // The wording the original shows on screen, where it differs
                // from the wording it files against the record.
                screenLabel: Value(j['screen_label'] as String? ?? ''),
                regulation: Value(j['regulation'] as String? ?? ''),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('restricted_particulars')) {
        await database
            .into(database.eggRestrictedParticulars)
            .insertOnConflictUpdate(
              EggRestrictedParticularsCompanion.insert(
                id: Value(j['id'] as int),
                keyword: j['keyword'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                note: Value(j['note'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('tray_sizes')) {
        await database.into(database.eggTraySizes).insertOnConflictUpdate(
              EggTraySizesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                eggCount: j['egg_count'] as int,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('facility_types')) {
        await database.into(database.eggFacilityTypes).insertOnConflictUpdate(
              EggFacilityTypesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      for (final j in rows('inspection_reasons')) {
        await database
            .into(database.eggInspectionReasons)
            .insertOnConflictUpdate(
              EggInspectionReasonsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
        written++;
      }
      if (recordOrigin != null) {
        await database.writeSyncState(referenceOriginKey, recordOrigin);
      }
    });

    if (skipped) return 0;
    if (advanceCursor) {
      final nextCursor = body['cursor'] as String?;
      if (nextCursor != null) {
        await database.writeSyncState(cursorKey, nextCursor);
      }
      await database.writeSyncState(
        lastSyncAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    return written;
  }

  /// Asks the server what reference data has changed since the last sync,
  /// without downloading any of it.
  ///
  /// Counts only, so the app can offer the download instead of forcing one on
  /// an inspector who may be on an expensive connection.
  Future<ReferenceUpdates> pendingReferenceUpdates() async {
    final cursor = await database.readSyncState(cursorKey);
    final uri = Uri.parse('$baseUrl/api/eggs/reference/status/').replace(
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'since': cursor,
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Could not check for updates (${response.statusCode}).',
        uri,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final counts = (body['counts'] as Map<String, dynamic>?) ?? const {};
    return ReferenceUpdates(
      clients: (counts['clients'] as num?)?.toInt() ?? 0,
      facilities: (counts['facilities'] as num?)?.toInt() ?? 0,
      total: (body['total'] as num?)?.toInt() ?? 0,
    );
  }

  // --- Reads --------------------------------------------------------------

  /// Whether this device holds any egg reference data at all.
  ///
  /// Deliberately a cheap check on one table rather than a survey of them
  /// all. It answers two questions that both want the same thing: whether
  /// the bundle may be written (it must never land on top of the server's
  /// rows, so anything here means no), and whether data of unknown origin
  /// exists to be re-fetched.
  ///
  /// It is not a check that the rules are complete. A device left with some
  /// tables and not others is a bug in whatever emptied them, not something
  /// to paper over by seeding the bundle over the top.
  Future<bool> get hasReferenceData async =>
      (await database.select(database.eggSizes).get()).isNotEmpty;

  Future<List<EggSizeBand>> sizeBands() async {
    final rows = await (database.select(database.eggSizes)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows)
        EggSizeBand(
          id: r.id,
          name: r.name,
          minMassG: r.minMassG,
          maxMassG: r.maxMassG,
          sortOrder: r.sortOrder,
          isMassBand: r.isMassBand,
        ),
    ];
  }

  Future<List<EggGradeRef>> gradeRefs() async {
    final rows = await (database.select(database.eggGrades)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.rank)]))
        .get();
    return [
      for (final r in rows) EggGradeRef(id: r.id, name: r.name, rank: r.rank),
    ];
  }

  Future<List<DeviationRef>> deviationRefs() async {
    final rows = await (database.select(database.eggDeviations)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [
      for (final r in rows)
        DeviationRef(
          id: r.id,
          categoryId: r.categoryId,
          description: r.description,
          downgradesToGradeId: r.downgradesToGradeId,
        ),
    ];
  }

  Future<List<EggDeviationCategory>> deviationCategories() =>
      (database.select(database.eggDeviationCategories)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<List<EggDeviation>> deviationsFor(int categoryId) => (database
          .select(database.eggDeviations)
        ..where(
            (t) => t.isActive.equals(true) & t.categoryId.equals(categoryId)))
      .get();

  Future<List<EggRequirement>> requirements(String kind) =>
      (database.select(database.eggRequirements)
            ..where((t) => t.isActive.equals(true) & t.kind.equals(kind))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.description),
            ]))
          .get();

  Future<List<EggSupplier>> suppliers() =>
      (database.select(database.eggSuppliers)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  /// Registers an egg producer or packer met in the field. As [addClient]:
  /// the server allocates the id, never this device.
  Future<EggSupplier> addSupplier({
    required String name,
    String physicalAddress = '',
    String contactPerson = '',
    String telephone = '',
    String email = '',
  }) async {
    final body = {
      'name': name.trim(),
      'physical_address': physicalAddress.trim(),
      'contact_person': contactPerson.trim(),
      'telephone': telephone.trim(),
      'email': email.trim(),
    };

    int id = await _nextLocalId(database.eggSuppliers.id);
    String updatedAt = '';
    final token = await storedToken();
    if (token != null) {
      try {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/api/eggs/suppliers/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final j = jsonDecode(response.body) as Map<String, dynamic>;
          id = j['id'] as int;
          updatedAt = j['updated_at'] as String? ?? '';
        }
      } on Object {
        // Offline or refused: keep the local row so capture can continue.
      }
    }

    await database.into(database.eggSuppliers).insertOnConflictUpdate(
          EggSuppliersCompanion.insert(
            id: Value(id),
            name: body['name']!,
            physicalAddress: Value(body['physical_address']!),
            contactPerson: Value(body['contact_person']!),
            telephone: Value(body['telephone']!),
            email: Value(body['email']!),
            updatedAt: Value(updatedAt),
          ),
        );
    return (await (database.select(database.eggSuppliers)
          ..where((t) => t.id.equals(id)))
        .getSingle());
  }

  /// Every requirement, grouped into the three labelling checklists.
  ///
  /// A direction's labelling part is required when any checklist has a failing
  /// requirement on it.
  Future<Map<LabelChecklist, Set<int>>> requirementChecklists() async {
    final rows = await (database.select(database.eggRequirements)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return {
      LabelChecklist.innerLabel: {
        for (final r in rows)
          if (r.kind == 'label_pack') r.id,
      },
      LabelChecklist.outerLabel: {
        for (final r in rows)
          if (r.kind == 'label_outer') r.id,
      },
      LabelChecklist.container: {
        for (final r in rows)
          if (r.kind == 'packing') r.id,
      },
    };
  }

  /// The bands a deviation count must stay inside, for the whole rule set.
  ///
  /// Read once when a form opens rather than queried per deviation: there are
  /// only a few hundred, and an inspector saving an inspection should not wait
  /// on a query per egg.
  Future<List<DeviationTolerance>> deviationTolerances() async {
    final rows = await (database.select(database.eggDeviationTolerances)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [
      for (final r in rows)
        DeviationTolerance(
          deviationId: r.deviationId,
          sizeId: r.sizeId,
          gradeId: r.gradeId,
          minimum: r.minimum,
          maximum: r.maximum,
        ),
    ];
  }

  Future<List<EggRestrictedParticular>> restrictedParticulars() =>
      (database.select(database.eggRestrictedParticulars)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.keyword),
            ]))
          .get();

  Future<List<EggTraySize>> traySizes() =>
      (database.select(database.eggTraySizes)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.eggCount),
            ]))
          .get();

  Future<List<EggFacilityType>> facilityTypes() =>
      (database.select(database.eggFacilityTypes)
            ..where((t) => t.isActive.equals(true))
            // Seed order, as the original's picker presents them.
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.name),
            ]))
          .get();

  Future<List<EggInspectionReason>> reasons() =>
      (database.select(database.eggInspectionReasons)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.name),
            ]))
          .get();

  Future<List<EggGrade>> grades() => (database.select(database.eggGrades)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.rank)]))
      .get();

  Future<List<EggFacility>> facilities() =>
      (database.select(database.eggFacilities)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<EggClient>> clients() => (database.select(database.eggClients)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .get();

  Future<List<EggDirectionRemark>> directionRemarks(String directionType) =>
      (database.select(database.eggDirectionRemarks)
            ..where((t) =>
                t.isActive.equals(true) & t.directionType.equals(directionType))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.remarkText),
            ]))
          .get();

  // --- Directions ---------------------------------------------------------

  /// Where the signed-in username lives, as defined by [SessionStore].
  ///
  /// Read straight from `sync_state` rather than taking a SessionStore
  /// dependency: both already live in that table, and threading a second
  /// collaborator through every construction site to read one string earns
  /// nothing. The key itself is not redeclared here.
  static const sessionUserKey = SessionStore.userKey;

  /// Whoever is signed in on this handset, or null if nobody is.
  ///
  /// Everything a user can see or send is scoped to this. A null owner means no
  /// session, which means nothing should be listed — capturing an inspection
  /// requires signing in, so there is no legitimate ownerless work to show.
  Future<String?> currentInspector() async {
    final name = await database.readSyncState(sessionUserKey);
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Restricts a query to the signed-in inspector's own rows.
  ///
  /// `null` owner is deliberately excluded rather than treated as a wildcard.
  /// The alternative — showing unowned rows to everyone — would quietly
  /// reintroduce the very leak this scoping exists to close, on exactly the
  /// rows whose owner is unknown.
  Expression<bool> _ownedBy(GeneratedColumn<String> column, String? owner) =>
      owner == null ? const Constant(false) : column.equals(owner);

  Future<void> saveDirection(EggDirectionsCompanion direction) async {
    final owner = await currentInspector();
    await database.into(database.eggDirections).insertOnConflictUpdate(
          direction.inspectorUsername.present
              ? direction
              : direction.copyWith(inspectorUsername: Value(owner)),
        );
  }

  Future<List<EggDirection>> savedDirections() async {
    final owner = await currentInspector();
    return (database.select(database.eggDirections)
          ..where((t) => _ownedBy(t.inspectorUsername, owner))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.issuedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  Future<int> pendingDirectionCount() async {
    final owner = await currentInspector();
    final rows = await (database.select(database.eggDirections)
          ..where(
            (t) =>
                t.isUploaded.equals(false) &
                _ownedBy(t.inspectorUsername, owner),
          ))
        .get();
    return rows.length;
  }

  /// Uploads one direction. Idempotent on `clientUuid`, like inspections.
  Future<void> uploadDirection(
    EggDirection direction, {
    required String token,
  }) async {
    // As with inspections: half a notice is not a record. Uploaded, it comes
    // back on every device as an unfinished direction nobody can discard.
    if (direction.status != 'completed') {
      throw StateError(
        'Refusing to upload rejection ${direction.clientUuid}: '
        'status is "${direction.status}", not "completed".',
      );
    }
    final uri = Uri.parse('$baseUrl/api/eggs/directions/');
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'client_uuid': direction.clientUuid,
            'inspection_uuid': direction.inspectionUuid,
            'labelling_part': direction.labellingPart,
            'quality_part': direction.qualityPart,
            'label_correct_by':
                direction.labelCorrectBy?.toIso8601String().split('T').first,
            'quality_correct_by':
                direction.qualityCorrectBy?.toIso8601String().split('T').first,
            'status': direction.status,
            'issued_at': direction.issuedAt.toUtc().toIso8601String(),
            'direction_number': direction.directionNumber,
            'quantity_removed': direction.quantityRemoved,
            'remarks': _ids(direction.remarkIds),
            'additional_remarks': direction.additionalRemarks,
            'client_name': direction.clientName,
            'producer_supplier': direction.producerSupplier,
            'latitude': _coordinate(direction.latitude),
            'longitude': _coordinate(direction.longitude),
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      // 4xx means the record itself is unacceptable; no amount of retrying
      // will change that.
      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 401 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        throw RecordRejected(response.statusCode, response.body);
      }
      throw http.ClientException(
        'Rejection upload failed (${response.statusCode}): ${response.body}',
        uri,
      );
    }

    await (database.update(database.eggDirections)
          ..where((t) => t.clientUuid.equals(direction.clientUuid)))
        .write(const EggDirectionsCompanion(isUploaded: Value(true)));
  }

  // --- Persistence --------------------------------------------------------

  Future<void> saveInspection(
    EggInspectionsCompanion inspection,
    List<EggSamplesCompanion> samples,
  ) async {
    final owner = await currentInspector();
    await database.transaction(() async {
      await database.into(database.eggInspections).insertOnConflictUpdate(
            inspection.inspectorUsername.present
                ? inspection
                : inspection.copyWith(inspectorUsername: Value(owner)),
          );
      final uuid = inspection.clientUuid.value;
      await (database.delete(database.eggSamples)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      for (final s in samples) {
        await database.into(database.eggSamples).insert(s);
      }
    });
  }

  Future<void> addPhoto(EggPhotosCompanion photo) =>
      database.into(database.eggPhotos).insert(photo);

  /// One signature per role per inspection — re-signing replaces the row,
  /// matching the server's unique_together on (inspection, role).
  Future<void> saveSignature(EggSignaturesCompanion signature) async {
    await (database.delete(database.eggSignatures)
          ..where((t) =>
              t.inspectionUuid.equals(signature.inspectionUuid.value) &
              t.role.equals(signature.role.value)))
        .go();
    await database.into(database.eggSignatures).insert(signature);
  }

  Future<List<EggSignature>> signaturesFor(String uuid) =>
      (database.select(database.eggSignatures)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .get();

  Future<void> removeSignature(String uuid, String role) =>
      (database.delete(database.eggSignatures)
            ..where(
              (t) => t.inspectionUuid.equals(uuid) & t.role.equals(role),
            ))
          .go();

  /// As [addPhoto], returning the row id so the caller can remove exactly this
  /// photograph later without matching on a file path.
  Future<int> addPhotoReturningId(EggPhotosCompanion photo) =>
      database.into(database.eggPhotos).insert(photo);

  Future<List<EggInspection>> savedInspections() async {
    final owner = await currentInspector();
    return (database.select(database.eggInspections)
          ..where((t) => _ownedBy(t.inspectorUsername, owner))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.inspectedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  Future<int> pendingUploadCount() async {
    final owner = await currentInspector();
    final rows = await (database.select(database.eggInspections)
          ..where(
            (t) =>
                t.isUploaded.equals(false) &
                _ownedBy(t.inspectorUsername, owner),
          ))
        .get();
    return rows.length;
  }

  /// The Egg Labeling Checklist (SOP-APS-EGGS-003) for [uuid] — the
  /// marking, container and packing requirements the inspector worked
  /// through, with the deviations marked.
  ///
  /// Null until the labelling checklist has been worked: the sheet records
  /// that work, and an untouched checklist is not a record of it. The
  /// original opens the sizing block only once labelling is done, so a
  /// record with samples on it has necessarily been through this.
  /// The rejection served off an egg inspection — SOP-APS-001.
  ///
  /// What the app calls a rejection is what the Agency's paperwork calls a
  /// direction, and it is the one document the person it is served on is
  /// entitled to read. The handset raised it, numbered it and sent it up as
  /// data, and rendered nothing — so neither the client nor the office ever
  /// saw the notice itself.
  ///
  /// [uuid] is the inspection's, as every other builder here takes; a
  /// rejection raised on its own in Rejection Management is found by its own
  /// uuid instead, so both open the same sheet.
  Future<File?> buildDirection(String uuid, {Directory? into}) async {
    final direction = await directionForInspection(uuid) ??
        await directionByUuid(uuid);
    if (direction == null) return null;
    final i = direction.inspectionUuid == null
        ? null
        : await inspectionByUuid(direction.inspectionUuid!);

    // The deviations the notice cites: the labelling rows that failed, and
    // the shell and content deviations found on the weighed sample.
    final deviations = <DirectionDeviation>[];
    final product = i == null
        ? 'Eggs'
        : [
            if (i.producerSupplier.isNotEmpty) i.producerSupplier,
            if (i.batchNumber.isNotEmpty) 'batch ${i.batchNumber}',
          ].join(' — ');
    if (i != null) {
      final failed = i.failedRequirementIds
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toSet();
      if (failed.isNotEmpty) {
        final requirements = await (database.select(database.eggRequirements)
              ..where((t) => t.id.isIn(failed.toList()))
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .get();
        for (final r in requirements) {
          deviations.add(DirectionDeviation(
            product: product.isEmpty ? 'Eggs' : product,
            nature: r.description,
            regulation: r.regulation,
          ));
        }
      }
      final samples = await samplesFor(direction.inspectionUuid!);
      final found = <int>{};
      for (final sample in samples) {
        found.addAll(sample.deviationIds
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>());
      }
      if (found.isNotEmpty) {
        final rows = await (database.select(database.eggDeviations)
              ..where((t) => t.id.isIn(found.toList())))
            .get();
        for (final d in rows) {
          // How many of the sample carried it: the tolerance is counted,
          // so a notice that omits the count cannot be argued with.
          final affected = samples
              .where((s) => s.deviationIds
                  .split(',')
                  .map((v) => int.tryParse(v.trim()))
                  .whereType<int>()
                  .contains(d.id))
              .length;
          deviations.add(DirectionDeviation(
            product: product.isEmpty ? 'Eggs' : product,
            nature: '${d.description} — $affected of ${samples.length} eggs '
                'in the sample.',
            regulation: '',
          ));
        }
      }
    }

    // The remarks the inspector picked off the Agency's own list, plus
    // anything they wrote.
    final remarkIds = direction.remarkIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    final remarks = remarkIds.isEmpty
        ? <EggDirectionRemark>[]
        : await (database.select(database.eggDirectionRemarks)
              ..where((t) => t.id.isIn(remarkIds))
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
            .get();

    final ctx = i == null ? null : await _eggDocumentContext(i.clientUuid, i);
    final facility = ctx?.facilityName ?? direction.clientName;
    final correctBy = direction.qualityCorrectBy ?? direction.labelCorrectBy;

    return DirectionPdf.write(
      out: _eggDocumentFile(facility, 'Egg-Rejection', direction.clientUuid,
          into),
      control: FsaDocuments.eggDirection,
      // Which part of the notice was served. One sheet may carry both.
      natureOfInspection: [
        if (direction.labellingPart) 'Egg Labelling',
        if (direction.qualityPart) 'Egg Quality',
      ].join(' & ').isEmpty
          ? 'Eggs'
          : [
              if (direction.labellingPart) 'Egg Labelling',
              if (direction.qualityPart) 'Egg Quality',
            ].join(' & '),
      facilityName: facility,
      ownerOrRepresentative: ctx?.authorisedPersonName ?? direction.clientName,
      physicalAddress: ctx?.facilityAddress ?? '',
      emailAddress: i?.clientEmail ?? '',
      dateOfVisit: i?.inspectedAt ?? direction.issuedAt,
      inspectionReason: '',
      latestReference: direction.directionNumber,
      originalReference: '',
      subjectFields: [
        (
          label: 'Producer/Supplier',
          value: direction.producerSupplier.isNotEmpty
              ? direction.producerSupplier
              : (i?.producerSupplier ?? '')
        ),
        (label: 'Batch Number', value: i?.batchNumber ?? ''),
        (
          label: 'Quantity Removed',
          value: direction.quantityRemoved == null
              ? ''
              : '${direction.quantityRemoved}'
        ),
      ],
      deviations: deviations,
      correctByDate: correctBy == null ? '' : _ymd(correctBy),
      actionsAndRemark: [
        for (final r in remarks) r.remarkText,
        if (direction.additionalRemarks.trim().isNotEmpty)
          direction.additionalRemarks.trim(),
      ].join('\n'),
      inspectorName:
          ctx?.inspectorName ?? (direction.inspectorUsername ?? ''),
      authorisedPersonName: ctx?.authorisedPersonName ?? direction.clientName,
      inspectorSignaturePath: ctx?.inspectorSignaturePath ?? '',
      authorisedPersonSignaturePath:
          ctx?.authorisedPersonSignaturePath ?? '',
      pleaseNote: 'Failure to rectify by the date above may result in '
          'further action under the Act.',
    );
  }

  Future<File?> buildLabellingChecklist(String uuid, {Directory? into}) async {
    final i = await inspectionByUuid(uuid);
    if (i == null) return null;
    final samples = await samplesFor(uuid);
    final failed = i.failedRequirementIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    // Nothing worked through at all: no ticks, no deviations, no samples.
    if (samples.isEmpty && failed.isEmpty && !i.outerLabellingAvailable) {
      return null;
    }

    final requirements = await (database.select(database.eggRequirements)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    if (requirements.isEmpty) return null;

    const titles = {
      'label_pack': 'MARKING OF CONTAINERS',
      'label_outer': 'MARKING OF OUTER CONTAINERS',
      'packing': 'PACKING REQUIREMENTS',
    };
    final sections = <FsaChecklistSection>[];
    for (final kind in titles.keys) {
      // The outer container block only applies when there was one.
      if (kind == 'label_outer' && !i.outerLabellingAvailable) continue;
      final rows = requirements.where((r) => r.kind == kind).toList();
      if (rows.isEmpty) continue;
      sections.add(FsaChecklistSection(
        title: titles[kind]!,
        rows: [
          for (final r in rows)
            FsaChecklistRow(
              requirement: r.description,
              regulation: r.regulation,
              deviation:
                  failed.contains(r.id) ? FsaDeviation.yes : FsaDeviation.no,
            ),
        ],
      ));
    }
    if (sections.isEmpty) return null;

    final ctx = await _eggDocumentContext(uuid, i);
    return FsaChecklistPdf.write(
      out: _eggDocumentFile(
          ctx.facilityName, 'Egg-Labeling-Checklist', uuid, into),
      control: FsaDocuments.eggLabelling,
      facilityName: ctx.facilityName,
      leftFields: [
        (label: 'Date of Inspection:', value: _ymd(i.inspectedAt)),
        (label: 'Facility Name:', value: ctx.facilityName),
        (label: 'Site Representative:', value: ctx.representative),
        (label: 'Tray Packaging Size', value: ctx.traySize),
      ],
      rightFields: [
        (label: 'Producer/Supplier', value: i.producerSupplier),
        (label: 'Batch Number', value: i.batchNumber),
        (
          label: 'Best Before Date',
          value: i.bestBefore == null ? '' : _ymd(i.bestBefore!)
        ),
        (label: 'Type of Facility', value: ctx.facilityType),
      ],
      sections: sections,
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      comments: i.nonConformanceComments,
      remarks: i.generalComments,
      photoPaths: [
        if (ctx.labelPhotoPath.isNotEmpty) ctx.labelPhotoPath,
      ],
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      documentTitle: 'Egg Labeling Checklist',
    );
  }

  /// The Egg Weighing Checklist (SOP-APS-EGGS-003) for [uuid], filled in
  /// from the samples weighed on this inspection.
  ///
  /// Null when no egg was weighed: the checklist is the record of the
  /// weighing, and a sheet of empty rows is not one. At a retailer, where
  /// the original allows an inspection with no weighing at all, that is the
  /// ordinary case rather than an error.
  Future<File?> buildWeighingChecklist(String uuid, {Directory? into}) async {
    final inspection = await inspectionByUuid(uuid);
    if (inspection == null) return null;
    final samples = await samplesFor(uuid);
    if (samples.isEmpty) return null;

    final deviations = await deviationRefs();
    String deviationName(int id) => deviations
        .where((d) => d.id == id)
        .map((d) => d.description)
        .firstWhere((_) => true, orElse: () => '');

    final sizes = await sizeBands();
    final grades = await gradeRefs();
    String sizeName(int? id) => id == null
        ? ''
        : sizes
            .where((s) => s.id == id)
            .map((s) => s.name)
            .firstWhere((_) => true, orElse: () => '');
    String gradeName(int? id) => id == null
        ? ''
        : grades
            .where((g) => g.id == id)
            .map((g) => g.name)
            .firstWhere((_) => true, orElse: () => '');

    final tray = inspection.traySizeId == null
        ? null
        : await (database.select(database.eggTraySizes)
              ..where((t) => t.id.equals(inspection.traySizeId!)))
            .getSingleOrNull();
    final facilityType = inspection.facilityTypeId == null
        ? null
        : await (database.select(database.eggFacilityTypes)
              ..where((t) => t.id.equals(inspection.facilityTypeId!)))
            .getSingleOrNull();

    final photos = await photosFor(uuid);
    String pathOfKind(String kind) => photos
        .where((p) => p.kind == kind && p.filePath.isNotEmpty)
        .map((p) => p.filePath)
        .firstWhere((_) => true, orElse: () => '');

    final signatures = await signaturesFor(uuid);
    String signaturePath(String role) => signatures
        .where((s) => s.role == role && !s.declined && s.filePath.isNotEmpty)
        .map((s) => s.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final manager = signatures.where((s) => s.role == 'manager').toList();

    final username = inspection.inspectorUsername ?? '';
    final user = await database.findUser(username);
    final fullName =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();

    final facility = inspection.facilityName.isNotEmpty
        ? inspection.facilityName
        : inspection.clientName;
    final dir = into ?? Directory.systemTemp;
    final short = uuid.length < 8 ? uuid : uuid.substring(0, 8);
    final slug = facility
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return EggWeighingChecklistPdf.write(
      out: File('${dir.path}/FSA-$slug-Egg-Weighing-Checklist-$short.pdf'),
      facilityName: facility,
      facilityAddress: inspection.facilityAddress.isNotEmpty
          ? inspection.facilityAddress
          : inspection.clientAddress,
      dateOfInspection: _dmy(inspection.inspectedAt),
      representative: inspection.representativeName.isNotEmpty
          ? inspection.representativeName
          : inspection.clientContactPerson,
      facilityType: facilityType?.name ?? '',
      producerSupplier: inspection.producerSupplier,
      batchNumber: inspection.batchNumber,
      bestBefore:
          inspection.bestBefore == null ? '' : _dmy(inspection.bestBefore!),
      declaredSize: sizeName(inspection.declaredSizeId),
      declaredGrade: gradeName(inspection.declaredGradeId),
      traySize: tray?.name ?? '',
      rows: [
        for (final sample in samples)
          EggWeighingRow(
            number: sample.eggNumber,
            massG: sample.massG,
            albumenHeightMm: sample.albumenHeightMm,
            haughUnit: sample.haughUnit,
            deviations: [
              for (final id in sample.deviationIds
                  .split(',')
                  .map((s) => int.tryParse(s.trim()))
                  .whereType<int>())
                if (deviationName(id).isNotEmpty) deviationName(id),
            ],
          ),
      ],
      inspectorName: fullName.isEmpty ? username : fullName,
      authorisedPersonName:
          manager.isNotEmpty && manager.first.signedName.isNotEmpty
              ? manager.first.signedName
              : (inspection.managerName.isNotEmpty
                  ? inspection.managerName
                  : inspection.clientContactPerson),
      comments: inspection.generalComments,
      trayLabelPhotoPath: pathOfKind('label'),
      inspectorSignaturePath: signaturePath('inspector'),
      authorisedPersonSignaturePath: signaturePath('manager'),
    );
  }

  /// What both egg documents need about a record: the names on it, the
  /// reference rows resolved, and who signed.
  Future<_EggDocumentContext> _eggDocumentContext(
      String uuid, EggInspection i) async {
    final tray = i.traySizeId == null
        ? null
        : await (database.select(database.eggTraySizes)
              ..where((t) => t.id.equals(i.traySizeId!)))
            .getSingleOrNull();
    final facilityType = i.facilityTypeId == null
        ? null
        : await (database.select(database.eggFacilityTypes)
              ..where((t) => t.id.equals(i.facilityTypeId!)))
            .getSingleOrNull();
    final photos = await photosFor(uuid);
    String pathOfKind(String kind) => photos
        .where((p) => p.kind == kind && p.filePath.isNotEmpty)
        .map((p) => p.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final signatures = await signaturesFor(uuid);
    String signaturePath(String role) => signatures
        .where((s) => s.role == role && !s.declined && s.filePath.isNotEmpty)
        .map((s) => s.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final manager = signatures.where((s) => s.role == 'manager').toList();
    final username = i.inspectorUsername ?? '';
    final user = await database.findUser(username);
    final full =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    return _EggDocumentContext(
      facilityName: i.facilityName.isNotEmpty ? i.facilityName : i.clientName,
      facilityAddress:
          i.facilityAddress.isNotEmpty ? i.facilityAddress : i.clientAddress,
      facilityType: facilityType?.name ?? '',
      traySize: tray?.name ?? '',
      representative: i.representativeName.isNotEmpty
          ? i.representativeName
          : i.clientContactPerson,
      inspectorName: full.isEmpty ? username : full,
      authorisedPersonName: manager.isNotEmpty &&
              manager.first.signedName.isNotEmpty
          ? manager.first.signedName
          : (i.managerName.isNotEmpty ? i.managerName : i.clientContactPerson),
      inspectorSignaturePath: signaturePath('inspector'),
      authorisedPersonSignaturePath: signaturePath('manager'),
      labelPhotoPath: pathOfKind('label'),
    );
  }

  File _eggDocumentFile(
      String facility, String kind, String uuid, Directory? into) {
    final dir = into ?? Directory.systemTemp;
    final short = uuid.length < 8 ? uuid : uuid.substring(0, 8);
    final slug = facility
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return File('${dir.path}/FSA-$slug-$kind-$short.pdf');
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The sheets date themselves the office system's way round.
  static String _ymd(DateTime d) => '${d.year}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';

  Future<List<EggSample>> samplesFor(String uuid) =>
      (database.select(database.eggSamples)
            ..where((t) => t.inspectionUuid.equals(uuid))
            ..orderBy([(t) => OrderingTerm(expression: t.eggNumber)]))
          .get();

  Future<List<EggPhoto>> photosFor(String uuid) =>
      (database.select(database.eggPhotos)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .get();

  /// The most recent inspection still being captured, if there is one.
  ///
  /// A draft exists when the app was interrupted mid-capture — almost always
  /// because Android reclaimed memory while the camera was in front. Offering
  /// it back is the difference between resuming and re-weighing every egg.
  Future<EggInspection?> latestDraft() async {
    final owner = await currentInspector();
    return (database.select(database.eggInspections)
          ..where(
            (t) =>
                t.status.equals('draft') & _ownedBy(t.inspectorUsername, owner),
          )
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Every unfinished inspection on this device, newest first.
  ///
  /// There can be more than one: a draft is written on every step change, so
  /// each abandoned attempt leaves one behind. Discarding a single draft then
  /// looked as if it had not worked — the banner simply came back showing the
  /// next one.
  Future<List<EggInspection>> drafts() async {
    final owner = await currentInspector();
    return (database.select(database.eggInspections)
          ..where(
            (t) =>
                t.status.equals('draft') & _ownedBy(t.inspectorUsername, owner),
          )
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  /// Discards every unfinished inspection, and reports how many went.
  Future<int> deleteAllDrafts() async {
    final all = await drafts();
    for (final draft in all) {
      await deleteInspection(draft.clientUuid);
    }
    return all.length;
  }

  /// Every unfinished direction on this device, newest first.
  Future<List<EggDirection>> directionDrafts() async {
    final owner = await currentInspector();
    return (database.select(database.eggDirections)
          ..where(
            (t) =>
                t.status.equals('draft') & _ownedBy(t.inspectorUsername, owner),
          )
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  /// Discards every unfinished direction, and reports how many went.
  Future<int> deleteAllDirectionDrafts() async {
    final all = await directionDrafts();
    for (final draft in all) {
      await deleteDirection(draft.clientUuid);
    }
    return all.length;
  }

  Future<void> deleteDirection(String uuid) =>
      (database.delete(database.eggDirections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .go();

  /// Removes an inspection and everything hanging off it.
  ///
  /// Used when a draft is discarded. Photographs are deleted from disk by the
  /// caller, which owns the file store.
  Future<void> deleteInspection(String uuid) async {
    await database.transaction(() async {
      await (database.delete(database.eggSamples)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.eggPhotos)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.eggInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .go();
    });
  }

  Future<void> deletePhoto(int id) =>
      (database.delete(database.eggPhotos)..where((t) => t.id.equals(id))).go();

  /// Re-points a captured inspection's lookup ids at the rows this server
  /// actually has, matching by name.
  ///
  /// The rules ship inside the APK with their own ids so a handset can work
  /// before it has signal. Once it syncs, the server's rows arrive under
  /// different ids, and for a while both sets sit in the tables — two
  /// "Jumbo" rows, two "Grade 1" rows. An inspection captured against the
  /// bundled twin uploads as `Invalid pk "11" - object does not exist` and
  /// sits at "Pending upload" for ever, because the ids it stores are never
  /// looked at again.
  ///
  /// Every id the upload sends is checked against the current table; one that
  /// is missing is resolved to its name through the bundled rules and pointed
  /// at the current row with that name. Returns true when anything changed,
  /// so the caller knows a retry is worth making.
  Future<bool> repointLookupIds(String uuid) async {
    final inspection = await inspectionByUuid(uuid);
    if (inspection == null) return false;
    final names = await _BundledNames.load();

    Future<int?> fix<T extends Table, D>(
      int? id,
      TableInfo<T, D> table,
      Expression<int> Function(T) idOf,
      Future<int?> Function(String name) byName,
      String? Function(int id) bundledName,
    ) async {
      if (id == null) return null;
      final present = await (database.select(table)
            ..where((t) => idOf(t).equals(id)))
          .getSingleOrNull();
      if (present != null) return id;
      final name = bundledName(id);
      if (name == null) return id;
      return await byName(name) ?? id;
    }

    Future<int?> sizeByName(String n) async =>
        (await (database.select(database.eggSizes)
                  ..where((t) => t.name.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> gradeByName(String n) async =>
        (await (database.select(database.eggGrades)
                  ..where((t) => t.name.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> reasonByName(String n) async =>
        (await (database.select(database.eggInspectionReasons)
                  ..where((t) => t.name.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> trayByName(String n) async =>
        (await (database.select(database.eggTraySizes)
                  ..where((t) => t.name.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> facilityTypeByName(String n) async =>
        (await (database.select(database.eggFacilityTypes)
                  ..where((t) => t.name.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> requirementByName(String n) async =>
        (await (database.select(database.eggRequirements)
                  ..where((t) => t.description.equals(n)))
                .get())
            .firstOrNull
            ?.id;
    Future<int?> particularByName(String n) async =>
        (await (database.select(database.eggRestrictedParticulars)
                  ..where((t) => t.keyword.equals(n)))
                .getSingleOrNull())
            ?.id;
    Future<int?> deviationByName(String n) async {
      // "<category>|<description>": the same description exists under
      // more than one category, so the category is part of the name.
      final split = n.indexOf('|');
      final category = n.substring(0, split);
      final description = n.substring(split + 1);
      final cat = await (database.select(database.eggDeviationCategories)
            ..where((t) => t.name.equals(category)))
          .getSingleOrNull();
      if (cat == null) return null;
      return (await (database.select(database.eggDeviations)
                ..where((t) =>
                    t.categoryId.equals(cat.id) &
                    t.description.equals(description)))
              .getSingleOrNull())
          ?.id;
    }

    Future<String> fixCsv<T extends Table, D>(
      String csv,
      TableInfo<T, D> table,
      Expression<int> Function(T) idOf,
      Future<int?> Function(String name) byName,
      String? Function(int id) bundledName,
    ) async {
      final out = <int>[];
      for (final id in _ids(csv)) {
        out.add(await fix(id, table, idOf, byName, bundledName) ?? id);
      }
      return out.join(',');
    }

    var changed = false;
    var facilityType = await fix(
        inspection.facilityTypeId,
        database.eggFacilityTypes,
        (t) => t.id,
        facilityTypeByName,
        names.facilityType);
    var reason = await fix(inspection.reasonId, database.eggInspectionReasons,
        (t) => t.id, reasonByName, names.reason);

    // An id no list here knows — captured against another server's rows,
    // which the bundled rules never had — is matched through the visit it
    // belongs to instead, which keeps both answers as names. An inspection
    // captured against a local server went to the live one as
    // `Invalid pk "13"` for ever otherwise (Ethan, 2026-09-24).
    final visit = inspection.visitUuid.isEmpty
        ? null
        : await (database.select(database.storeVisits)
              ..where((t) => t.uuid.equals(inspection.visitUuid)))
            .getSingleOrNull();
    if (visit != null) {
      Future<bool> known<T extends Table, D>(int? id, TableInfo<T, D> table,
              Expression<int> Function(T) idOf) async =>
          id != null &&
          await (database.select(table)..where((t) => idOf(t).equals(id)))
                  .getSingleOrNull() !=
              null;
      if (!await known(facilityType, database.eggFacilityTypes, (t) => t.id) &&
          visit.facilityType.trim().isNotEmpty) {
        final rows = await database.select(database.eggFacilityTypes).get();
        final i = FacilityTypeMatch.indexOf(
            visit.facilityType, [for (final r in rows) r.name]);
        if (i != null) facilityType = rows[i].id;
      }
      if (!await known(reason, database.eggInspectionReasons, (t) => t.id) &&
          visit.inspectionReason.trim().isNotEmpty) {
        final rows = await database.select(database.eggInspectionReasons).get();
        final i = InspectionReasonMatch.indexOf(
            visit.inspectionReason, [for (final r in rows) r.name]);
        if (i != null) reason = rows[i].id;
      }
    }
    final tray = await fix(inspection.traySizeId, database.eggTraySizes,
        (t) => t.id, trayByName, names.traySize);
    final declaredSize = await fix(inspection.declaredSizeId, database.eggSizes,
        (t) => t.id, sizeByName, names.size);
    final declaredGrade = await fix(inspection.declaredGradeId,
        database.eggGrades, (t) => t.id, gradeByName, names.grade);
    final determinedGrade = await fix(inspection.determinedGradeId,
        database.eggGrades, (t) => t.id, gradeByName, names.grade);
    final failed = await fixCsv(
        inspection.failedRequirementIds,
        database.eggRequirements,
        (t) => t.id,
        requirementByName,
        names.requirement);
    final particulars = await fixCsv(
        inspection.restrictedParticularIds,
        database.eggRestrictedParticulars,
        (t) => t.id,
        particularByName,
        names.particular);

    if (facilityType != inspection.facilityTypeId ||
        reason != inspection.reasonId ||
        tray != inspection.traySizeId ||
        declaredSize != inspection.declaredSizeId ||
        declaredGrade != inspection.declaredGradeId ||
        determinedGrade != inspection.determinedGradeId ||
        failed != inspection.failedRequirementIds ||
        particulars != inspection.restrictedParticularIds) {
      changed = true;
      await (database.update(database.eggInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .write(EggInspectionsCompanion(
        facilityTypeId: Value(facilityType),
        reasonId: Value(reason),
        traySizeId: Value(tray),
        declaredSizeId: Value(declaredSize),
        declaredGradeId: Value(declaredGrade),
        determinedGradeId: Value(determinedGrade),
        failedRequirementIds: Value(failed),
        restrictedParticularIds: Value(particulars),
      ));
    }

    for (final sample in await samplesFor(uuid)) {
      final size = await fix(sample.sizeId, database.eggSizes, (t) => t.id,
          sizeByName, names.size);
      final grade = await fix(sample.gradeId, database.eggGrades, (t) => t.id,
          gradeByName, names.grade);
      final deviations = await fixCsv(
          sample.deviationIds,
          database.eggDeviations,
          (t) => t.id,
          deviationByName,
          names.deviation);
      if (size != sample.sizeId ||
          grade != sample.gradeId ||
          deviations != sample.deviationIds) {
        changed = true;
        await (database.update(database.eggSamples)
              ..where((t) => t.id.equals(sample.id)))
            .write(EggSamplesCompanion(
          sizeId: Value(size),
          gradeId: Value(grade),
          deviationIds: Value(deviations),
        ));
      }
    }
    return changed;
  }

  Future<EggInspection?> inspectionByUuid(String uuid) =>
      (database.select(database.eggInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  Future<EggDirection?> directionByUuid(String uuid) =>
      (database.select(database.eggDirections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  /// The direction this inspection raised, if it raised one. Read back on
  /// the record's own page: what was served on the client belongs with the
  /// inspection that found it.
  Future<EggDirection?> directionForInspection(String inspectionUuid) =>
      (database.select(database.eggDirections)
            ..where((t) => t.inspectionUuid.equals(inspectionUuid)))
          .getSingleOrNull();

  /// How many eggs in this inspection carry each deviation.
  ///
  /// One egg can carry several deviations and one deviation can appear on
  /// several eggs, so this counts *eggs affected* per deviation — the number an
  /// inspector needs when justifying a downgrade. Ordered most-frequent first.
  Future<List<DeviationTally>> deviationTally(String inspectionUuid) async {
    final samples = await samplesFor(inspectionUuid);
    final counts = <int, int>{};
    for (final sample in samples) {
      // A deviation ticked twice on one egg still affects one egg.
      for (final id in _ids(sample.deviationIds).toSet()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const [];

    final descriptions = {
      for (final d in await database.select(database.eggDeviations).get())
        d.id: d.description,
    };
    final categoriesById = {
      for (final c
          in await database.select(database.eggDeviationCategories).get())
        c.id: c.name,
    };
    final categoryOf = {
      for (final d in await database.select(database.eggDeviations).get())
        d.id: categoriesById[d.categoryId] ?? '',
    };

    final tally = [
      for (final entry in counts.entries)
        DeviationTally(
          deviationId: entry.key,
          // A deviation recorded before a reference sync removed it still has
          // to be shown; naming the id beats showing a blank row.
          description: descriptions[entry.key] ?? 'Deviation #${entry.key}',
          category: categoryOf[entry.key] ?? '',
          eggsAffected: entry.value,
        ),
    ]..sort((a, b) {
        final byCount = b.eggsAffected.compareTo(a.eggsAffected);
        return byCount != 0 ? byCount : a.description.compareTo(b.description);
      });
    return tally;
  }

  /// Names for a comma-separated id list, in reference order.
  Future<List<String>> requirementNames(String csv) async {
    final wanted = _ids(csv).toSet();
    if (wanted.isEmpty) return const [];
    final rows = await database.select(database.eggRequirements).get();
    return [
      for (final r in rows)
        if (wanted.contains(r.id)) r.description,
    ];
  }

  Future<List<String>> restrictedParticularNames(String csv) async {
    final wanted = _ids(csv).toSet();
    if (wanted.isEmpty) return const [];
    final rows = await database.select(database.eggRestrictedParticulars).get();
    return [
      for (final r in rows)
        if (wanted.contains(r.id)) r.keyword,
    ];
  }

  Future<List<String>> directionRemarkNames(String csv) async {
    final wanted = _ids(csv).toSet();
    if (wanted.isEmpty) return const [];
    final rows = await database.select(database.eggDirectionRemarks).get();
    return [
      for (final r in rows)
        if (wanted.contains(r.id)) r.remarkText,
    ];
  }

  // --- Administrator corrections ------------------------------------------

  /// Re-queues every inspection captured on [date] for upload.
  ///
  /// For when the server lost a batch and it has to go up again. Returns the
  /// number of records actually changed, so the caller can report the truth
  /// rather than assume it worked.
  Future<int> markInspectionsPendingForDate(DateTime date) =>
      markInspectionsPendingBetween(date, date);

  /// Marks every inspection on [date] as already uploaded, without sending it.
  ///
  /// For when records reached the server but the acknowledgement was lost, and
  /// resending would duplicate work.
  Future<int> markInspectionsUploadedForDate(DateTime date) =>
      markInspectionsUploadedBetween(date, date);

  /// The same corrections over a span of days, inclusive of both ends.
  ///
  /// Management filters by date range, and an administrator looking at a week
  /// of records expects the correction to cover what is on screen — applying it
  /// to one day of a visible week would silently do a fraction of the job.
  Future<int> markInspectionsPendingBetween(DateTime from, DateTime to) =>
      _setInspectionUploaded(from, to, uploaded: false);

  Future<int> markInspectionsUploadedBetween(DateTime from, DateTime to) =>
      _setInspectionUploaded(from, to, uploaded: true);

  Future<int> markDirectionsPendingForDate(DateTime date) =>
      markDirectionsPendingBetween(date, date);

  Future<int> markDirectionsUploadedForDate(DateTime date) =>
      markDirectionsUploadedBetween(date, date);

  /// The same corrections over a span of days, inclusive of both ends.
  Future<int> markDirectionsPendingBetween(DateTime from, DateTime to) =>
      _setDirectionUploaded(from, to, uploaded: false);

  Future<int> markDirectionsUploadedBetween(DateTime from, DateTime to) =>
      _setDirectionUploaded(from, to, uploaded: true);

  /// True when [value] falls on or between the calendar days [from] and [to].
  ///
  /// Compared by day rather than by instant: an inspection captured at 16:40 on
  /// the closing day is inside a range that ends that day, which comparing
  /// timestamps directly would exclude.
  static bool _withinDays(DateTime value, DateTime from, DateTime to) {
    final day = DateTime(value.year, value.month, value.day);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Future<int> _setInspectionUploaded(
    DateTime from,
    DateTime to, {
    required bool uploaded,
  }) async {
    final all = await savedInspections();
    final targets = all
        .where((i) => _withinDays(i.inspectedAt.toLocal(), from, to))
        .where((i) => i.isUploaded != uploaded)
        .toList();
    for (final i in targets) {
      await (database.update(database.eggInspections)
            ..where((t) => t.clientUuid.equals(i.clientUuid)))
          .write(EggInspectionsCompanion(isUploaded: Value(uploaded)));
    }
    return targets.length;
  }

  Future<int> _setDirectionUploaded(
    DateTime from,
    DateTime to, {
    required bool uploaded,
  }) async {
    final all = await savedDirections();
    final targets = all
        .where((d) => _withinDays(d.issuedAt.toLocal(), from, to))
        .where((d) => d.isUploaded != uploaded)
        .toList();
    for (final d in targets) {
      await (database.update(database.eggDirections)
            ..where((t) => t.clientUuid.equals(d.clientUuid)))
          .write(EggDirectionsCompanion(isUploaded: Value(uploaded)));
    }
    return targets.length;
  }

  // --- Upload -------------------------------------------------------------

  static List<int> _ids(String csv) => csv
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();

  /// Rounds a number to the decimal places the server column stores.
  ///
  /// Every numeric field here is a DECIMAL on the server, and a raw Dart
  /// double serialises with full binary-float precision. Two cases make that
  /// fatal rather than untidy:
  ///
  ///  * a GPS fix arrives as 26.234899999999996 — twenty digits;
  ///  * the Haugh unit is *computed*, `100 * log10(...)`, so it is essentially
  ///    always 76.61237244897959 rather than 76.61.
  ///
  /// The server rejects both, and because a failed upload is retried forever
  /// the record never leaves the handset. Rounding to the stored precision is
  /// what makes an ordinary inspection uploadable at all.
  static double? _round(double? value, int places) {
    if (value == null) return null;
    if (value.isNaN || value.isInfinite) return null;
    return double.parse(value.toStringAsFixed(places));
  }

  /// Latitude/longitude: DECIMAL(9, 6) — about 11 cm, far finer than a phone
  /// GPS fix, so nothing real is lost.
  static double? _coordinate(double? value) => _round(value, 6);

  /// Egg mass, albumen height and Haugh unit: DECIMAL(6, 2).
  static double? _measurement(double? value) => _round(value, 2);

  /// Uploads one inspection and its photos.
  ///
  /// The server upserts on `clientUuid`, so a retry after a dropped connection
  /// updates rather than duplicates. Only marked uploaded once the server has
  /// confirmed — a half-sent record stays pending and is retried.
  /// A reference id the office can resolve, or null.
  ///
  /// The form offers "Not indicated" on the size and grade pickers, which
  /// are answers rather than rows in the office's lists; they are held as
  /// negative ids so a draft can remember them without a column of its own.
  static int? _officeId(int? id) => id == null || id < 0 ? null : id;

  Future<void> upload(EggInspection inspection, {required String token}) async {
    // Refused here as well as in the sync service. Half an inspection is not a
    // record: uploaded, it comes back on every device as an unfinished one
    // nobody can get rid of.
    if (inspection.status != 'completed') {
      throw StateError(
        'Refusing to upload inspection ${inspection.clientUuid}: '
        'status is "${inspection.status}", not "completed".',
      );
    }
    final samples = await samplesFor(inspection.clientUuid);

    final body = <String, dynamic>{
      'client_uuid': inspection.clientUuid,
      'status': inspection.status,
      'inspected_at': inspection.inspectedAt.toUtc().toIso8601String(),
      'facility_name': inspection.facilityName,
      'facility_type': inspection.facilityTypeId,
      'facility_address': inspection.facilityAddress,
      'facility_phone': inspection.facilityPhone,
      'reason': inspection.reasonId,
      'client_name': inspection.clientName,
      'client_address': inspection.clientAddress,
      'client_contact_person': inspection.clientContactPerson,
      'client_contact_number': inspection.clientContactNumber,
      'client_email': inspection.clientEmail,
      'representative_name': inspection.representativeName,
      'manager_name': inspection.managerName,
      'manager_email': inspection.managerEmail,
      'producer_supplier': inspection.producerSupplier,
      'batch_number': inspection.batchNumber,
      'best_before': inspection.bestBefore?.toIso8601String().split('T').first,
      'tray_size': _officeId(inspection.traySizeId),
      // Whether the inspector seized the consignment rather than serving a
      // rectification period. Empty when the question never arose.
      'seizure_decision': inspection.seizureDecision,
      'eggs_expression_absent': inspection.eggsExpressionAbsent,
      'best_before_absent': inspection.bestBeforeAbsent,
      // What the consignment is declared as. Added with the tolerance rules;
      // without these the server cannot tell which band an inspection was
      // judged against.
      // "Not indicated" is the handset's own answer, not a row the office
      // holds — it is carried locally as a negative id. Sent as such the
      // server reads it as a foreign key it has never heard of and refuses
      // the whole inspection, so it travels as "no claim", which is what it
      // means. The labelling checklist is what records the deviation.
      'declared_size': _officeId(inspection.declaredSizeId),
      'declared_grade': _officeId(inspection.declaredGradeId),
      'sample_size': inspection.sampleSize,
      'pasteurised_present': inspection.pasteurisedPresent,
      'haugh_not_required': inspection.haughNotRequired,
      'determined_grade': inspection.determinedGradeId,
      'grade_overridden': inspection.gradeOverridden,
      'override_reason': inspection.overrideReason,
      'general_comments': inspection.generalComments,
      'non_conformance_comments': inspection.nonConformanceComments,
      'failed_requirements': _ids(inspection.failedRequirementIds),
      'restricted_particulars': _ids(inspection.restrictedParticularIds),
      'restricted_particulars_text': inspection.restrictedParticularsText,
      'latitude': _coordinate(inspection.latitude),
      'longitude': _coordinate(inspection.longitude),
      'samples': [
        for (final s in samples)
          {
            'egg_number': s.eggNumber,
            'mass_g': _measurement(s.massG),
            'size': s.sizeId,
            'grade': s.gradeId,
            'albumen_height_mm': _measurement(s.albumenHeightMm),
            // Computed from mass and albumen height, so it carries full float
            // precision and must be rounded or the server refuses the record.
            'haugh_unit': _measurement(s.haughUnit),
            'deviations': _ids(s.deviationIds),
          },
      ],
    };

    final uri = Uri.parse('$baseUrl/api/eggs/inspections/');
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      if (response.statusCode >= 400 &&
          response.statusCode < 500 &&
          response.statusCode != 401 &&
          response.statusCode != 408 &&
          response.statusCode != 429) {
        throw RecordRejected(response.statusCode, response.body);
      }
      throw http.ClientException(
        'Upload failed (${response.statusCode}): ${response.body}',
        uri,
      );
    }

    // The record is on the server once this POST is answered. It is marked
    // so now: its photographs and signatures follow on their own, and the
    // sync pass keeps retrying any that did not make it. Waiting for them
    // first held a record the office already had at "not synced" whenever a
    // photograph was slow.
    await (database.update(database.eggInspections)
          ..where((t) => t.clientUuid.equals(inspection.clientUuid)))
        .write(const EggInspectionsCompanion(isUploaded: Value(true)));
    try {
      await uploadAttachments(inspection.clientUuid, token: token);
    } on Object catch (error) {
      debugPrint('Eggs: attachments for ${inspection.clientUuid} will be '
          'retried — $error');
    }
  }

  /// The record's photographs and signatures, each sent on its own so one
  /// failure does not force the whole record to be resent — and each marked
  /// only when the server confirmed it, so the next pass retries the rest.
  ///
  /// Called separately by the sync pass as well: a record whose attachments
  /// failed is still marked uploaded, and without this retry those images
  /// would sit on the handset forever with nothing left to carry them up.
  /// How long a photograph or signature may take to go up. Far longer than
  /// [timeout]: a 6 MB photo took three minutes on a slow uplink to the live
  /// server, and the 45 seconds every other call gets cut every one of them
  /// off (Ethan, 2026-09-24).
  static const fileUploadTimeout = Duration(minutes: 5);

  Future<void> uploadAttachments(
    String inspectionUuid, {
    required String token,
  }) async {
    for (final photo in await photosFor(inspectionUuid)) {
      if (photo.isUploaded) continue;
      final file = File(photo.filePath);
      if (!file.existsSync()) continue;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/eggs/inspections/$inspectionUuid/photos/'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['kind'] = photo.kind
        ..fields['caption'] = photo.caption
        // When the photograph was taken, not when it happened to upload. A
        // record synced days later would otherwise carry no capture time at
        // all, since the column is nullable server-side.
        ..fields['captured_at'] = photo.capturedAt.toUtc().toIso8601String()
        ..files.add(await http.MultipartFile.fromPath('image', photo.filePath,
            filename: 'photo_${photo.kind}.jpg'));
      final photoResponse = await request.send().timeout(fileUploadTimeout);
      if (photoResponse.statusCode == 201 || photoResponse.statusCode == 200) {
        await (database.update(database.eggPhotos)
              ..where((t) => t.id.equals(photo.id)))
            .write(const EggPhotosCompanion(isUploaded: Value(true)));
      }
    }

    for (final signature in await signaturesFor(inspectionUuid)) {
      if (signature.isUploaded) continue;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/eggs/inspections/$inspectionUuid/signatures/'),
      )
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['role'] = signature.role
        ..fields['signed_name'] = signature.signedName
        ..fields['declined'] = signature.declined.toString();
      if (signature.signedAt != null) {
        request.fields['signed_at'] =
            signature.signedAt!.toUtc().toIso8601String();
      }
      if (signature.filePath.isNotEmpty) {
        request.files.add(
          // A short part-filename, whatever the file is called on disk: the
          // server's FileField caps the stored name at 100 characters, and
          // the visit sign-off's copies carry two uuids in theirs.
          await http.MultipartFile.fromPath('image', signature.filePath,
              filename: 'signature_${signature.role}.png'),
        );
      }
      final signatureResponse = await request.send().timeout(fileUploadTimeout);
      if (signatureResponse.statusCode == 201 ||
          signatureResponse.statusCode == 200) {
        await (database.update(database.eggSignatures)
              ..where((t) => t.id.equals(signature.id)))
            .write(const EggSignaturesCompanion(isUploaded: Value(true)));
      }
    }
  }

  /// Parses a value the server sends as a JSON number or a decimal string.
  ///
  /// Django serialises DecimalField as a string by default, so a plain cast
  /// would silently drop every coordinate.
  static double? _number(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Parses a date-only field, tolerating a full timestamp.
  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Renders a list of ids as the comma-separated form the tables store.
  static String _csv(Object? value) {
    if (value is! List) return '';
    return value.map((e) => e.toString()).join(',');
  }

  /// Registers a client met in the field.
  ///
  /// Sent to the server first so the row carries the server's own id. A client
  /// invented locally with a made-up id is the situation that produced
  /// "Invalid pk … object does not exist" on every later upload, so an id is
  /// never guessed here.
  ///
  /// With no signal the client is still written locally — the inspection has
  /// to be capturable either way — but with a negative id, which marks it as
  /// not yet registered and keeps it out of the server's numbering.
  Future<EggClient> addClient({
    required String name,
    String tradingName = '',
    String physicalAddress = '',
    String contactPerson = '',
    String telephone = '',
    String email = '',
  }) async {
    final body = {
      'name': name.trim(),
      'trading_name': tradingName.trim(),
      'physical_address': physicalAddress.trim(),
      'contact_person': contactPerson.trim(),
      'telephone': telephone.trim(),
      'email': email.trim(),
    };

    int id = await _nextLocalId(database.eggClients.id);
    String updatedAt = '';
    final token = await storedToken();
    if (token != null) {
      try {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/api/eggs/clients/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final j = jsonDecode(response.body) as Map<String, dynamic>;
          id = j['id'] as int;
          updatedAt = j['updated_at'] as String? ?? '';
        }
      } on Object {
        // Offline or refused: keep the local row so capture can continue.
      }
    }

    final row = EggClientsCompanion.insert(
      id: Value(id),
      name: body['name']!,
      tradingName: Value(body['trading_name']!),
      physicalAddress: Value(body['physical_address']!),
      contactPerson: Value(body['contact_person']!),
      telephone: Value(body['telephone']!),
      email: Value(body['email']!),
      updatedAt: Value(updatedAt),
    );
    await database.into(database.eggClients).insertOnConflictUpdate(row);
    return (await (database.select(database.eggClients)
          ..where((t) => t.id.equals(id)))
        .getSingle());
  }

  /// Registers premises met in the field. As [addClient].
  Future<EggFacility> addFacility({
    required String name,
    int? facilityTypeId,
    String physicalAddress = '',
    String telephone = '',
  }) async {
    final body = {
      'name': name.trim(),
      'facility_type': facilityTypeId,
      'physical_address': physicalAddress.trim(),
      'telephone': telephone.trim(),
    };

    int id = await _nextLocalId(database.eggFacilities.id);
    String updatedAt = '';
    final token = await storedToken();
    if (token != null) {
      try {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/api/eggs/facilities/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          final j = jsonDecode(response.body) as Map<String, dynamic>;
          id = j['id'] as int;
          updatedAt = j['updated_at'] as String? ?? '';
        }
      } on Object {
        // Offline or refused.
      }
    }

    await database.into(database.eggFacilities).insertOnConflictUpdate(
          EggFacilitiesCompanion.insert(
            id: Value(id),
            name: body['name']! as String,
            facilityTypeId: Value(facilityTypeId),
            physicalAddress: Value(body['physical_address']! as String),
            telephone: Value(body['telephone']! as String),
            updatedAt: Value(updatedAt),
          ),
        );
    return (await (database.select(database.eggFacilities)
          ..where((t) => t.id.equals(id)))
        .getSingle());
  }

  /// An id that cannot collide with the server's.
  ///
  /// Negative and descending, so a row registered with no signal is obviously
  /// local and a later download cannot overwrite the wrong record.
  Future<int> _nextLocalId(GeneratedColumn<int> column) async {
    final rows = await database
        .customSelect(
          'SELECT MIN(${column.name}) AS lowest FROM ${column.tableName}',
        )
        .getSingle();
    final lowest = rows.data['lowest'] as int? ?? 0;
    return lowest < 0 ? lowest - 1 : -1;
  }

  /// A token that can actually be used, minting a new one if the stored access
  /// token has run out.
  ///
  /// The access token lives about half a day; an inspector can be out for
  /// several. Without this, uploads simply stopped once it expired, and every
  /// saved inspection said "will upload automatically" while nothing left the
  /// handset. Returns null when there is no way to authenticate — which the
  /// caller must report rather than treat as "later".
  Future<String?> storedToken() async {
    final access = await database.readSyncState('auth.accessToken');
    if (access != null && access.isNotEmpty && !_isKnownExpired(access)) {
      return access;
    }
    // One refresh at a time. The list pages, the menu, the background sync
    // and Server Sync all ask for a token, often within the same second,
    // and with refresh-token rotation on the server a refresh token is
    // single-use: two callers posting the same one means the second is
    // refused, and whichever answer lands last decides what the handset
    // keeps. Callers that arrive mid-refresh wait for the one in flight.
    final running = _refreshInFlight;
    if (running != null) return running;
    final pass = _refreshAccessToken();
    _refreshInFlight = pass;
    try {
      return await pass;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<String?>? _refreshInFlight;

  Future<String?> _refreshAccessToken() async {
    final refresh = await database.readSyncState('auth.refreshToken');
    if (refresh == null || refresh.isEmpty || _isKnownExpired(refresh)) {
      return null;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/auth/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(timeout);
      if (response.statusCode == 401) {
        // The server has looked at this refresh token and refused it — it
        // was signed by another server, or revoked. It will never be
        // accepted, so keeping it only makes the handset post it again
        // every two minutes for ever, with every upload waiting behind it
        // and nothing on screen to say why. Cleared, the next sync says
        // plainly that a sign-in with signal is needed. A tablet that had
        // last signed in against the deployed server and then taken a
        // build pointed at a local one sat in exactly that loop
        // (2026-09-23).
        await database.writeSyncState('auth.accessToken', '');
        await database.writeSyncState('auth.refreshToken', '');
        return null;
      }
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final minted = body['access'] as String?;
      if (minted == null || minted.isEmpty) return null;
      await database.writeSyncState('auth.accessToken', minted);
      // Rotation is on for some deployments; keep whatever comes back.
      final rotated = body['refresh'] as String?;
      if (rotated != null && rotated.isNotEmpty) {
        await database.writeSyncState('auth.refreshToken', rotated);
      }
      return minted;
    } on Object {
      // No signal, or the refresh token has been revoked. Either way there is
      // no token to upload with right now.
      return null;
    }
  }

  /// Whether a JWT's `exp` has demonstrably passed.
  ///
  /// Read without verifying the signature: only the server can do that. This
  /// exists purely to skip a round trip that is certain to fail, so a token
  /// whose expiry cannot be read is reported as *not* known to be expired and
  /// sent anyway. The server is the authority, and refusing to try would
  /// strand an inspector over a parsing quirk rather than a real rejection.
  ///
  /// A minute of slack, so a token about to lapse mid-upload is renewed first.
  static bool _isKnownExpired(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return DateTime.now().toUtc().isAfter(
            expiry.subtract(const Duration(minutes: 1)),
          );
    } on Object {
      return false;
    }
  }

  /// Pulls this inspector's records back down from the server.
  ///
  /// Needed because work captured on one handset (or seeded centrally) is
  /// otherwise invisible on another. Anything already held locally and not yet
  /// uploaded is left alone — a pending local edit must never be overwritten
  /// by the server's older copy.
  Future<int> downloadMine({required String token}) async {
    // The server returns only the caller's own records, so whoever is signed
    // in here is by construction the owner of everything that arrives.
    final owner = await currentInspector();
    var written = 0;
    final headers = {'Authorization': 'Bearer $token'};
    final inspectionCursor =
        await database.readSyncState('eggs.inspections.downloadCursor');
    final directionCursor =
        await database.readSyncState('eggs.directions.downloadCursor');

    final localPending = {
      for (final i in await savedInspections())
        if (!i.isUploaded) i.clientUuid,
    };
    final localPendingDirections = {
      for (final d in await savedDirections())
        if (!d.isUploaded) d.clientUuid,
    };

    final inspectionsUri = Uri.parse('$baseUrl/api/eggs/inspections/').replace(
      queryParameters: {
        if (inspectionCursor != null && inspectionCursor.isNotEmpty)
          'updated_since': inspectionCursor,
      },
    );
    final response =
        await _client.get(inspectionsUri, headers: headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Could not fetch inspections (${response.statusCode}).',
        inspectionsUri,
      );
    }
    final decoded = jsonDecode(response.body);
    final inspections = (decoded is Map<String, dynamic>
            ? (decoded['results'] as List<dynamic>? ?? const [])
            : decoded as List<dynamic>)
        .cast<Map<String, dynamic>>();

    DateTime? newestInspection;
    for (final j in inspections) {
      final updatedAt = DateTime.tryParse('${j['updated_at'] ?? ''}');
      if (updatedAt != null &&
          (newestInspection == null || updatedAt.isAfter(newestInspection))) {
        newestInspection = updatedAt;
      }
      final uuid = j['client_uuid'] as String;
      if (localPending.contains(uuid)) continue;
      // A draft is work in progress on one handset, not a record to
      // distribute. Writing one back re-created inspections the inspector had
      // just discarded, so the "unfinished inspection" banner returned every
      // time the menu refreshed and could never be cleared.
      if ((j['status'] as String? ?? 'completed') == 'draft') continue;
      final at = DateTime.parse(j['inspected_at'] as String).toLocal();
      await database.into(database.eggInspections).insertOnConflictUpdate(
            EggInspectionsCompanion.insert(
              clientUuid: uuid,
              inspectedAt: at,
              updatedAt: at,
              status: Value(j['status'] as String? ?? 'completed'),
              facilityName: Value(j['facility_name'] as String? ?? ''),
              facilityTypeId: Value(j['facility_type'] as int?),
              facilityAddress: Value(j['facility_address'] as String? ?? ''),
              facilityPhone: Value(j['facility_phone'] as String? ?? ''),
              reasonId: Value(j['reason'] as int?),
              clientName: Value(j['client_name'] as String? ?? ''),
              clientAddress: Value(j['client_address'] as String? ?? ''),
              clientContactPerson:
                  Value(j['client_contact_person'] as String? ?? ''),
              clientContactNumber:
                  Value(j['client_contact_number'] as String? ?? ''),
              clientEmail: Value(j['client_email'] as String? ?? ''),
              representativeName:
                  Value(j['representative_name'] as String? ?? ''),
              managerName: Value(j['manager_name'] as String? ?? ''),
              managerEmail: Value(j['manager_email'] as String? ?? ''),
              producerSupplier: Value(j['producer_supplier'] as String? ?? ''),
              batchNumber: Value(j['batch_number'] as String? ?? ''),
              bestBefore: Value(_date(j['best_before'])),
              traySizeId: Value(j['tray_size'] as int?),
              sampleSize: Value(j['sample_size'] as int?),
              pasteurisedPresent:
                  Value(j['pasteurised_present'] as bool? ?? false),
              haughNotRequired:
                  Value(j['haugh_not_required'] as bool? ?? false),
              determinedGradeId: Value(j['determined_grade'] as int?),
              gradeOverridden: Value(j['grade_overridden'] as bool? ?? false),
              overrideReason: Value(j['override_reason'] as String? ?? ''),
              generalComments: Value(j['general_comments'] as String? ?? ''),
              nonConformanceComments:
                  Value(j['non_conformance_comments'] as String? ?? ''),
              failedRequirementIds: Value(_csv(j['failed_requirements'])),
              restrictedParticularIds: Value(_csv(j['restricted_particulars'])),
              restrictedParticularsText:
                  Value(j['restricted_particulars_text'] as String? ?? ''),
              eggsExpressionAbsent: Value(j['eggs_expression_absent'] == true),
              bestBeforeAbsent: Value(j['best_before_absent'] == true),
              latitude: Value(_number(j['latitude'])),
              longitude: Value(_number(j['longitude'])),
              inspectorUsername: Value(owner),
              // Came from the server, so it is by definition already there.
              isUploaded: const Value(true),
            ),
          );

      await (database.delete(database.eggSamples)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      for (final s in (j['samples'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()) {
        await database.into(database.eggSamples).insert(
              EggSamplesCompanion.insert(
                inspectionUuid: uuid,
                eggNumber: s['egg_number'] as int,
                massG: Value(double.tryParse('${s['mass_g']}')),
                sizeId: Value(s['size'] as int?),
                gradeId: Value(s['grade'] as int?),
                albumenHeightMm:
                    Value(double.tryParse('${s['albumen_height_mm']}')),
                haughUnit: Value(double.tryParse('${s['haugh_unit']}')),
                deviationIds: Value(
                  (s['deviations'] as List<dynamic>? ?? const []).join(','),
                ),
              ),
            );
      }

      // Photographs. Only filled in when the device holds none of its own for
      // this record: a locally-captured photo points at a file on this handset
      // and must not be replaced by a server URL, but an inspection captured
      // on someone else's phone would otherwise claim it had no photos at all.
      if ((await photosFor(uuid)).isEmpty) {
        for (final photo in (j['photos'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()) {
          final image = '${photo['image'] ?? ''}';
          if (image.isEmpty) continue;
          await database.into(database.eggPhotos).insert(
                EggPhotosCompanion.insert(
                  inspectionUuid: uuid,
                  kind: photo['kind'] as String? ?? 'egg',
                  // The server returns a path; store it absolute so the viewer
                  // does not have to know where it came from.
                  filePath: image.startsWith('http') ? image : '$baseUrl$image',
                  caption: Value(photo['caption'] as String? ?? ''),
                  capturedAt:
                      DateTime.tryParse('${photo['captured_at']}')?.toLocal() ??
                          at,
                  // It came from the server, so it is by definition up there.
                  isUploaded: const Value(true),
                ),
              );
        }
      }
      written++;
    }

    if (newestInspection != null) {
      await database.writeSyncState(
        'eggs.inspections.downloadCursor',
        newestInspection.toUtc().toIso8601String(),
      );
    }

    final directionsUri = Uri.parse('$baseUrl/api/eggs/directions/').replace(
      queryParameters: {
        if (directionCursor != null && directionCursor.isNotEmpty)
          'updated_since': directionCursor,
      },
    );
    final dirResponse =
        await _client.get(directionsUri, headers: headers).timeout(timeout);
    if (dirResponse.statusCode == 200) {
      final dirDecoded = jsonDecode(dirResponse.body);
      final directions = (dirDecoded is Map<String, dynamic>
              ? (dirDecoded['results'] as List<dynamic>? ?? const [])
              : dirDecoded as List<dynamic>)
          .cast<Map<String, dynamic>>();
      DateTime? newestDirection;
      for (final j in directions) {
        final updatedAt = DateTime.tryParse('${j['updated_at'] ?? ''}');
        if (updatedAt != null &&
            (newestDirection == null || updatedAt.isAfter(newestDirection))) {
          newestDirection = updatedAt;
        }
        final uuid = j['client_uuid'] as String;
        if (localPendingDirections.contains(uuid)) continue;
        // A draft belongs to the handset writing it; writing one back would
        // resurrect a direction the inspector had discarded.
        if ((j['status'] as String? ?? 'completed') == 'draft') continue;
        final at = DateTime.parse(j['issued_at'] as String).toLocal();
        await database.into(database.eggDirections).insertOnConflictUpdate(
              EggDirectionsCompanion.insert(
                clientUuid: uuid,
                issuedAt: at,
                updatedAt: at,
                status: Value(j['status'] as String? ?? 'completed'),
                directionNumber: Value(j['direction_number'] as String? ?? ''),
                labellingPart: Value(j['labelling_part'] as bool? ?? false),
                qualityPart: Value(j['quality_part'] as bool? ?? false),
                labelCorrectBy: Value(_date(j['label_correct_by'])),
                qualityCorrectBy: Value(_date(j['quality_correct_by'])),
                quantityRemoved:
                    Value(double.tryParse('${j['quantity_removed']}')),
                remarkIds: Value(
                  (j['remarks'] as List<dynamic>? ?? const []).join(','),
                ),
                additionalRemarks:
                    Value(j['additional_remarks'] as String? ?? ''),
                clientName: Value(j['client_name'] as String? ?? ''),
                producerSupplier:
                    Value(j['producer_supplier'] as String? ?? ''),
                // The inspection this was raised from. Without it the summary
                // claims every downloaded direction was issued on its own.
                inspectionUuid: Value(j['inspection_uuid'] as String?),
                latitude: Value(_number(j['latitude'])),
                longitude: Value(_number(j['longitude'])),
                inspectorUsername: Value(owner),
                isUploaded: const Value(true),
              ),
            );
        written++;
      }
      if (newestDirection != null) {
        await database.writeSyncState(
          'eggs.directions.downloadCursor',
          newestDirection.toUtc().toIso8601String(),
        );
      }
    }

    return written;
  }

  void dispose() => _client.close();
}

/// Names of the rows in the bundled rules, by the ids the bundle gave them.
///
/// The bundle is the only record of what a stale id used to mean once the
/// synced tables have replaced its rows, so the names are read from the asset
/// rather than from the database.
class _BundledNames {
  _BundledNames._(this._data);

  static _BundledNames? _cached;

  static Future<_BundledNames> load() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await rootBundle.loadString(EggsRepository.bundledRulesAsset);
      final body = jsonDecode(raw) as Map<String, dynamic>;
      return _cached = _BundledNames._(
        (body['data'] as Map<String, dynamic>?) ?? const {},
      );
    } on Object {
      // No asset bundle to hand (a bare test binding, say): nothing can be
      // named, so nothing is re-pointed. Not cached — the next call may work.
      return _BundledNames._(const {});
    }
  }

  final Map<String, dynamic> _data;

  String? _lookup(String collection, int id, String field) {
    for (final row in (_data[collection] as List<dynamic>?) ?? const []) {
      final r = row as Map<String, dynamic>;
      if (r['id'] == id) return r[field] as String?;
    }
    return null;
  }

  String? size(int id) => _lookup('sizes', id, 'name');
  String? grade(int id) => _lookup('grades', id, 'name');
  String? reason(int id) => _lookup('inspection_reasons', id, 'name');
  String? traySize(int id) => _lookup('tray_sizes', id, 'name');
  String? facilityType(int id) => _lookup('facility_types', id, 'name');
  String? requirement(int id) => _lookup('requirements', id, 'description');
  String? particular(int id) =>
      _lookup('restricted_particulars', id, 'keyword');

  /// "<category name>|<description>", see the deviation lookup.
  String? deviation(int id) {
    for (final row in (_data['deviations'] as List<dynamic>?) ?? const []) {
      final r = row as Map<String, dynamic>;
      if (r['id'] != id) continue;
      final category =
          _lookup('deviation_categories', r['category'] as int, 'name');
      if (category == null) return null;
      return '$category|${r['description']}';
    }
    return null;
  }
}

/// What the egg documents need about a record and its signing.
class _EggDocumentContext {
  const _EggDocumentContext({
    required this.facilityName,
    required this.facilityAddress,
    required this.facilityType,
    required this.traySize,
    required this.representative,
    required this.inspectorName,
    required this.authorisedPersonName,
    required this.inspectorSignaturePath,
    required this.authorisedPersonSignaturePath,
    required this.labelPhotoPath,
  });

  final String facilityName;
  final String facilityAddress;
  final String facilityType;
  final String traySize;
  final String representative;
  final String inspectorName;
  final String authorisedPersonName;
  final String inspectorSignaturePath;
  final String authorisedPersonSignaturePath;
  final String labelPhotoPath;
}
