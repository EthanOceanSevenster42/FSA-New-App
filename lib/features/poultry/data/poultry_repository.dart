import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'dart:io';

import '../../../core/data/local_database.dart';
import '../../../core/documents/direction_pdf.dart';
import '../../../core/documents/fsa_checklist_pdf.dart';
import '../../../core/documents/fsa_documents.dart';
import '../../../core/documents/quid_checklist_pdf.dart';
import '../domain/poultry_rules.dart';
import '../domain/quid_determination.dart';
import '../domain/quid_flow.dart';
import '../../../core/data/regulation_reference.dart';

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
    final cursor = fromScratch ? null : await database.readSyncState(cursorKey);
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

    String stamp(Map<String, dynamic> j) => j['updated_at'] as String? ?? '';

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
          regulationReference: cleanRegulation(r.regulationReference),
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
      for (final r in rows) PoultryDesignationRef(id: r.id, name: r.remarkText),
    ];
  }

  Future<List<PoultryDesignationRef>> restrictedParticulars() async {
    final rows = await (database.select(database.poultryRestrictedParticulars)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [
      for (final r in rows)
        PoultryDesignationRef(id: r.id, name: r.description),
    ];
  }

  // -------------------------------------------------------------- directory

  /// The premises directory, shared with the egg module.
  ///
  /// One directory, not one per commodity: the abattoir an egg inspector
  /// visited last week is the same building a poultry inspector stands in
  /// today, and a second copy would just be the same names spelled
  /// differently. The rows are synced by the egg reference feed, which the
  /// home screen already keeps fresh.
  Future<List<EggFacility>> facilities() =>
      (database.select(database.eggFacilities)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<EggClient>> clients() => (database.select(database.eggClients)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .get();

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

  Future<String?> storedToken() => database.readSyncState('auth.accessToken');

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
        // Restricted particulars are not sent: they are read off the label,
        // and the Label/Container checklist is the record that carries them.
        'compliant_item_ids': i.compliantItemIds,
        'grading_by_sample': i.gradingBySample,
        'inspection_comments': i.inspectionComments,
        'direction_comments': i.directionComments,
        'direction_remarks': i.directionRemarks,
        'direction_remark_type': i.directionRemarkTypeId,
        'seizure_decision': i.seizureDecision,
        'no_client_signature_present': i.noClientSignaturePresent,
        'latitude': i.latitude,
        'longitude': i.longitude,
      };

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

  /// The direction served off a poultry record — SOP-APS-001.
  ///
  /// The notice itself, not the checklist behind it: the deviations cited,
  /// the date they must be put right by, and the two signatures. Poultry
  /// raised directions, uploaded them as data and rendered nothing, so the
  /// person it was served on had no sheet to read and the office had to
  /// draw one itself — the same gap raw had before it grew this.
  ///
  /// Built from whichever record the direction was raised off: a grading
  /// inspection cites the carcass and packing rows, a label/container
  /// checklist the marking ones, and only the lists that record actually
  /// worked are judged.
  Future<File?> buildDirection(String uuid, {Directory? into}) async {
    final direction = await (database.select(database.poultryDirections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (direction == null) return null;
    final grading = await (database.select(database.poultryInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    final label = await (database.select(database.poultryLabelInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (grading == null && label == null) return null;

    final inspectorUsername =
        grading?.inspectorUsername ?? label?.inspectorUsername ?? '';
    final ctx = await _documentContext(uuid, inspectorUsername);
    final inspectedAt =
        grading?.inspectedAt ?? label?.inspectedAt ?? direction.issuedAt;
    final product = grading?.productDetails.isNotEmpty ?? false
        ? grading!.productDetails
        : (label?.productDetails ?? '');

    // Only the lists the record in hand worked. Judging a grading
    // inspection against the marking rows would cite deviations on a
    // notice for requirements nobody was asked about.
    final kinds = <PoultryChecklistKind>{
      if (grading != null) ...[
        PoultryChecklistKind.grading,
        PoultryChecklistKind.portion,
        PoultryChecklistKind.pack,
      ],
      if (label != null) ...[
        PoultryChecklistKind.labelInner,
        PoultryChecklistKind.labelOuter,
        PoultryChecklistKind.container,
      ],
    };
    final ticked = <int>{
      if (grading != null) ..._tickedIds(grading.compliantItemIds),
      if (label != null) ..._tickedIds(label.compliantItemIds),
    };
    final items = await checklistItems();
    final findings = PoultryRules.findings(
      items: [
        for (final item in items)
          if (kinds.contains(item.kind)) item,
      ],
      compliantItemIds: ticked,
    );

    final reasonId = grading?.reasonId ?? label?.reasonId;
    final reasons = await inspectionReasons();
    final reason = reasonId == null
        ? ''
        : reasons
            .where((r) => r.id == reasonId)
            .map((r) => r.name)
            .firstWhere((_) => true, orElse: () => '');

    return DirectionPdf.write(
      out: _poultryDocumentFile(
          grading?.facilityName ?? label?.facilityName ?? '',
          'Poultry-Rejection',
          uuid,
          into),
      control: FsaDocuments.poultryDirection,
      natureOfInspection: 'Poultry Meat Classification and Grading',
      facilityName: grading?.facilityName ?? label?.facilityName ?? '',
      // Whoever signed for the client, falling back to the name the
      // direction was made out to.
      ownerOrRepresentative: ctx.authorisedPersonName.isNotEmpty
          ? ctx.authorisedPersonName
          : direction.clientName,
      physicalAddress: grading?.facilityAddress ?? label?.facilityAddress ?? '',
      emailAddress: direction.clientEmail.isNotEmpty
          ? direction.clientEmail
          : (grading?.contactPersonEmail ?? label?.contactPersonEmail ?? ''),
      dateOfVisit: inspectedAt,
      inspectionReason: reason,
      // Poultry directions carry no number of their own on the handset —
      // unlike raw, whose reference is built at save time. Left empty
      // rather than invented: a number the office cannot trace back is
      // worse than none.
      latestReference: '',
      originalReference: '',
      subjectFields: [
        (
          label: 'Producer',
          value:
              grading?.producerTradingName ?? label?.producerTradingName ?? ''
        ),
        (label: 'Product Details', value: product),
        (
          label: 'Sample #',
          value: grading?.sampleNumber ?? label?.sampleNumber ?? ''
        ),
      ],
      deviations: [
        for (final f in findings)
          DirectionDeviation(
            product: product,
            nature: f.item.description,
            regulation: f.item.regulationReference,
          ),
      ],
      // FSA-SOP-APS-001 Annexure C: the period the deviations carry,
      // counted from the inspection date.
      correctByDate: direction.correctByDate == null
          ? ''
          : _poultryYmd(direction.correctByDate!),
      actionsAndRemark: [
        if (direction.remarks.trim().isNotEmpty) direction.remarks.trim(),
        if (direction.comments.trim().isNotEmpty) direction.comments.trim(),
        if (direction.actionTaken.trim().isNotEmpty)
          direction.actionTaken.trim(),
      ].join('\n'),
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName.isNotEmpty
          ? ctx.authorisedPersonName
          : direction.clientName,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      pleaseNote: 'Failure to rectify by the date above may result in '
          'further action under the Act.',
    );
  }

  /// The grading checklist for one poultry inspection — SOP-APS-PM-003.
  ///
  /// Poultry was the one commodity that sent the office no paperwork at
  /// all: eggs, PMP and raw each render theirs, and a poultry record
  /// arrived with an invoice and nothing to read. Produced from what the
  /// inspector actually ticked, like every other sheet.
  Future<File?> buildGradingChecklist(String uuid, {Directory? into}) async {
    final i = await (database.select(database.poultryInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (i == null) return null;
    final ticked = _tickedIds(i.compliantItemIds);
    if (ticked.isEmpty) return null;

    final ctx = await _documentContext(uuid, i.inspectorUsername);
    final items = await checklistItems();
    const titles = {
      PoultryChecklistKind.grading: 'QUALITY STANDARDS FOR CARCASSES',
      PoultryChecklistKind.portion: 'QUALITY STANDARDS FOR PORTIONS',
      // Answered on this inspection, so printed on this document. It was
      // being captured here and printed on the labelling sheet instead.
      PoultryChecklistKind.pack: 'PACKING REQUIREMENTS',
    };
    return FsaChecklistPdf.write(
      out: _poultryDocumentFile(
          i.facilityName, 'Poultry-Grading-Checklist', uuid, into),
      control: FsaDocuments.poultryGrading,
      facilityName: i.facilityName,
      leftFields: [
        (label: 'Date of Inspection:', value: _poultryYmd(i.inspectedAt)),
        (label: 'Facility Name:', value: i.facilityName),
        (label: 'Telephone:', value: i.facilityTelephone),
        (label: 'Contact Person:', value: i.contactPerson),
      ],
      rightFields: [
        (label: 'Producer/Trading Name:', value: i.producerTradingName),
        (label: 'Product Details:', value: i.productDetails),
        (label: 'Sample #:', value: i.sampleNumber),
      ],
      sections: _poultrySections(items, titles, ticked),
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      comments: i.inspectionComments,
      remarks: i.directionComments,
      photoPaths: ctx.photoPaths,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      documentTitle: 'Poultry Grading Verification Checklist',
    );
  }

  /// The labelling checklist for one poultry record — SOP-APS-PM-002.
  Future<File?> buildPoultryLabellingChecklist(String uuid,
      {Directory? into}) async {
    final i = await (database.select(database.poultryLabelInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (i == null) return null;
    final ticked = _tickedIds(i.compliantItemIds);
    if (ticked.isEmpty) return null;

    final ctx = await _documentContext(uuid, i.inspectorUsername);
    final items = await checklistItems();
    // Packing (Reg. 7) is not here. It is answered on the grading
    // inspection — the original puts it on that page — and this document
    // prints every row of every kind it lists, marking anything unticked as
    // a deviation. Listing a kind the Label/Container checklist never
    // captures put six deviations nobody had been asked about on the sheet
    // the office reads, on every record.
    const titles = {
      PoultryChecklistKind.labelInner: 'MARKING — INNER LABEL',
      PoultryChecklistKind.labelOuter: 'MARKING — OUTER PACKAGING',
      PoultryChecklistKind.container: 'CONTAINERS & OUTER CONTAINERS',
    };
    return FsaChecklistPdf.write(
      out: _poultryDocumentFile(
          i.facilityName, 'Poultry-Labelling-Checklist', uuid, into),
      control: FsaDocuments.poultryLabelling,
      facilityName: i.facilityName,
      leftFields: [
        (label: 'Date of Inspection:', value: _poultryYmd(i.inspectedAt)),
        (label: 'Facility Name:', value: i.facilityName),
        (label: 'Telephone:', value: i.facilityTelephone),
        (label: 'Contact Person:', value: i.contactPerson),
      ],
      rightFields: [
        (label: 'Producer/Trading Name:', value: i.producerTradingName),
        (label: 'Product Details:', value: i.productDetails),
        (label: 'Registration Number:', value: i.registrationNumber),
      ],
      sections: _poultrySections(items, titles, ticked),
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      comments: i.nonConformanceComments,
      remarks: '',
      photoPaths: ctx.photoPaths,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      documentTitle: 'Poultry Labelling Verification Checklist',
    );
  }

  /// The QUID determination checklist for one QUID inspection —
  /// SOP-APS-PM-001.
  ///
  /// QUID was reaching the office as figures with no sheet: it is a member
  /// kind of its own, and neither the record view nor the upload bundle had a
  /// case for it. Laid out as the Agency's own report does it — the chilling
  /// table for the declared method, the injector table where the product is
  /// injected, and the determination of QUID, each with its average.
  ///
  /// Null until carcasses have been weighed: a sheet of empty masses is not a
  /// record of a determination.
  /// The rejection a QUID determination ended in, as the sheet served on
  /// the facility. Null while the determination raised none.
  ///
  /// The rejection is captured on the weighing screen itself — the
  /// injector over its limit, the remarks, the date to correct by and the
  /// batch removed — and went up as fields on the record only, so neither
  /// Inspection Management nor the office had a document of it.
  Future<File?> buildQuidRejection(String uuid, {Directory? into}) async {
    final i = await (database.select(database.poultryQuidInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (i == null || !i.directionRequired) return null;
    final samples = await (database.select(database.poultryQuidSamples)
          ..where((t) => t.inspectionUuid.equals(uuid)))
        .get();
    final injectors = await (database.select(database.poultryQuidInjectors)
          ..where((t) => t.inspectionUuid.equals(uuid))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
    // Judged as the screen and the checklist judge it.
    final verdicts = quidVerdicts(
      injectors: [
        for (final inj in injectors)
          (position: inj.position, name: inj.name, quidPercent: inj.quidPercent),
      ],
      weighings: [
        for (final s in quidLastRound(samples, (s) => s.iteration))
          (
            assignedInjector: int.tryParse(s.assignedInjector),
            quidPercent: s.quidPercent,
          ),
      ],
      isWholeCarcass: i.isWholeCarcass,
    );
    final ctx = await _documentContext(uuid, i.inspectorUsername);
    final reasons = await inspectionReasons();
    final reason = reasons
        .where((r) => r.id == i.reasonId)
        .map((r) => r.name)
        .firstWhere((_) => true, orElse: () => '');
    final remarkTypes = await directionRemarks();
    final remarkType = remarkTypes
        .where((r) => r.id == i.directionRemarkTypeId)
        .map((r) => r.name)
        .firstWhere((_) => true, orElse: () => '');
    final product = i.productDetails.trim().isNotEmpty
        ? i.productDetails.trim()
        : (i.isWholeCarcass ? 'Whole carcasses' : 'Cuts/portions');
    final failed = [
      for (final v in verdicts)
        if (v.passes == false)
          DirectionDeviation(
            product: product,
            nature: '${v.name.isEmpty ? 'Injector ${v.position}' : v.name}: '
                'average QUID ${v.averagePercent}% exceeds the permitted '
                '${v.limitPercent.toStringAsFixed(3)}% over '
                '${v.sampleCount} carcasses.',
            regulation: 'SOP-APS-PM-001',
          ),
    ];
    return DirectionPdf.write(
      out: _poultryDocumentFile(
          i.facilityName, 'Poultry-QUID-Rejection', uuid, into),
      control: FsaDocuments.poultryDirection,
      natureOfInspection: 'Poultry QUID Verification',
      facilityName: i.facilityName,
      ownerOrRepresentative: ctx.authorisedPersonName.isNotEmpty
          ? ctx.authorisedPersonName
          : (i.managerName.trim().isNotEmpty
              ? i.managerName.trim()
              : i.contactPerson),
      physicalAddress: i.facilityAddress,
      emailAddress: i.managerEmail.trim().isNotEmpty
          ? i.managerEmail.trim()
          : (i.clientEmail.trim().isNotEmpty
              ? i.clientEmail.trim()
              : i.contactPersonEmail),
      dateOfVisit: i.inspectedAt,
      inspectionReason: reason,
      latestReference: '',
      originalReference: '',
      subjectFields: [
        (label: 'Producer', value: i.producerTradingName),
        (label: 'Product Details', value: product),
        (label: 'Chilling Method', value: i.isWaterChilled ? 'Water' : 'Air'),
        (
          label: 'Portion Type',
          value: i.isWholeCarcass ? 'Whole Carcass' : 'Cuts/Portions'
        ),
      ],
      deviations: [
        ...failed,
        // A rejection with no injector failed — the water pick-up over 7%
        // on the second round — states the weighing's own reason.
        if (failed.isEmpty && i.directionReason.trim().isNotEmpty)
          DirectionDeviation(product: product, nature: i.directionReason.trim()),
      ],
      correctByDate:
          i.correctByDate == null ? '' : _poultryYmd(i.correctByDate!),
      actionsAndRemark: [
        if (remarkType.isNotEmpty) remarkType,
        if (i.directionRemarks.trim().isNotEmpty) i.directionRemarks.trim(),
        if (i.directionAction.trim().isNotEmpty)
          'Batch No. and/or quantity removed: ${i.directionAction.trim()}',
      ].join('\n'),
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
    );
  }

  Future<File?> buildQuidChecklist(String uuid, {Directory? into}) async {
    final i = await (database.select(database.poultryQuidInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingleOrNull();
    if (i == null) return null;
    final samples = await (database.select(database.poultryQuidSamples)
          ..where((t) => t.inspectionUuid.equals(uuid)))
        .get();

    bool has(String v) => v.trim().isNotEmpty;
    final chilling = samples
        .where((s) => has(s.initialMassG) || has(s.finalMassG))
        .toList();
    final injected = samples
        .where((s) => has(s.beforeMassG) || has(s.injectorAfterMassG))
        .toList();
    // Carcasses that were weighed off the process, which is what a QUID
    // determination is made from.
    final determinedCarcasses = samples.where((s) => has(s.quidFinalMassG)).toList();
    if (chilling.isEmpty && injected.isEmpty) return null;

    final ctx = await _documentContext(uuid, i.inspectorUsername);
    final injectors = await (database.select(database.poultryQuidInjectors)
          ..where((t) => t.inspectionUuid.equals(uuid))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
    // Judged exactly as the screen judges it: one calculation, so the sheet
    // the office files cannot disagree with what the inspector was shown.
    final verdicts = quidVerdicts(
      injectors: [
        for (final inj in injectors)
          (position: inj.position, name: inj.name, quidPercent: inj.quidPercent),
      ],
      // The last round decides; a failed first round stays listed below.
      weighings: [
        for (final s in quidLastRound(samples, (s) => s.iteration))
          (
            assignedInjector: int.tryParse(s.assignedInjector),
            quidPercent: s.quidPercent,
          ),
      ],
      isWholeCarcass: i.isWholeCarcass,
    );
    final determined = quidMean([
      for (final s in quidLastRound(samples, (s) => s.iteration)) s.quidPercent
    ]);
    final reasons = await inspectionReasons();
    final reason = reasons
        .where((r) => r.id == i.reasonId)
        .map((r) => r.name)
        .firstWhere((_) => true, orElse: () => '');
    // The QUID record answers whole carcass or portions with a switch of its
    // own rather than a portion-type row.
    final portionType = i.isWholeCarcass ? 'Whole Carcass' : 'Cuts/Portions';

    return QuidChecklistPdf.write(
      out: _poultryDocumentFile(
          i.facilityName, 'Poultry-QUID-Checklist', uuid, into),
      control: FsaDocuments.poultryQuid,
      facilityName: i.facilityName,
      dateOfInspection: _poultryYmd(i.inspectedAt),
      reasonForInspection: reason,
      registrationNumber: i.companyRegNumber,
      portionType: portionType,
      allowableQuidPercent: i.dispensationQuidPercent,
      isWaterChilled: i.isWaterChilled,
      chilling: [
        for (final s in chilling)
          QuidCarcass(
            number: s.carcassNumber,
            initialMassG: s.initialMassG,
            finalMassG: s.finalMassG,
            percent: s.pickupPercent,
          ),
      ],
      averagePickupPercent: i.isWaterChilled
          ? i.averageWaterChillPickup
          : i.averageInjectorPickup,
      iterationNumber: i.iterationNumber,
      // One block per injector on the set-up list, as the paper sheet is
      // ruled: the carcasses it injected beside the carcasses its QUID was
      // determined on, each with its own average, and the finding made
      // against that injector's own setting.
      injectors: [
        for (final v in verdicts)
          QuidInjectorBlock(
            name: v.name.isEmpty ? 'Injector ${v.position}' : v.name,
            setPercent: v.setPercent,
            injection: [
              for (final s in injected
                  .where((s) => s.assignedInjector == '${v.position}'))
                QuidInjectorCarcass(
                  // The injector has its own rate column: `pickupPercent`
                  // is the chilling reading, and printing it here would put
                  // the chiller's figure under the injector's heading.
                  number: s.carcassNumber,
                  beforeMassG: s.beforeMassG,
                  afterMassG: s.injectorAfterMassG,
                  gainG: s.gainG,
                  ratePercent: s.injectorRatePercent,
                ),
            ],
            averageRatePercent: quidMean([
              for (final s in injected
                  .where((s) => s.assignedInjector == '${v.position}'))
                s.injectorRatePercent,
            ]),
            averageQuidPercent: v.averagePercent,
            passes: v.passes,
            verdict: switch (v.passes) {
              true => 'PASS — average ${v.averagePercent}% against a limit '
                  'of ${v.limitPercent.toStringAsFixed(3)}% '
                  '(${v.sampleCount} carcasses).',
              false => 'FAIL — average ${v.averagePercent}% against a limit '
                  'of ${v.limitPercent.toStringAsFixed(3)}% '
                  '(${v.sampleCount} carcasses).',
              null => v.sampleCount == 0
                  ? ''
                  : 'No finding: $quidMinimumSampleSet carcasses are needed '
                      'and ${v.sampleCount} were weighed.',
            },
            determination: [
              for (final s in determinedCarcasses
                  .where((s) => s.assignedInjector == '${v.position}'))
                QuidDeterminedCarcass(
                  sampleNumber: s.carcassNumber,
                  initialMassG: s.initialMassG,
                  finalMassG: s.quidFinalMassG,
                  setPercent: v.setPercent,
                  calculatedPercent: s.quidPercent,
                ),
            ],
          ),
        // Carcasses injected but tied to no injector on the set-up list — a
        // record from before injectors were listed, which named one
        // injector for the whole run. Printed under that name rather than
        // dropped.
        if (injected.any((s) =>
            !injectors.any((inj) => '${inj.position}' == s.assignedInjector)))
          QuidInjectorBlock(
            name: i.injectorName.trim().isEmpty ? 'Injector' : i.injectorName,
            setPercent: i.setInjectorQuidPercent,
            injection: [
              for (final s in injected.where((s) => !injectors
                  .any((inj) => '${inj.position}' == s.assignedInjector)))
                QuidInjectorCarcass(
                  number: s.carcassNumber,
                  beforeMassG: s.beforeMassG,
                  afterMassG: s.injectorAfterMassG,
                  gainG: s.gainG,
                  ratePercent: s.injectorRatePercent,
                ),
            ],
            averageRatePercent: i.averageInjectorPickup,
          ),
      ],
      averageQuidPercent: determined,
      // The consignment totals behind that average.
      quidInitialMassG: i.quidInitialMassG,
      quidAfterMassG: i.quidAfterMassG,
      quidGainMassG: i.quidGainMassG,
      verificationDate:
          i.documentDate == null ? '' : _poultryYmd(i.documentDate!),
      documentName: i.documentName,
      documentVerified: i.documentVerified ? 'YES' : 'NO',
      documentDeviationPresent: i.documentDeviationPresent ? 'YES' : 'NO',
      documentDeviationComment: i.documentDeviationComment,
      // Every record verified at the line, and whether its document was
      // photographed. Only the first used to reach the sheet.
      verificationRecords: [
        for (final r
            in QuidVerificationRecord.decode(i.verificationRecordsJson))
          QuidVerifiedRecord(
            date: r.date == null ? '' : _poultryYmd(r.date!),
            name: r.documentName,
            verified: r.verified ? 'YES' : 'NO',
            deviationPresent: r.deviationPresent ? 'YES' : 'NO',
            comment: r.deviationComment,
            photographed: r.hasPhoto ? 'YES' : 'NO',
          ),
      ],
      // The rejection the weighing ended in, which the sheet never showed.
      rejectionReason: i.directionRequired ? i.directionReason : '',
      rejectionRemarks: i.directionRequired
          ? [
              if (i.seizureDecision == 'seize')
                'Seizure under section 8 of the APS Act '
                    '(FSA-SOP-APS-001 Annexure C).',
              i.directionRemarks,
            ].where((s) => s.trim().isNotEmpty).join('\n')
          : '',
      rejectionCorrectBy: i.directionRequired && i.correctByDate != null
          ? _poultryYmd(i.correctByDate!)
          : '',
      rejectionAction: i.directionRequired ? i.directionAction : '',
      // The verdict, not just the figures: one injector over its limit is a
      // non-conformance on the consignment, however well the others ran.
      withinPermissibleLimit: switch (verdicts.map((v) => v.passes).toList()) {
        final judged when judged.every((p) => p == null) => '',
        final judged when judged.contains(false) => 'NO',
        _ => 'YES',
      },
      comments: '',
      remarks: '',
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
    );
  }

  /// Every block the checklist has, in the order the sheet prints them. A
  /// requirement the inspector did not tick is a deviation, as on every
  /// other commodity's sheet.
  List<FsaChecklistSection> _poultrySections(
    List<PoultryChecklistItemRef> items,
    Map<PoultryChecklistKind, String> titles,
    Set<int> ticked,
  ) {
    final sections = <FsaChecklistSection>[];
    for (final entry in titles.entries) {
      final rows = items.where((r) => r.kind == entry.key).toList();
      if (rows.isEmpty) continue;
      sections.add(FsaChecklistSection(
        title: entry.value,
        rows: [
          for (final r in rows)
            FsaChecklistRow(
              requirement: r.description,
              regulation: cleanRegulation(r.regulationReference),
              deviation:
                  ticked.contains(r.id) ? FsaDeviation.no : FsaDeviation.yes,
            ),
        ],
      ));
    }
    return sections;
  }

  Set<int> _tickedIds(String csv) => csv
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();

  /// The signatures, photographs and names a printed sheet carries.
  Future<_PoultryDocumentContext> _documentContext(
      String uuid, String inspectorUsername) async {
    final signatures = await (database.select(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(uuid)))
        .get();
    String pathOf(String role) => signatures
        .where((s) => s.role == role && !s.declined && s.filePath.isNotEmpty)
        .map((s) => s.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final client = signatures.where((s) => s.role == 'client').toList();
    final user = await database.findUser(inspectorUsername);
    final full =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    final photos = await (database.select(database.poultryPhotos)
          ..where((t) => t.recordUuid.equals(uuid)))
        .get();
    return _PoultryDocumentContext(
      inspectorName: full.isEmpty ? inspectorUsername : full,
      authorisedPersonName: client.isEmpty ? '' : client.first.signedName,
      inspectorSignaturePath: pathOf('inspector'),
      authorisedPersonSignaturePath: pathOf('client'),
      photoPaths: [for (final p in photos) p.filePath],
    );
  }

  File _poultryDocumentFile(
      String facility, String kind, String uuid, Directory? into) {
    final dir = into ?? Directory.systemTemp;
    final short = uuid.length < 8 ? uuid : uuid.substring(0, 8);
    final slug = facility
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return File('${dir.path}/FSA-$slug-$kind-$short.pdf');
  }

  static String _poultryYmd(DateTime d) => '${d.year}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';

  void dispose() => _client.close();
}

/// What a printed poultry sheet needs beyond the record itself.
class _PoultryDocumentContext {
  const _PoultryDocumentContext({
    required this.inspectorName,
    required this.authorisedPersonName,
    required this.inspectorSignaturePath,
    required this.authorisedPersonSignaturePath,
    required this.photoPaths,
  });

  final String inspectorName;
  final String authorisedPersonName;
  final String inspectorSignaturePath;
  final String authorisedPersonSignaturePath;
  final List<String> photoPaths;
}
