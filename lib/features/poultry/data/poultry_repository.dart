import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';
import '../domain/poultry_rules.dart';

/// Poultry reference data and captured grading inspections.
///
/// Same shape as [EggsRepository]: the bundled asset and the endpoint produce
/// an identical payload, so one writer handles both and they cannot drift.
class PoultryRepository {
  PoultryRepository({
    required this.database,
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final LocalDatabase database;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// Rules shipped inside the app, so a handset that has never had signal can
  /// still capture. Regenerate with `manage.py export_poultry_reference`.
  static const bundledRulesAsset = 'assets/reference/poultry_reference.json';

  static const cursorKey = 'poultry.cursor';
  static const lastSyncAtKey = 'poultry.lastSyncAt';

  // ---------------------------------------------------------------- reference

  /// Loads the bundled rules if this device has none yet.
  ///
  /// Returns how many rows were written; zero when the store is already
  /// populated, so calling it on every launch is cheap.
  Future<int> loadBundledRulesIfEmpty() async {
    final existing = await _count(database.poultryChecklistItems);
    if (existing > 0) return 0;
    final raw = await rootBundle.loadString(bundledRulesAsset);
    return _writeReference(
      jsonDecode(raw) as Map<String, dynamic>,
      // Deliberately does not advance the cursor: the bundle is a snapshot
      // taken at build time, and adopting its stamp would make the first
      // delta skip everything changed between the build and the install.
      advanceCursor: false,
    );
  }

  /// Pulls reference data from the server, from [cursorKey] onwards.
  Future<int> syncReference({bool fromScratch = false}) async {
    final cursor =
        fromScratch ? null : await database.readSyncState(cursorKey);
    final uri = Uri.parse('$baseUrl/api/poultry/reference/').replace(
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'since': cursor,
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Poultry reference sync failed with status ${response.statusCode}.',
        uri,
      );
    }
    return _writeReference(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Writes a reference payload read from disk rather than the asset bundle.
  ///
  /// The bundled asset is the only thing that makes a brand-new handset
  /// usable, so the tests read the real exported file. Going through the same
  /// writer the network and bundle paths use means a test cannot pass against
  /// a code path the app does not take.
  @visibleForTesting
  Future<int> writeReferenceForTest(Map<String, dynamic> body) =>
      _writeReference(body, advanceCursor: false);

  Future<int> _writeReference(
    Map<String, dynamic> body, {
    bool advanceCursor = true,
  }) async {
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    var written = 0;

    List<Map<String, dynamic>> rows(String key) =>
        ((data[key] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>();

    String stamp(Map<String, dynamic> j) =>
        j['updated_at'] as String? ?? '';

    await database.transaction(() async {
      for (final j in rows('meat_types')) {
        await database.into(database.poultryMeatTypes).insertOnConflictUpdate(
              PoultryMeatTypesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('grades')) {
        await database.into(database.poultryGrades).insertOnConflictUpdate(
              PoultryGradesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                rank: Value(j['rank'] as int?),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('portion_types')) {
        await database
            .into(database.poultryPortionTypes)
            .insertOnConflictUpdate(
              PoultryPortionTypesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('designation_classes')) {
        await database
            .into(database.poultryDesignationClasses)
            .insertOnConflictUpdate(
              PoultryDesignationClassesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('alternative_designation_classes')) {
        await database
            .into(database.poultryAltDesignationClasses)
            .insertOnConflictUpdate(
              PoultryAltDesignationClassesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('designation_grade_links')) {
        await database
            .into(database.poultryDesignationGradeLinks)
            .insertOnConflictUpdate(
              PoultryDesignationGradeLinksCompanion.insert(
                id: Value(j['id'] as int),
                meatTypeId: j['meat_type'] as int,
                designationClassId: j['designation_class'] as int,
                gradeId: j['grade'] as int,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('alternative_designation_grade_links')) {
        await database
            .into(database.poultryAltDesignationGradeLinks)
            .insertOnConflictUpdate(
              PoultryAltDesignationGradeLinksCompanion.insert(
                id: Value(j['id'] as int),
                meatTypeId: j['meat_type'] as int,
                altDesignationClassId:
                    j['alternative_designation_class'] as int,
                gradeId: j['grade'] as int,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('checklist_items')) {
        await database
            .into(database.poultryChecklistItems)
            .insertOnConflictUpdate(
              PoultryChecklistItemsCompanion.insert(
                id: Value(j['id'] as int),
                kind: j['kind'] as String,
                originalId: j['original_id'] as int,
                description: j['description'] as String,
                regulationReference:
                    Value(j['regulation_reference'] as String? ?? ''),
                minLetteringHeight:
                    Value(j['min_lettering_height'] as String? ?? ''),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('restricted_particulars')) {
        await database
            .into(database.poultryRestrictedParticulars)
            .insertOnConflictUpdate(
              PoultryRestrictedParticularsCompanion.insert(
                id: Value(j['id'] as int),
                code: Value(j['code'] as String? ?? ''),
                description: j['description'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('inspection_reasons')) {
        await database
            .into(database.poultryInspectionReasons)
            .insertOnConflictUpdate(
              PoultryInspectionReasonsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('inspection_locations')) {
        await database
            .into(database.poultryInspectionLocations)
            .insertOnConflictUpdate(
              PoultryInspectionLocationsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                description: Value(j['description'] as String? ?? ''),
                code: Value(j['code'] as String? ?? ''),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('direction_remarks')) {
        await database
            .into(database.poultryDirectionRemarks)
            .insertOnConflictUpdate(
              PoultryDirectionRemarksCompanion.insert(
                id: Value(j['id'] as int),
                remarkText: j['text'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }

      if (advanceCursor) {
        final cursor = body['cursor'] as String?;
        if (cursor != null && cursor.isNotEmpty) {
          await database.writeSyncState(cursorKey, cursor);
        }
      }
      await database.writeSyncState(
        lastSyncAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    });

    return written;
  }

  Future<int> _count(TableInfo<Table, dynamic> table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM ${table.actualTableName}')
        .getSingle();
    return row.read<int>('c');
  }

  // ------------------------------------------------------------ reference reads

  Future<List<PoultryMeatTypeRef>> meatTypes() async {
    final rows = await (database.select(database.poultryMeatTypes)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryMeatTypeRef(id: r.id, name: r.name),
    ];
  }

  Future<List<PoultryGradeRef>> grades() async {
    final rows = await (database.select(database.poultryGrades)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows)
        PoultryGradeRef(id: r.id, name: r.name, rank: r.rank),
    ];
  }

  Future<List<PoultryDesignationRef>> portionTypes() async {
    final rows = await (database.select(database.poultryPortionTypes)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.name),
    ];
  }

  Future<List<PoultryDesignationRef>> designationClasses() async {
    final rows = await (database.select(database.poultryDesignationClasses)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.name),
    ];
  }

  Future<List<PoultryDesignationRef>> alternativeDesignationClasses() async {
    final rows = await (database.select(database.poultryAltDesignationClasses)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.name),
    ];
  }

  Future<List<PoultryGradeLink>> designationGradeLinks() async {
    final rows = await (database.select(database.poultryDesignationGradeLinks)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [
      for (final r in rows)
        PoultryGradeLink(
          meatTypeId: r.meatTypeId,
          designationId: r.designationClassId,
          gradeId: r.gradeId,
        ),
    ];
  }

  Future<List<PoultryGradeLink>> alternativeGradeLinks() async {
    final rows =
        await (database.select(database.poultryAltDesignationGradeLinks)
              ..where((t) => t.isActive.equals(true)))
            .get();
    return [
      for (final r in rows)
        PoultryGradeLink(
          meatTypeId: r.meatTypeId,
          designationId: r.altDesignationClassId,
          gradeId: r.gradeId,
        ),
    ];
  }

  Future<List<PoultryChecklistItemRef>> checklistItems() async {
    final rows = await (database.select(database.poultryChecklistItems)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.kind),
            (t) => OrderingTerm(expression: t.sortOrder),
          ]))
        .get();
    return [
      for (final r in rows)
        PoultryChecklistItemRef(
          id: r.id,
          kind: switch (r.kind) {
            'portion' => PoultryChecklistKind.portion,
            'pack' => PoultryChecklistKind.pack,
            'label_inner' => PoultryChecklistKind.labelInner,
            'label_outer' => PoultryChecklistKind.labelOuter,
            'container' => PoultryChecklistKind.container,
            'label_grading' => PoultryChecklistKind.labelGrading,
            'label_portion' => PoultryChecklistKind.labelPortion,
            _ => PoultryChecklistKind.grading,
          },
          originalId: r.originalId,
          description: r.description,
          regulationReference: r.regulationReference,
          minLetteringHeight: r.minLetteringHeight,
        ),
    ];
  }

  Future<List<PoultryDesignationRef>> inspectionReasons() async {
    final rows = await (database.select(database.poultryInspectionReasons)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.name),
    ];
  }

  /// Locations, labelled by `name`.
  ///
  /// The original displays `description`, where ids 5 and 6 both read "Import"
  /// because of a seed bug it never corrected. Showing three identical options
  /// gives an inspector no way to pick the right one, so the unambiguous
  /// `name` is used for display while the id stored stays the original's.
  Future<List<PoultryDesignationRef>> inspectionLocations() async {
    final rows = await (database.select(database.poultryInspectionLocations)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.name),
    ];
  }

  Future<List<PoultryDesignationRef>> directionRemarks() async {
    final rows = await (database.select(database.poultryDirectionRemarks)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [
      for (final r in rows)
        PoultryDesignationRef(id: r.id, name: r.remarkText),
    ];
  }

  Future<List<PoultryDesignationRef>> restrictedParticulars() async {
    final rows =
        await (database.select(database.poultryRestrictedParticulars)
              ..where((t) => t.isActive.equals(true)))
            .get();
    return [
      for (final r in rows)
        PoultryDesignationRef(id: r.id, name: r.description),
    ];
  }

  // ------------------------------------------------------------------- capture

  Future<void> saveInspection(PoultryInspectionsCompanion row) =>
      database.into(database.poultryInspections).insertOnConflictUpdate(row);

  /// Inspections captured by [username].
  ///
  /// Scoped rather than global: a shared handset must not show one inspector
  /// another's work. Rows with no owner predate ownership and are shown to
  /// whoever is signed in, because there is no better answer available.
  Future<List<PoultryInspection>> savedInspections(String username) async {
    final rows = await (database.select(database.poultryInspections)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.inspectedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    return [
      for (final r in rows)
        if (r.inspectorUsername.isEmpty ||
            r.inspectorUsername.toLowerCase() == username.toLowerCase())
          r,
    ];
  }

  Future<PoultryInspection?> inspectionByUuid(String uuid) =>
      (database.select(database.poultryInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  Future<String?> storedToken() =>
      database.readSyncState('auth.accessToken');

  // -------------------------------------------------------------------- upload

  Future<void> upload(
    PoultryInspection inspection, {
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/api/poultry/inspections/');
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(_payload(inspection)),
        )
        .timeout(timeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw http.ClientException(
        'Upload failed with status ${response.statusCode}: ${response.body}',
        uri,
      );
    }

    await (database.update(database.poultryInspections)
          ..where((t) => t.clientUuid.equals(inspection.clientUuid)))
        .write(const PoultryInspectionsCompanion(isUploaded: Value(true)));
  }

  Map<String, dynamic> _payload(PoultryInspection i) => {
        'client_uuid': i.clientUuid,
        'status': i.status,
        'inspected_at': i.inspectedAt.toUtc().toIso8601String(),
        'location': i.locationId,
        'reason': i.reasonId,
        'facility_name': i.facilityName,
        'facility_address': i.facilityAddress,
        'facility_telephone': i.facilityTelephone,
        'company_reg_number': i.companyRegNumber,
        'contact_person': i.contactPerson,
        'contact_person_email': i.contactPersonEmail,
        'manager_name': i.managerName,
        'manager_email': i.managerEmail,
        'client_email': i.clientEmail,
        'client_email_2': i.clientEmail2,
        'producer_trading_name': i.producerTradingName,
        'meat_type': i.meatTypeId,
        'portion_type': i.portionTypeId,
        'designation_class': i.designationClassId,
        'alternative_designation_class': i.altDesignationClassId,
        'product_details': i.productDetails,
        'sample_number': i.sampleNumber,
        'grade': i.gradeId,
        'restricted_particulars': _ids(i.restrictedParticularIds),
        'compliant_item_ids': i.compliantItemIds,
        'inspection_comments': i.inspectionComments,
        'direction_comments': i.directionComments,
        'direction_remarks': i.directionRemarks,
        'direction_remark_type': i.directionRemarkTypeId,
        'no_client_signature_present': i.noClientSignaturePresent,
        'latitude': i.latitude,
        'longitude': i.longitude,
      };

  static List<int> _ids(String csv) => [
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ];

  // ------------------------------------------------ bulk status corrections

  /// True when [value] falls on or between the calendar days [from] and [to].
  static bool _withinDays(DateTime value, DateTime from, DateTime to) {
    final day = DateTime(value.year, value.month, value.day);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  Future<int> markInspectionsPendingBetween(DateTime from, DateTime to) =>
      _setUploaded(from, to, uploaded: false);

  Future<int> markInspectionsUploadedBetween(DateTime from, DateTime to) =>
      _setUploaded(from, to, uploaded: true);

  Future<int> _setUploaded(
    DateTime from,
    DateTime to, {
    required bool uploaded,
  }) async {
    final all = await database.select(database.poultryInspections).get();
    final targets = all
        .where((i) => _withinDays(i.inspectedAt.toLocal(), from, to))
        .where((i) => i.isUploaded != uploaded)
        .toList();
    for (final i in targets) {
      await (database.update(database.poultryInspections)
            ..where((t) => t.clientUuid.equals(i.clientUuid)))
          .write(PoultryInspectionsCompanion(isUploaded: Value(uploaded)));
    }
    return targets.length;
  }

  void dispose() => _client.close();
}
