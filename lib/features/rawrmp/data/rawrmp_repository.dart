import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';
import '../../../core/documents/fsa_checklist_pdf.dart';
import '../../../core/documents/direction_pdf.dart';
import '../../../core/documents/fsa_documents.dart';
import '../domain/composition_checklist.dart';
import '../domain/rawrmp_rules.dart';
import 'composition_checklist_pdf.dart';
import '../../../core/data/regulation_reference.dart';

/// RawRMP reference data and captured work.
///
/// Same conventions as the other commodities: the bundled asset and the
/// endpoint carry an identical payload written by one writer; captured records
/// are keyed on the handset's uuid; uploads upsert.
class RawRmpRepository {
  RawRmpRepository({
    required this.database,
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final LocalDatabase database;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  static const bundledRulesAsset = 'assets/reference/rawrmp_reference.json';
  static const cursorKey = 'rawrmp.cursor';
  static const lastSyncAtKey = 'rawrmp.lastSyncAt';

  Future<String?> storedToken() => database.readSyncState('auth.accessToken');

  // ---------------------------------------------------------------- reference

  Future<int> loadBundledRulesIfEmpty() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM raw_rmp_checklist_items')
        .getSingle();
    if (row.read<int>('c') > 0) return 0;
    final raw = await rootBundle.loadString(bundledRulesAsset);
    return _writeReference(
      jsonDecode(raw) as Map<String, dynamic>,
      // The bundle is a build-time snapshot; adopting its cursor would make
      // the first delta skip everything changed since the build.
      advanceCursor: false,
    );
  }

  Future<int> syncReference({bool fromScratch = false}) async {
    final cursor = fromScratch ? null : await database.readSyncState(cursorKey);
    final uri = Uri.parse('$baseUrl/api/rawrmp/reference/').replace(
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'since': cursor,
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'RawRMP reference sync failed with status ${response.statusCode}.',
        uri,
      );
    }
    return _writeReference(jsonDecode(response.body) as Map<String, dynamic>);
  }

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
      for (final j in rows('products')) {
        await database.into(database.rawRmpProducts).insertOnConflictUpdate(
              RawRmpProductsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('producers')) {
        await database.into(database.rawRmpProducers).insertOnConflictUpdate(
              RawRmpProducersCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('storage_types')) {
        await database.into(database.rawRmpStorageTypes).insertOnConflictUpdate(
              RawRmpStorageTypesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('laboratories')) {
        await database.into(database.rawRmpLaboratories).insertOnConflictUpdate(
              RawRmpLaboratoriesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                locationDetails: Value(j['location_details'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('sample_categories')) {
        await database
            .into(database.rawRmpSampleCategories)
            .insertOnConflictUpdate(
              RawRmpSampleCategoriesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                subCategoryName: Value(j['sub_category_name'] as String? ?? ''),
                sortOrder: Value(j['sort_order'] as int? ?? 0),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('restricted_particulars')) {
        await database
            .into(database.rawRmpRestrictedParticulars)
            .insertOnConflictUpdate(
              RawRmpRestrictedParticularsCompanion.insert(
                id: Value(j['id'] as int),
                description: j['description'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('direction_remarks')) {
        await database
            .into(database.rawRmpDirectionRemarks)
            .insertOnConflictUpdate(
              RawRmpDirectionRemarksCompanion.insert(
                id: Value(j['id'] as int),
                remarkText: j['text'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(stamp(j)),
              ),
            );
        written++;
      }
      for (final j in rows('inspection_reasons')) {
        await database
            .into(database.rawRmpInspectionReasons)
            .insertOnConflictUpdate(
              RawRmpInspectionReasonsCompanion.insert(
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
            .into(database.rawRmpInspectionLocations)
            .insertOnConflictUpdate(
              RawRmpInspectionLocationsCompanion.insert(
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
      for (final j in rows('checklist_items')) {
        await database
            .into(database.rawRmpChecklistItems)
            .insertOnConflictUpdate(
              RawRmpChecklistItemsCompanion.insert(
                id: Value(j['id'] as int),
                section: j['section'] as String,
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
      for (final j in rows('label_non_conformances')) {
        await database
            .into(database.rawRmpLabelNonConformances)
            .insertOnConflictUpdate(
              RawRmpLabelNonConformancesCompanion.insert(
                id: Value(j['id'] as int),
                markedNumber: Value(j['marked_number'] as int?),
                description: j['description'] as String,
                regulationReference:
                    Value(j['regulation_reference'] as String? ?? ''),
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

  // ---------------------------------------------------------- reference reads

  Future<List<RawRmpRef>> _named(
    ResultSetImplementation<dynamic, dynamic> table,
  ) async {
    final rows = await database
        .customSelect(
          'SELECT id, name FROM ${table.aliasedName} '
          'WHERE is_active = 1 ORDER BY sort_order, id',
        )
        .get();
    return [
      for (final r in rows)
        RawRmpRef(id: r.read<int>('id'), name: r.read<String>('name')),
    ];
  }

  /// Only the active rows: the original's picker filters IsActive, which is
  /// what hides "Shelf" on this commodity.
  Future<List<RawRmpRef>> storageTypes() => _named(database.rawRmpStorageTypes);
  Future<List<RawRmpRef>> reasons() => _named(database.rawRmpInspectionReasons);
  Future<List<RawRmpRef>> sampleCategories() =>
      _named(database.rawRmpSampleCategories);

  Future<List<RawRmpRef>> products() async {
    final rows = await (database.select(database.rawRmpProducts)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.name)];
  }

  Future<List<RawRmpRef>> producers() async {
    final rows = await (database.select(database.rawRmpProducers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.name)];
  }

  Future<List<RawRmpRef>> laboratories() async {
    final rows = await (database.select(database.rawRmpLaboratories)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.name)];
  }

  Future<List<RawRmpRef>> locations() async {
    final rows = await (database.select(database.rawRmpInspectionLocations)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.name)];
  }

  /// The flat non-conformance list a direction's numbered deviations
  /// resolve against, exactly as the original resolves them.
  Future<List<RawRmpLabelNonConformance>> labelNonConformances() =>
      database.select(database.rawRmpLabelNonConformances).get();

  Future<List<RawRmpRef>> restrictedParticulars() async {
    final rows = await (database.select(database.rawRmpRestrictedParticulars)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.description)];
  }

  Future<List<RawRmpRef>> directionRemarks() async {
    final rows = await (database.select(database.rawRmpDirectionRemarks)
          ..where((t) => t.isActive.equals(true)))
        .get();
    return [for (final r in rows) RawRmpRef(id: r.id, name: r.remarkText)];
  }

  Future<List<RawRmpChecklistItemRef>> checklistItems() async {
    final rows = await (database.select(database.rawRmpChecklistItems)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return [
      for (final r in rows)
        RawRmpChecklistItemRef(
          id: r.id,
          section: switch (r.section) {
            'scale' => RawRmpSection.scale,
            'container' => RawRmpSection.container,
            'fridge' => RawRmpSection.fridge,
            'notice' => RawRmpSection.notice,
            _ => RawRmpSection.marking,
          },
          originalId: r.originalId,
          description: r.description,
          regulationReference: cleanRegulation(r.regulationReference),
          minLetteringHeight: r.minLetteringHeight,
        ),
    ];
  }

  /// The premises and client directories, shared with the egg module.
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

  Future<void> saveInspection(RawRmpInspectionsCompanion row) =>
      database.into(database.rawRmpInspections).insertOnConflictUpdate(row);

  static bool _mine(String owner, String username) =>
      owner.isEmpty || owner.toLowerCase() == username.toLowerCase();

  Future<List<RawRmpInspection>> savedInspections(String username) async {
    final rows = await (database.select(database.rawRmpInspections)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.inspectedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    return [
      for (final r in rows)
        if (_mine(r.inspectorUsername, username)) r,
    ];
  }

  /// Everything the two checklist documents share: the record, who signed
  /// it, and the particulars printed at the top of both sheets.
  Future<_RawDocumentContext?> _documentContext(String uuid) async {
    final i = await inspectionByUuid(uuid);
    if (i == null) return null;
    final reason = i.reasonId == null
        ? null
        : await (database.select(database.rawRmpInspectionReasons)
              ..where((t) => t.id.equals(i.reasonId!)))
            .getSingleOrNull();
    final location = i.locationId == null
        ? null
        : await (database.select(database.rawRmpInspectionLocations)
              ..where((t) => t.id.equals(i.locationId!)))
            .getSingleOrNull();
    final signatures = await (database.select(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(uuid)))
        .get();
    String pathOf(String role) => signatures
        .where((s) => s.role == role && !s.declined && s.filePath.isNotEmpty)
        .map((s) => s.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final client = signatures.where((s) => s.role == 'client').toList();
    final user = await database.findUser(i.inspectorUsername);
    final full =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    final photos = await (database.select(database.poultryPhotos)
          ..where((t) => t.recordUuid.equals(uuid)))
        .get();
    return _RawDocumentContext(
      inspection: i,
      facilityName:
          i.facilityName.isNotEmpty ? i.facilityName : i.newFacilityName,
      facilityType: location?.name ?? '',
      inspectorName: full.isEmpty ? i.inspectorUsername : full,
      authorisedPersonName:
          client.isNotEmpty && client.first.signedName.isNotEmpty
              ? client.first.signedName
              : i.contactPerson,
      inspectorSignaturePath: pathOf('inspector'),
      authorisedPersonSignaturePath: pathOf('client'),
      reason: reason?.name ?? '',
      photoPaths: [
        for (final photo in photos)
          if (photo.filePath.isNotEmpty) photo.filePath,
      ],
    );
  }

  File _documentFile(
      String facility, String kind, String uuid, Directory? into) {
    final dir = into ?? Directory.systemTemp;
    final short = uuid.length < 8 ? uuid : uuid.substring(0, 8);
    final slug = facility
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return File('${dir.path}/FSA-$slug-$kind-$short.pdf');
  }

  /// The direction served from [uuid], as the notice the client is handed.
  ///
  /// The direction record was being raised and sent, but nothing ever drew
  /// the sheet: the data went up and the notice existed only on the web, so
  /// the person it was served on had nothing in their hand.
  ///
  /// Null when the inspection raised no direction — there is no notice to
  /// serve for an inspection that found nothing.
  Future<File?> buildDirection(String uuid, {Directory? into}) async {
    final direction = await directionForInspection(uuid);
    if (direction == null) return null;
    final ctx = await _documentContext(uuid);
    if (ctx == null) return null;
    final i = ctx.inspection;

    final items = await checklistItems();
    final present = <RawRmpSection>{
      if (i.markingLabelsPresent) RawRmpSection.marking,
      if (i.scaleLabelsPresent) RawRmpSection.scale,
      if (i.containersPresent) RawRmpSection.container,
      if (i.displayFridgePresent) RawRmpSection.fridge,
      if (i.noticeBoardsPresent) RawRmpSection.notice,
    };
    final compliant = i.compliantItemIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    // The deviations themselves, in the order the checklist lists them, so
    // the notice cites what the record cites.
    final findings = RawRmpRules.findings(
      items: items,
      present: present,
      compliantItemIds: compliant,
    );
    final product = i.productItem.isNotEmpty ? i.productItem : i.newProductItem;

    String ymd(DateTime? d) {
      if (d == null) return '';
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year}';
    }

    return DirectionPdf.write(
      out: _documentFile(ctx.facilityName, 'Rejection', uuid, into),
      control: FsaDocuments.rawDirection,
      natureOfInspection: 'Certain Raw Processed Meat Products',
      facilityName: ctx.facilityName,
      ownerOrRepresentative: ctx.authorisedPersonName,
      physicalAddress: i.facilityAddress,
      emailAddress: i.contactPersonEmail,
      dateOfVisit: i.inspectedAt,
      inspectionReason: ctx.reason,
      // The number it was served under. An empty original reference is the
      // ordinary case: only a follow-up cites an earlier notice.
      latestReference: direction.referenceNumber,
      originalReference: '',
      subjectFields: [
        (label: 'Producer', value: i.producerName),
        (label: 'Product Details', value: product),
        (label: 'Batch Number', value: i.batchNumber),
      ],
      deviations: [
        for (final f in findings)
          DirectionDeviation(
            product: product,
            nature: f.description,
            regulation: cleanRegulation(f.regulationReference),
          ),
      ],
      correctByDate: ymd(direction.correctByDate ?? i.correctByDate),
      actionsAndRemark: [
        if (direction.remarks.trim().isNotEmpty) direction.remarks.trim(),
        if (direction.comments.trim().isNotEmpty) direction.comments.trim(),
      ].join('\n'),
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      pleaseNote: 'Failure to rectify by the date above may result in '
          'further action under the Act.',
    );
  }

  /// The Container and Labelling Verification Checklist (SOP-APS-RAW-001)
  /// for [uuid] — the marking requirements the inspector worked through,
  /// with the deviations marked.
  ///
  /// Null until the label and pack checklist has been completed: the sheet
  /// records that work, and an untouched checklist is not a record of it.
  Future<File?> buildLabellingChecklist(String uuid, {Directory? into}) async {
    final ctx = await _documentContext(uuid);
    if (ctx == null) return null;
    final i = ctx.inspection;
    // Produced from what was captured, not from a switch. Gating on the
    // "checklist complete" toggle meant an inspector who worked down the
    // list and moved on sent the office no checklist at all — which is what
    // the office was seeing: records arriving with an invoice and nothing
    // else. Any ticked requirement is a worked checklist.
    if (!i.labelPackComplete && i.compliantItemIds.trim().isEmpty) {
      return null;
    }

    final reference = await checklistItems();
    final present = <RawRmpSection>{
      if (i.markingLabelsPresent) RawRmpSection.marking,
      if (i.scaleLabelsPresent) RawRmpSection.scale,
      if (i.containersPresent) RawRmpSection.container,
      if (i.displayFridgePresent) RawRmpSection.fridge,
      if (i.noticeBoardsPresent) RawRmpSection.notice,
    };
    final compliant = i.compliantItemIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();

    const titles = {
      RawRmpSection.marking: 'MARKING REQUIREMENTS',
      RawRmpSection.container: 'CONTAINERS & OUTER CONTAINERS',
      RawRmpSection.scale: 'SCALE LABEL REQUIREMENTS',
      RawRmpSection.fridge: 'DISPLAY FRIDGE LABEL REQUIREMENTS',
      RawRmpSection.notice: 'NOTICE BOARDS, SIGNAGE, AVERTISEMENTS, ETC.',
    };
    // Every block is printed, in the sheet's own order. A block the premises
    // does not have reads N/A throughout rather than vanishing — the form is
    // a record that it was considered.
    const order = [
      RawRmpSection.marking,
      RawRmpSection.container,
      RawRmpSection.scale,
      RawRmpSection.fridge,
      RawRmpSection.notice,
    ];
    final sections = <FsaChecklistSection>[];
    for (final section in order) {
      final rows = reference.where((r) => r.section == section).toList();
      if (rows.isEmpty) continue;
      final checked = present.contains(section);
      sections.add(FsaChecklistSection(
        title: titles[section]!,
        rows: [
          for (final r in rows)
            FsaChecklistRow(
              requirement: r.description,
              regulation: cleanRegulation(r.regulationReference),
              standard:
                  r.minLetteringHeight.isEmpty ? '-' : r.minLetteringHeight,
              deviation: !checked
                  ? FsaDeviation.notApplicable
                  : (compliant.contains(r.id)
                      ? FsaDeviation.no
                      : FsaDeviation.yes),
            ),
        ],
      ));
    }
    if (sections.isEmpty) return null;
    return FsaChecklistPdf.write(
      out: _documentFile(
          ctx.facilityName, 'Labelling-Verification-Checklist', uuid, into),
      control: FsaDocuments.rawLabelling,
      facilityName: ctx.facilityName,
      leftFields: [
        (label: 'Date of Inspection:', value: _ymd(i.inspectedAt)),
        (label: 'Facility Name:', value: ctx.facilityName),
        (label: 'Reason for Inspection:', value: ctx.reason),
        (label: 'Manufactured/Packed Date', value: i.manufacturedPackedDate),
      ],
      rightFields: [
        (
          label: 'Producer',
          value:
              i.producerName.isNotEmpty ? i.producerName : i.newProducerDetails
        ),
        (
          label: 'Product Name Inspected',
          value: i.productItem.isNotEmpty ? i.productItem : i.newProductItem
        ),
        (label: 'Batch Number', value: i.batchNumber),
      ],
      sections: sections,
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      comments: i.nonConformanceComments,
      remarks: i.generalComments,
      photoPaths: ctx.photoPaths,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      documentTitle: 'Container and Labelling Verification Checklist',
    );
  }

  /// The Sampling Checklist (SOP-APS-RAW-002) for [uuid] — the laboratory
  /// sample taken off the consignment and how it travels.
  ///
  /// Null when nothing was sampled: there is no sampling sheet for a visit
  /// that took no sample.
  Future<File?> buildSamplingChecklist(String uuid, {Directory? into}) async {
    final ctx = await _documentContext(uuid);
    if (ctx == null) return null;
    final i = ctx.inspection;
    if (!i.isSampled) return null;

    final laboratory = i.laboratoryId == null
        ? null
        : await (database.select(database.rawRmpLaboratories)
              ..where((t) => t.id.equals(i.laboratoryId!)))
            .getSingleOrNull();
    // Every category the sample went for, as one line.
    final categoryIds = [
      for (final s in i.sampleCategoryIds.split(','))
        if (int.tryParse(s.trim()) != null) int.parse(s.trim()),
      if (i.sampleCategoryIds.trim().isEmpty && i.sampleCategoryId != null)
        i.sampleCategoryId!,
    ];
    final categoryRows = categoryIds.isEmpty
        ? null
        : await (database.select(database.rawRmpSampleCategories)
              ..where((t) => t.id.isIn(categoryIds)))
            .get();
    final category = categoryRows == null || categoryRows.isEmpty
        ? null
        : (name: categoryRows.map((c) => c.name).join('; '));
    final storage = i.storageTypeId == null
        ? null
        : await (database.select(database.rawRmpStorageTypes)
              ..where((t) => t.id.equals(i.storageTypeId!)))
            .getSingleOrNull();

    return FsaChecklistPdf.write(
      out: _documentFile(ctx.facilityName, 'Sampling-Checklist', uuid, into),
      control: FsaDocuments.rawSampling,
      facilityName: ctx.facilityName,
      leftFields: [
        (label: 'Date of Sampling:', value: _ymd(i.inspectedAt)),
        (label: 'Facility Name:', value: ctx.facilityName),
        (label: 'Reason for Inspection:', value: ctx.reason),
        (label: 'Manufactured/Packed Date', value: i.manufacturedPackedDate),
      ],
      rightFields: [
        (
          label: 'Producer',
          value:
              i.producerName.isNotEmpty ? i.producerName : i.newProducerDetails
        ),
        (
          label: 'Product Name Inspected',
          value: i.productItem.isNotEmpty ? i.productItem : i.newProductItem
        ),
        (label: 'Batch Number', value: i.batchNumber),
      ],
      sections: [
        FsaChecklistSection(title: 'SAMPLE DETAILS', rows: [
          FsaChecklistRow(
              requirement: 'Internal sample number',
              value: i.internalSampleNumber),
          FsaChecklistRow(
              requirement: 'Sample size taken', value: i.testSampleSize),
          FsaChecklistRow(
              requirement: 'Laboratory', value: laboratory?.name ?? ''),
          FsaChecklistRow(
              requirement: 'Laboratory testing category',
              value: category?.name ?? ''),
          FsaChecklistRow(
              requirement: 'Storage method', value: storage?.name ?? ''),
          FsaChecklistRow(
            requirement: 'Calcium content test requested (MRM only)',
            value: i.calciumTestRequired ? 'Yes' : 'No',
          ),
          FsaChecklistRow(
            requirement: 'Delivery method',
            value: i.isCouriered ? 'Hand delivered' : 'Courier',
          ),
          FsaChecklistRow(requirement: 'Waybill number', value: i.waybill),
        ]),
      ],
      inspectorName: ctx.inspectorName,
      authorisedPersonName: ctx.authorisedPersonName,
      comments: i.nonConformanceComments,
      remarks: i.generalComments,
      photoPaths: ctx.photoPaths,
      inspectorSignaturePath: ctx.inspectorSignaturePath,
      authorisedPersonSignaturePath: ctx.authorisedPersonSignaturePath,
      documentTitle: 'Sampling Checklist',
    );
  }

  /// The Compositional Checklist document (SOP-APS-RAW-003) for [uuid],
  /// built from the answers on the record, the facility and product it
  /// names, and the closing signatures held against it. Null when the
  /// checklist was never touched — the regulation does not apply to every
  /// raw product, and an untouched checklist is not a document.
  Future<File?> buildCompositionChecklist(String uuid,
      {Directory? into}) async {
    final i = await inspectionByUuid(uuid);
    if (i == null) return null;
    final answers = CompositionChecklist.decode(i.compositionChecklistJson);
    if (!CompositionChecklist.isAnswered(answers) &&
        i.compositionComments.trim().isEmpty) {
      return null;
    }
    final location = i.locationId == null
        ? null
        : await (database.select(database.rawRmpInspectionLocations)
              ..where((t) => t.id.equals(i.locationId!)))
            .getSingleOrNull();
    final signatures = await (database.select(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(uuid)))
        .get();
    String pathOf(String role) => signatures
        .where((s) => s.role == role && !s.declined)
        .map((s) => s.filePath)
        .firstWhere((p) => p.isNotEmpty, orElse: () => '');
    final client = signatures.where((s) => s.role == 'client').toList();
    final user = await database.findUser(i.inspectorUsername);
    final fullName =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    final inspectorName = fullName.isEmpty ? i.inspectorUsername : fullName;
    final productName =
        i.productItem.isNotEmpty ? i.productItem : i.newProductItem;
    final facilityName =
        i.facilityName.isNotEmpty ? i.facilityName : i.newFacilityName;
    final dir = into ?? Directory.systemTemp;
    final slug = facilityName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final short = uuid.length < 8 ? uuid : uuid.substring(0, 8);
    final out =
        File('${dir.path}/FSA-$slug-Compositional-Checklist-$short.pdf');
    return CompositionChecklistPdf.write(
      out: out,
      facilityName: facilityName,
      facilityAddress: i.facilityAddress,
      dateOfSampling: _dmy(i.inspectedAt),
      siteRepresentative: i.contactPerson,
      representativePosition: i.representativePosition,
      facilityType: location?.name ?? '',
      productName: productName,
      batchNumber: i.batchNumber,
      manufacturedPackedDate: i.manufacturedPackedDate,
      answers: answers,
      comments: i.compositionComments,
      inspectorName: inspectorName,
      authorisedPersonName:
          client.isNotEmpty && client.first.signedName.isNotEmpty
              ? client.first.signedName
              : i.contactPerson,
      inspectorSignaturePath: pathOf('inspector'),
      authorisedPersonSignaturePath: pathOf('client'),
    );
  }

  static String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The sheets date themselves the office system's way round.
  static String _ymd(DateTime d) => '${d.year}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';

  Future<RawRmpInspection?> inspectionByUuid(String uuid) =>
      (database.select(database.rawRmpInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  /// Sampled inspections whose couriered sample has no waybill yet — what the
  /// Pending Courier screen exists to finish.
  Future<List<RawRmpInspection>> pendingCourier(String username) async {
    final all = await savedInspections(username);
    return [
      for (final i in all)
        if (i.isSampled && i.isCouriered && i.waybill.trim().isEmpty) i,
    ];
  }

  /// Writes the waybill and, when the record was already sent, re-uploads so
  /// the register's copy carries it too.
  Future<void> setWaybill(String uuid, String waybill) async {
    await (database.update(database.rawRmpInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .write(
      RawRmpInspectionsCompanion(
        waybill: Value(waybill.trim()),
        // The record changed after upload, so it must go again.
        isUploaded: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveDirection(RawRmpDirectionsCompanion row) =>
      database.into(database.rawRmpDirections).insertOnConflictUpdate(row);

  /// The number a direction raised now would carry.
  ///
  /// `client / inspector id / dd/MM/yyyy / nn`, exactly as the original
  /// builds it in `SaveDirection`: nn is how many directions this inspector
  /// has already raised today, plus one, two digits. The office quotes this
  /// back, so it is generated when the direction is first raised and never
  /// again — a refreshed direction keeps the number it was served under.
  ///
  /// The inspector's id is the server's own, which is what the original
  /// means by its cloud user id; an inspector the device has never synced
  /// contributes nothing rather than a nought that means something else.
  Future<String> nextDirectionReference({
    required String inspectorUsername,
    required String clientName,
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final startOfDay = DateTime(when.year, when.month, when.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final today = await (database.select(database.rawRmpDirections)
          ..where((t) =>
              t.inspectorUsername.equals(inspectorUsername) &
              t.issuedAt.isBiggerOrEqualValue(startOfDay) &
              t.issuedAt.isSmallerThanValue(endOfDay)))
        .get();
    final user = await (database.select(database.syncedUsers)
          ..where((t) => t.username.equals(inspectorUsername))
          ..limit(1))
        .getSingleOrNull();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(when.day)}/${two(when.month)}/${when.year}';
    final parts = [
      clientName.trim(),
      if (user != null) '${user.id}',
      date,
      two(today.length + 1),
    ];
    return parts.join('/');
  }

  /// The direction raised from [inspectionUuid], if one exists — so a
  /// re-saved inspection updates its direction instead of issuing twice.
  Future<RawRmpDirection?> directionForInspection(String inspectionUuid) =>
      (database.select(database.rawRmpDirections)
            ..where((t) => t.sourceInspectionUuid.equals(inspectionUuid))
            ..limit(1))
          .getSingleOrNull();

  Future<List<RawRmpDirection>> directions(String username) async {
    final rows = await (database.select(database.rawRmpDirections)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.issuedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    return [
      for (final r in rows)
        if (_mine(r.inspectorUsername, username)) r,
    ];
  }

  // -------------------------------------------------------------------- upload

  Future<void> upload(RawRmpInspection i, {required String token}) async {
    await _post(
      'inspections',
      token: token,
      body: {
        'client_uuid': i.clientUuid,
        'status': i.status,
        'inspected_at': i.inspectedAt.toUtc().toIso8601String(),
        'location': i.locationId,
        'reason': i.reasonId,
        'facility_name': i.facilityName,
        'producer_trading_name': i.producerTradingName,
        'facility_address': i.facilityAddress,
        'facility_telephone': i.facilityTelephone,
        'contact_person': i.contactPerson,
        'contact_person_email': i.contactPersonEmail,
        'follow_up_direction_particulars': i.followUpDirectionParticulars,
        'producer_name': i.producerName,
        'new_producer_details': i.newProducerDetails,
        'product_item': i.productItem,
        'new_product_item': i.newProductItem,
        'batch_number': i.batchNumber,
        'manufactured_packed_date': i.manufacturedPackedDate,
        'storage_type': i.storageTypeId,
        'marking_labels_present': i.markingLabelsPresent,
        'scale_labels_present': i.scaleLabelsPresent,
        'containers_present': i.containersPresent,
        'display_fridge_present': i.displayFridgePresent,
        'notice_boards_present': i.noticeBoardsPresent,
        'compliant_item_ids': i.compliantItemIds,
        'restricted_particulars_present': i.restrictedParticularsPresent,
        'restricted_particulars': _ids(i.restrictedParticularIds),
        'restricted_particulars_text': i.restrictedParticularsText,
        'label_pack_complete': i.labelPackComplete,
        'is_sampled': i.isSampled,
        'laboratory': i.laboratoryId,
        'internal_sample_number': i.internalSampleNumber,
        'test_sample_size': i.testSampleSize,
        'primary_sample_size': i.primarySampleSize,
        'sample_category': i.sampleCategoryId,
        'sample_category_ids': i.sampleCategoryIds,
        'dna_species_text': i.dnaSpeciesText,
        'product_name_absent': i.productNameAbsent,
        'seizure_decision': i.seizureDecision,
        'record_kind': i.recordKind,
        'calcium_test_required': i.calciumTestRequired,
        'is_couriered': i.isCouriered,
        'lab_info_complete': i.labInfoComplete,
        'waybill': i.waybill,
        'direction_remark_type': i.directionRemarkTypeId,
        'direction_remarks': i.directionRemarks,
        'correct_by_date': i.correctByDate == null
            ? null
            : '${i.correctByDate!.year.toString().padLeft(4, '0')}-'
                '${i.correctByDate!.month.toString().padLeft(2, '0')}-'
                '${i.correctByDate!.day.toString().padLeft(2, '0')}',
        'non_conformance_comments': i.nonConformanceComments,
        'distance_travelled_km': i.distanceTravelledKm,
        'manager_name': i.managerName,
        'manager_email': i.managerEmail,
        'client_email': i.clientEmail,
        'client_email_2': i.clientEmail2,
        'no_client_signature_present': i.noClientSignaturePresent,
        'general_comments': i.generalComments,
        'latitude': i.latitude,
        'longitude': i.longitude,
      },
    );
    await (database.update(database.rawRmpInspections)
          ..where((t) => t.clientUuid.equals(i.clientUuid)))
        .write(const RawRmpInspectionsCompanion(isUploaded: Value(true)));
  }

  Future<void> uploadDirection(
    RawRmpDirection d, {
    required String token,
  }) async {
    await _post(
      'directions',
      token: token,
      body: {
        'client_uuid': d.clientUuid,
        'status': d.status,
        'issued_at': d.issuedAt.toUtc().toIso8601String(),
        // The number the direction was served under, and the deadline on it.
        // The office quotes the number back and chases the date, and neither
        // was travelling.
        'reference_number': d.referenceNumber,
        'correct_by_date': d.correctByDate == null
            ? null
            : '${d.correctByDate!.year.toString().padLeft(4, '0')}-'
                '${d.correctByDate!.month.toString().padLeft(2, '0')}-'
                '${d.correctByDate!.day.toString().padLeft(2, '0')}',
        'facility_name': d.facilityName,
        'client_name': d.clientName,
        'client_email': d.clientEmail,
        'remark_type': d.remarkTypeId,
        'remarks': d.remarks,
        'comments': d.comments,
        'action_taken': d.actionTaken,
        'non_conformance_ids': d.nonConformanceIds,
        'source_inspection_uuid': d.sourceInspectionUuid,
        'new_facility_name': d.newFacilityName,
        'producer_name': d.producerName,
        'new_producer_name': d.newProducerName,
        'batch_number': d.batchNumber,
        'manufactured_packed_date': d.manufacturedPackedDate,
        'primary_sample_size': d.primarySampleSize,
        'restricted_particular_ids': d.restrictedParticularIds,
        'latitude': d.latitude,
        'longitude': d.longitude,
      },
    );
    await (database.update(database.rawRmpDirections)
          ..where((t) => t.clientUuid.equals(d.clientUuid)))
        .write(const RawRmpDirectionsCompanion(isUploaded: Value(true)));
  }

  Future<void> _post(
    String collection, {
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl/api/rawrmp/$collection/');
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
      throw http.ClientException(
        'Upload failed with status ${response.statusCode}: ${response.body}',
        uri,
      );
    }
  }

  static List<int> _ids(String csv) => [
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ];

  /// Registers a producer met in the field and hands back its directory row.
  ///
  /// As with egg suppliers: the server allocates the id, never this device —
  /// a made-up id is what produced "object does not exist" on every later
  /// upload. Offline, the row is kept locally under a negative id so capture
  /// can carry on; the next sync brings the server's copy.
  Future<RawRmpRef> addProducer(String name) => _register(
      'producers',
      name,
      database.rawRmpProducers,
      (id, cleaned) => RawRmpProducersCompanion(
            id: Value(id),
            name: Value(cleaned),
            isActive: const Value(true),
          ));

  /// Registers a product item met in the field. Same rules as [addProducer].
  Future<RawRmpRef> addProduct(String name) => _register(
      'products',
      name,
      database.rawRmpProducts,
      (id, cleaned) => RawRmpProductsCompanion(
            id: Value(id),
            name: Value(cleaned),
            isActive: const Value(true),
          ));

  Future<RawRmpRef> _register<T extends Table, D>(
    String collection,
    String name,
    TableInfo<T, D> table,
    Insertable<D> Function(int id, String name) companion,
  ) async {
    final cleaned = name.trim();
    int id = await _nextLocalId(table);
    final token = await storedToken();
    if (token != null) {
      try {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/api/rawrmp/$collection/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'name': cleaned}),
            )
            .timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          id = (jsonDecode(response.body) as Map<String, dynamic>)['id'] as int;
        }
      } on Object {
        // Offline or refused: keep the local row so capture can continue.
      }
    }
    await database.into(table).insertOnConflictUpdate(companion(id, cleaned));
    return RawRmpRef(id: id, name: cleaned);
  }

  /// An id that cannot collide with the server's: negative and descending,
  /// so a row registered with no signal is obviously local.
  Future<int> _nextLocalId<T extends Table, D>(TableInfo<T, D> table) async {
    final row = await database
        .customSelect('SELECT MIN(id) AS lowest FROM ${table.actualTableName}')
        .getSingle();
    final lowest = row.data['lowest'] as int? ?? 0;
    return lowest < 0 ? lowest - 1 : -1;
  }

  void dispose() => _client.close();
}

/// What both raw checklist documents need about a record and its signing.
class _RawDocumentContext {
  const _RawDocumentContext({
    required this.inspection,
    required this.facilityName,
    required this.facilityType,
    required this.inspectorName,
    required this.authorisedPersonName,
    required this.inspectorSignaturePath,
    required this.authorisedPersonSignaturePath,
    required this.reason,
    required this.photoPaths,
  });

  final RawRmpInspection inspection;
  final String facilityName;
  final String facilityType;
  final String inspectorName;
  final String authorisedPersonName;
  final String inspectorSignaturePath;
  final String authorisedPersonSignaturePath;
  final String reason;
  final List<String> photoPaths;
}
