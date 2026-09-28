import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/photo_storage.dart';
import 'occurrence_document_pdf.dart';

import '../../../core/data/local_database.dart';
import '../../eggs/data/eggs_repository.dart';
import '../../eggs/domain/egg_rules.dart';
import '../../pmp/data/pmp_repository.dart';
import '../../poultry/data/poultry_repository.dart';
import '../../poultry/domain/quid_determination.dart';
import '../../poultry/domain/quid_flow.dart';
import '../../rawrmp/data/rawrmp_repository.dart';
import '../../seizures/data/seizure_repository.dart';
import '../../rawrmp/domain/raw_record_kind.dart';
import '../domain/inspection_outcome.dart';
import '../domain/visit_prefill.dart';
import '../../../core/data/regulation_reference.dart';

/// One inspection belonging to a visit, however it was captured.
///
/// Members inside a visit finish as `ready` rather than `completed`: the
/// capture is done but nothing is submitted. The one sign-off at the end
/// flips every ready member to `completed`, which is what the sync service
/// uploads — "I am done, now submit", once, for the whole group.
class VisitMember {
  const VisitMember({
    required this.uuid,
    required this.kind,
    required this.label,
    required this.completed,
    this.status = '',
    this.isUploaded = false,
    this.inspectedAt,
  });

  final String uuid;

  /// 'egg' | 'poultry' | 'poultry_label'
  final String kind;

  /// What the list shows for this member.
  final String label;

  final bool completed;

  /// 'draft' | 'ready' | 'completed' — the raw stored state, for screens
  /// that need more than the completed flag.
  final String status;
  final bool isUploaded;
  final DateTime? inspectedAt;
}

class _Evidence {
  const _Evidence({required this.complete, required this.paths});

  final bool complete;
  final List<String> paths;
}

/// Owns the store-visit records and the closing-signature fan-out.
///
/// The fan-out writes directly into the egg and poultry signature tables —
/// the same rows the standalone forms write — so the upload paths need no
/// changes and cannot tell a visit-signed record from a form-signed one.
class VisitRepository {
  static const _uploadedAtPrefix = 'visits.uploadedAt.';
  static const localRetention = Duration(days: 3);

  VisitRepository(this.database, {this.baseUrl = '', http.Client? client})
      : _client = client ?? http.Client();

  final LocalDatabase database;

  /// Where the office's server lives. Empty in tests, which never upload.
  final String baseUrl;
  final http.Client _client;

  /// Signed-off groups the server has not been told about yet.
  ///
  /// The members upload through their own commodity endpoints; this is the
  /// group itself, which is what the office's record is made from — so a
  /// visit whose members are all up but whose group never arrived would
  /// leave the office with four unrelated records and no job.
  Future<List<StoreVisit>> pendingUploads() => (database
          .select(database.storeVisits)
        ..where((t) => t.completedAt.isNotNull() & t.isUploaded.equals(false)))
      .get();

  /// Approves a visit that is already on the server (Ethan, 2026-09-24).
  ///
  /// Recorded on the device first, so an approval given with no signal is
  /// not lost; [sendApproval] tells the server, and Server Sync sends any
  /// that are still waiting.
  Future<void> approve(String visitUuid, {DateTime? at}) =>
      (database.update(database.storeVisits)
            ..where((t) => t.uuid.equals(visitUuid)))
          .write(StoreVisitsCompanion(
        approvedAt: Value(at ?? DateTime.now()),
        approvalSent: const Value(false),
      ));

  /// Takes an approval back. Sent the same way as giving one.
  Future<void> unapprove(String visitUuid) =>
      (database.update(database.storeVisits)
            ..where((t) => t.uuid.equals(visitUuid)))
          .write(const StoreVisitsCompanion(
        approvedAt: Value(null),
        approvalSent: Value(false),
      ));

  /// Approval answers — given or taken back — the server does not hold yet.
  Future<List<StoreVisit>> pendingApprovals() => (database
          .select(database.storeVisits)
        ..where(
            (t) => t.approvalSent.equals(false) & t.isUploaded.equals(true)))
      .get();

  /// Tells the server the visit's current answer. True once it has it.
  Future<bool> sendApproval(StoreVisit visit, {required String token}) async {
    if (baseUrl.isEmpty) return false;
    final response = await _client.post(
      Uri.parse('$baseUrl/api/visits/${visit.uuid}/approve/'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'approved': visit.approvedAt != null,
        'approved_at': visit.approvedAt?.toUtc().toIso8601String(),
      }),
    );
    if (response.statusCode != 200) return false;
    await (database.update(database.storeVisits)
          ..where((t) => t.uuid.equals(visit.uuid)))
        .write(const StoreVisitsCompanion(approvalSent: Value(true)));
    return true;
  }

  /// Sends every approval still waiting; returns how many went.
  Future<int> sendPendingApprovals({required String token}) async {
    var sent = 0;
    for (final visit in await pendingApprovals()) {
      try {
        if (await sendApproval(visit, token: token)) sent++;
      } on Object {
        // Stays waiting for the next pass.
      }
    }
    return sent;
  }

  /// Marks a signed-off visit as changed, so the office is told again.
  ///
  /// An inspector who corrects a record in Inspection Management has
  /// changed what the office holds. Clearing the uploaded flag is what puts
  /// the visit back in front of Server Sync; the server updates the row it
  /// already has, keyed on this visit's own uuid, and the bridge corrects
  /// the APS group rather than filing a second one.
  Future<void> markChanged(String visitUuid) =>
      (database.update(database.storeVisits)
            ..where((t) => t.uuid.equals(visitUuid)))
          .write(const StoreVisitsCompanion(isUploaded: Value(false)));

  /// Puts a corrected record back into the state the group is in.
  ///
  /// The capture forms leave a finished member as `ready`, because inside a
  /// grouped inspection the one sign-off at the end is what submits it. A
  /// record corrected after that sign-off has already been submitted, so
  /// left as `ready` it reappears as "awaiting sign-off" and invites an
  /// inspector to sign a group that is already with the office.
  Future<void> restoreSubmitted(VisitMember member) async {
    const submitted = 'completed';
    switch (member.kind) {
      case 'egg':
        await (database.update(database.eggInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const EggInspectionsCompanion(status: Value(submitted)));
      case 'poultry':
        await (database.update(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const PoultryInspectionsCompanion(status: Value(submitted)));
      case 'poultry_label':
        await (database.update(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const PoultryLabelInspectionsCompanion(
                status: Value(submitted)));
      case 'pmp':
        await (database.update(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const PmpInspectionsCompanion(status: Value(submitted)));
      case 'rawrmp':
        await (database.update(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const RawRmpInspectionsCompanion(status: Value(submitted)));
      case 'quid':
        await (database.update(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .write(const PoultryQuidInspectionsCompanion(
                status: Value(submitted)));
    }
  }

  /// Sends one signed-off group, with its Request for Invoice.
  ///
  /// Multipart rather than JSON: the RFI travels with the group so the
  /// office record and its billing document arrive together, rather than
  /// the document being a second errand that can be forgotten.
  /// [kilometres] and [hours] come from the visit's Request for Invoice,
  /// which is where the inspector actually enters them. The office bills
  /// off those two numbers, so a record that arrives without them reads as
  /// a visit that cost nothing to make.
  Future<bool> upload(
    StoreVisit visit, {
    required String token,
    File? invoicePdf,
    double kilometres = 0,
    double hours = 0,
  }) async {
    if (baseUrl.isEmpty) return false;
    final members = await this.members(visit.uuid);
    // Nullable values: `is_compliant` is unset when the handset
    // cannot judge the commodity, which is not the same as a fail.
    final lines = <Map<String, Object?>>[];
    for (final member in members) {
      lines.add({
        'kind': member.kind,
        'client_uuid': member.uuid,
        'product_name': await _productName(member),
        'product_class': await _productClass(member),
        'is_sample_taken': await _wasSampled(member),
        // What the sample was sent for. APS prints the laboratory and the
        // tests beside the product, and until now the office had to open
        // the record to find out — the handset already knows.
        ...await _labDetails(member),
        // What was found: the deviations themselves, whether the product
        // met the regulation, whether a direction was served, and where.
        ...await _findings(member),
      });
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/visits/'),
    )..headers['Authorization'] = 'Bearer $token';

    request.fields.addAll({
      'visit_uuid': visit.uuid,
      'facility_name': visit.facilityName,
      'facility_address': visit.facilityAddress,
      'facility_phone': visit.facilityPhone,
      'contact_person': visit.contactPerson,
      'producer_name': visit.producerName,
      'contact_email': visit.contactEmail,
      'manager_name': visit.managerName,
      'manager_email': visit.managerEmail,
      'additional_email_1': visit.additionalEmail1,
      'additional_email_2': visit.additionalEmail2,
      'additional_email_3': visit.additionalEmail3,
      'inspector_name': visit.inspectorUsername,
      'is_occurrence_report': visit.isOccurrenceReport ? 'true' : 'false',
      'facility_type': visit.facilityType,
      'occurrence_time_of_visit': visit.occurrenceTimeOfVisit,
      'occurrence_registration_code': visit.occurrenceRegistrationCode,
      'occurrence_description': visit.occurrenceDescription,
      'kilometres': '$kilometres',
      'hours': '$hours',
      'started_at': visit.startedAt.toUtc().toIso8601String(),
      if (visit.completedAt != null)
        'completed_at': visit.completedAt!.toUtc().toIso8601String(),
      // A nested list in a multipart body travels as one JSON string.
      'members': jsonEncode(lines),
      'follow_up': (await _isFollowUp(visit.uuid)).toString(),
    });

    if (invoicePdf != null && invoicePdf.existsSync()) {
      request.files.add(await http.MultipartFile.fromPath(
        'rfi',
        invoicePdf.path,
        filename: 'request-for-invoice.pdf',
      ));
    }

    // The checklists the inspector filled in, rendered here and sent with
    // the group. The office reads them off the record; leaving them on the
    // handset means the only copy of the evidence is on a device in a van.
    final documents = <Map<String, String>>[];
    for (final member in members) {
      for (final document in await _documentsFor(member)) {
        request.files.add(await http.MultipartFile.fromPath(
          'documents',
          document.file.path,
          filename: document.filename,
        ));
        documents.add({
          'commodity': member.kind,
          'document_type': document.type,
          'filename': document.filename,
        });
      }
    }
    if (documents.isNotEmpty) {
      // Same order as the files themselves, which is how they are paired up.
      request.fields['document_meta'] = jsonEncode(documents);
    }
    if (visit.isOccurrenceReport) {
      // The written report and its photographs go up as one PDF — the
      // Occurrence Document APS attaches to the record and emails.
      final document = await buildOccurrenceDocument(visit);
      if (document != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'occurrence_document',
          document.path,
          filename: 'occurrence-report.pdf',
        ));
      }
    }

    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(minutes: 5)),
    );
    if (response.statusCode != 200 && response.statusCode != 201) return false;
    await (database.update(database.storeVisits)
          ..where((t) => t.uuid.equals(visit.uuid)))
        .write(const StoreVisitsCompanion(isUploaded: Value(true)));
    // `completedAt` is when fieldwork ended, not when the server confirmed
    // receipt. Retention must start only after that confirmation.
    await database.writeSyncState(
      '$_uploadedAtPrefix${visit.uuid}',
      DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  /// What was inspected, for the product line the office reads.
  /// The photographs taken for the visit's occurrence report, oldest first.
  Future<List<VisitOccurrencePhoto>> occurrencePhotos(String visitUuid) =>
      (database.select(database.visitOccurrencePhotos)
            ..where((t) => t.visitUuid.equals(visitUuid))
            ..orderBy([(t) => OrderingTerm(expression: t.capturedAt)]))
          .get();

  Future<int> addOccurrencePhoto(String visitUuid, String filePath) =>
      database.into(database.visitOccurrencePhotos).insert(
            VisitOccurrencePhotosCompanion.insert(
              visitUuid: visitUuid,
              filePath: filePath,
              capturedAt: DateTime.now(),
            ),
          );

  Future<void> removeOccurrencePhoto(int id) =>
      (database.delete(database.visitOccurrencePhotos)
            ..where((t) => t.id.equals(id)))
          .go();

  /// Binds the written report and its photographs into the Occurrence
  /// Document. Null when there is nothing to bind.
  Future<File?> buildOccurrenceDocument(StoreVisit visit) async {
    final photos = await occurrencePhotos(visit.uuid);
    if (visit.occurrenceDescription.trim().isEmpty && photos.isEmpty) {
      return null;
    }
    // Written beside the photographs it binds (the app's own photo folder),
    // or in the system temp folder when there is only the written report.
    final folder = photos.isNotEmpty
        ? File(photos.first.filePath).parent
        : Directory.systemTemp;
    final out = File('${folder.path}/visit_${visit.uuid}_occurrence.pdf');
    final when = visit.completedAt ?? visit.startedAt;
    return OccurrenceDocumentPdf.write(
      out: out,
      facilityName: visit.facilityName,
      facilityAddress: visit.facilityAddress,
      date: '${when.day.toString().padLeft(2, '0')}/'
          '${when.month.toString().padLeft(2, '0')}/${when.year}',
      timeOfVisit: visit.occurrenceTimeOfVisit,
      registrationCode: visit.occurrenceRegistrationCode,
      inspectorName: await _inspectorFullName(visit.inspectorUsername),
      description: visit.occurrenceDescription,
      photoPaths: photos.map((p) => p.filePath).toList(),
      ownerManagerDetails: visit.contactPerson,
      telephone: visit.facilityPhone,
      email: visit.contactEmail,
      managerName: visit.managerName.isNotEmpty
          ? visit.managerName
          : visit.contactPerson,
      inspectorSignaturePath: visit.inspectorSignaturePath,
      managerSignaturePath: visit.managerSignaturePath,
    );
  }

  /// The inspector's full name as the server knows them, for the document;
  /// their login name when the roster has not been synced yet.
  Future<String> _inspectorFullName(String username) async {
    final user = await database.findUser(username);
    if (user == null) return username;
    final full = '${user.firstName} ${user.lastName}'.trim();
    return full.isEmpty ? username : full;
  }

  Future<String> _productName(VisitMember member) async {
    switch (member.kind) {
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return 'Certain Raw Processed Meat Products';
        final name =
            row.productItem.isNotEmpty ? row.productItem : row.newProductItem;
        return name.isEmpty ? 'Certain Raw Processed Meat Products' : name;
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return 'Processed Meat Products';
        final name =
            row.productItem.isNotEmpty ? row.productItem : row.newProductItem;
        return name.isEmpty ? 'Processed Meat Products' : name;
      case 'egg':
        return 'Eggs';
      case 'poultry_label':
        return 'Label/Container';
      case 'quid':
        return 'Poultry QUID';
      default:
        return 'Poultry Meat';
    }
  }

  /// APS prints a class beside each product and the handset has no such
  /// field, so it sends a short sentence describing what was inspected.
  Future<String> _productClass(VisitMember member) async {
    switch (member.kind) {
      case 'egg':
        final row = await (database.select(database.eggInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return 'Eggs sampled and graded on site.';
        final size = await _nameOf('egg_sizes', row.declaredSizeId);
        final grade = await _nameOf('egg_grades', row.declaredGradeId);
        final sold = [grade, size].where((p) => p.isNotEmpty).join(' ');
        return sold.isEmpty
            ? 'Eggs sampled and graded on site.'
            : 'Sold as $sold; sampled and graded on site.';
      case 'poultry':
        final row = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return 'Poultry graded and classified on site.';
        final designation = await _nameOf(
            'poultry_designation_classes', row.designationClassId);
        final grade = await _nameOf('poultry_grades', row.gradeId);
        final parts =
            [designation, grade].where((p) => p.isNotEmpty).join(', ');
        return parts.isEmpty
            ? 'Poultry graded and classified on site.'
            : 'Graded and classified as $parts.';
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        final storage = row == null
            ? ''
            : await _nameOf('raw_rmp_storage_types', row.storageTypeId);
        return storage.isEmpty
            ? 'Marking and labelling checked on site.'
            : 'Held $storage; marking and labelling checked on site.';
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        final storage = row == null
            ? ''
            : await _nameOf('pmp_storage_types', row.storageTypeId);
        return storage.isEmpty
            ? 'Marking and labelling checked on site.'
            : 'Held $storage; marking and labelling checked on site.';
      case 'quid':
        // What was weighed and how it ended. It used to fall to the label
        // wording below, so the office read a QUID line as a label check.
        final row = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return 'QUID verified on site.';
        final injectors = await (database.select(database.poultryQuidInjectors)
              ..where((t) => t.inspectionUuid.equals(member.uuid)))
            .get();
        final method = row.isWaterChilled ? 'water-chilled' : 'air-chilled';
        final portion = row.isWholeCarcass ? 'whole carcasses' : 'cuts';
        final count = injectors.length;
        final ended = row.directionRequired
            ? 'rejection issued'
            : row.quidDeterminationComplete
                ? 'within the permitted limit'
                : 'determination not completed';
        return 'QUID verified on $method $portion over $count '
            '${count == 1 ? 'injector' : 'injectors'}; $ended.';
      default:
        return 'Label and container requirements checked on site.';
    }
  }

  /// The deviations recorded against a member, and what they amount to.
  ///
  /// Each commodity keeps its findings its own way — the meat forms tick
  /// the requirements that were met, the egg form records the ones that
  /// failed — so each is read on its own terms and reported the same way.
  /// A commodity whose findings the handset cannot total leaves
  /// `is_compliant` unset rather than claiming a pass.
  Future<Map<String, Object?>> _findings(VisitMember member) async {
    Set<int> ids(String csv) => csv
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();

    var outcome = InspectionOutcome.none;
    double? latitude;
    double? longitude;

    switch (member.kind) {
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return const {};
        latitude = row.latitude;
        longitude = row.longitude;
        final items = await (database.select(database.rawRmpChecklistItems)
              ..where((t) => t.isActive.equals(true)))
            .get();
        outcome = InspectionFindings.fromChecklist(
          requirements: [
            for (final i in items)
              (
                id: i.id,
                section: i.section,
                description: i.description,
                regulation: cleanRegulation(i.regulationReference)
              ),
          ],
          sectionsPresent: {
            if (row.markingLabelsPresent) 'marking',
            if (row.scaleLabelsPresent) 'scale',
            if (row.containersPresent) 'container',
            if (row.displayFridgePresent) 'fridge',
            if (row.noticeBoardsPresent) 'notice',
          },
          compliantIds: ids(row.compliantItemIds),
          checklistWorked:
              row.labelPackComplete || ids(row.compliantItemIds).isNotEmpty,
          extraFindings: [row.nonConformanceComments],
        );
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return const {};
        final items = await (database.select(database.pmpChecklistItems)
              ..where((t) => t.isActive.equals(true)))
            .get();
        outcome = InspectionFindings.fromChecklist(
          requirements: [
            for (final i in items)
              (
                id: i.id,
                section: i.section,
                description: i.description,
                regulation: cleanRegulation(i.regulationReference)
              ),
          ],
          sectionsPresent: {
            if (row.markingLabelsPresent) 'marking',
            if (row.scaleLabelsPresent) 'scale',
            if (row.containersPresent) 'container',
            if (row.displayFridgePresent) 'fridge',
            if (row.noticeBoardsPresent) 'notice',
          },
          compliantIds: ids(row.compliantItemIds),
          checklistWorked:
              row.labelPackComplete || ids(row.compliantItemIds).isNotEmpty,
          extraFindings: [row.nonConformanceComments],
        );
      case 'egg':
        final row = await (database.select(database.eggInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return const {};
        latitude = row.latitude;
        longitude = row.longitude;
        // The egg form records the requirements that FAILED, so every
        // applicable row counts as met except those.
        final failed = ids(row.failedRequirementIds);
        final requirements = await (database.select(database.eggRequirements)
              ..where((t) => t.isActive.equals(true)))
            .get();
        // The weighed eggs carry deviations of their own — judged the way
        // the handset judges them: a count across the sample against the
        // band the Agency allows for the declared size and grade. Every
        // ticked deviation used to arrive here as a finding, so a record
        // the handset had passed (two cracked shells where four are
        // allowed) reached the office marked non-compliant.
        final samples = await (database.select(database.eggSamples)
              ..where((t) => t.inspectionUuid.equals(member.uuid)))
            .get();
        final counts = <int, int>{};
        for (final sample in samples) {
          for (final id in ids(sample.deviationIds)) {
            counts[id] = (counts[id] ?? 0) + 1;
          }
        }
        final extra = <String>[];
        if (counts.isNotEmpty) {
          final tolerances = [
            for (final t
                in await database.select(database.eggDeviationTolerances).get())
              DeviationTolerance(
                deviationId: t.deviationId,
                sizeId: t.sizeId,
                gradeId: t.gradeId,
                minimum: t.minimum,
                maximum: t.maximum,
              ),
          ];
          final beyondBand = [
            for (final entry in counts.entries)
              if (!EggRules.isDeviationPermissible(
                deviationId: entry.key,
                count: entry.value,
                sizeId: row.declaredSizeId ?? -1,
                gradeId: row.declaredGradeId ?? -1,
                tolerances: tolerances,
              ))
                entry.key,
          ];
          if (beyondBand.isNotEmpty) {
            final deviations = await (database.select(database.eggDeviations)
                  ..where((t) => t.id.isIn(beyondBand)))
                .get();
            extra.addAll([
              for (final d in deviations)
                '${d.description} (${counts[d.id]} of ${samples.length} eggs)',
            ]);
          }
        }
        outcome = InspectionFindings.fromChecklist(
          requirements: [
            for (final r in requirements)
              (
                id: r.id,
                section: r.kind,
                description: r.description,
                regulation: cleanRegulation(r.regulation)
              ),
          ],
          sectionsPresent: {
            'label_pack',
            'packing',
            if (row.outerLabellingAvailable) 'label_outer',
          },
          compliantIds: {
            for (final r in requirements)
              if (!failed.contains(r.id)) r.id,
          },
          checklistWorked: samples.isNotEmpty || failed.isNotEmpty,
          extraFindings: extra,
        );
      case 'poultry':
      case 'poultry_label':
        // Two records can stand behind one member: the grading inspection
        // and the label one. Only the lists a record actually worked are
        // judged — a grading inspection is not failed by label rows nobody
        // looked at.
        final grading = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        final label = await (database.select(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (grading == null && label == null) return const {};
        final compliantIds = <int>{
          if (grading != null) ...ids(grading.compliantItemIds),
          if (label != null) ...ids(label.compliantItemIds),
        };
        final items = await (database.select(database.poultryChecklistItems)
              ..where((t) => t.isActive.equals(true)))
            .get();
        outcome = InspectionFindings.fromChecklist(
          requirements: [
            for (final i in items)
              (
                id: i.id,
                section: i.kind,
                description: i.description,
                regulation: cleanRegulation(i.regulationReference)
              ),
          ],
          sectionsPresent: {
            if (grading != null) ...['grading', 'portion'],
            if (label != null) ...[
              'label_inner',
              'label_outer',
              'container',
              'pack'
            ],
          },
          compliantIds: compliantIds,
          checklistWorked: compliantIds.isNotEmpty,
        );
      case 'quid':
        // QUID is measured, not ticked, so it cannot go through the
        // checklist rule — and falling to the default sent the office a QUID
        // member with no compliance line at all, not even the direction it
        // had raised. The finding is the one the sheet states: an injector
        // running over what it is set to.
        final row = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null) return const {};
        latitude = row.latitude;
        longitude = row.longitude;
        final injectors = await (database.select(database.poultryQuidInjectors)
              ..where((t) => t.inspectionUuid.equals(member.uuid)))
            .get();
        final samples = await (database.select(database.poultryQuidSamples)
              ..where((t) => t.inspectionUuid.equals(member.uuid)))
            .get();
        final verdicts = quidVerdicts(
          injectors: [
            for (final i in injectors)
              (position: i.position, name: i.name, quidPercent: i.quidPercent),
          ],
          // The last round is the one that decides.
          weighings: [
            for (final sample in quidLastRound(samples, (s) => s.iteration))
              (
                assignedInjector: int.tryParse(sample.assignedInjector),
                quidPercent: sample.quidPercent,
              ),
          ],
          isWholeCarcass: row.isWholeCarcass,
        );
        final judged = [
          for (final v in verdicts)
            if (v.passes != null) v,
        ];
        final failed = [
          for (final v in judged)
            if (v.passes == false)
              '${v.name.isEmpty ? 'Injector ${v.position}' : v.name}: '
                  'average QUID ${v.averagePercent}% exceeds the permitted '
                  '${v.limitPercent.toStringAsFixed(3)}% over '
                  '${v.sampleCount} carcasses.',
        ];
        final comment = row.generalComments.trim();
        // A rejection the weighing ended in — the water pick-up over 7% on
        // the second round — is a finding even with no injector judged.
        final rejected = row.directionRequired;
        final reason = row.directionReason.trim();
        outcome = InspectionOutcome(
          findings: [
            ...failed,
            if (rejected && failed.isEmpty && reason.isNotEmpty) reason,
            if (comment.isNotEmpty) comment,
          ],
          // Null while no injector has enough carcasses to be judged on:
          // a determination nobody could complete is not a pass.
          isCompliant: rejected
              ? false
              : judged.isEmpty
                  ? null
                  : failed.isEmpty,
        );
      default:
        return const {};
    }

    final direction = await _raisedDirectionFor(member);
    if (outcome.findings.isEmpty && outcome.isCompliant == null && !direction) {
      return const {};
    }
    return {
      'is_compliant': outcome.isCompliant,
      'direction_raised': direction,
      'findings': outcome.findingsText,
      'latitude': latitude?.toStringAsFixed(6) ?? '',
      'longitude': longitude?.toStringAsFixed(6) ?? '',
    };
  }

  /// Whether a direction was served off the back of this inspection.
  Future<bool> _raisedDirectionFor(VisitMember member) async {
    switch (member.kind) {
      case 'rawrmp':
        return await (database.select(database.rawRmpDirections)
                  ..where((t) => t.sourceInspectionUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
      case 'pmp':
        return await (database.select(database.pmpDirections)
                  ..where((t) => t.sourceInspectionUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
      case 'egg':
        return await (database.select(database.eggDirections)
                  ..where((t) => t.inspectionUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
      case 'quid':
        // The rejection lives on the determination itself rather than in
        // a directions table: it is raised when the weighing ends in one.
        final row = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.directionRequired ?? false;
      default:
        return await (database.select(database.poultryDirections)
                  ..where((t) => t.clientUuid.equals(member.uuid)))
                .getSingleOrNull() !=
            null;
    }
  }

  /// The laboratory a sample went to, and what it was sent for.
  ///
  /// APS carries a laboratory and four test flags against each product.
  /// Only the two meat commodities take samples, and only they record a
  /// laboratory; the rest send nothing rather than guessing.
  /// Whether this visit follows up an earlier direction.
  ///
  /// The inspector says so per inspection, by choosing the "Follow Up"
  /// reason or naming the direction being followed up; APS records it once
  /// against the group.
  Future<bool> _isFollowUp(String visitUuid) async {
    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in raw) {
      if (row.followUpDirectionParticulars.trim().isNotEmpty) return true;
      final reason = await _nameOf('raw_rmp_inspection_reasons', row.reasonId);
      if (reason.toLowerCase().contains('follow')) return true;
    }
    final pmp = await (database.select(database.pmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in pmp) {
      if (row.followUpDirectionParticulars.trim().isNotEmpty) return true;
      final reason = await _nameOf('pmp_inspection_reasons', row.reasonId);
      if (reason.toLowerCase().contains('follow')) return true;
    }
    final eggs = await (database.select(database.eggInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in eggs) {
      final reason = await _nameOf('egg_inspection_reasons', row.reasonId);
      if (reason.toLowerCase().contains('follow')) return true;
    }
    return false;
  }

  /// The compliance documents for one member, rendered ready to send.
  ///
  /// The document type is APS's own vocabulary, not the app's: `compliance`
  /// for a checklist, `lab_form` for the sheet that travels with a sample,
  /// `composition` for the compositional analysis. That is what the office
  /// filters and files on.
  Future<List<({String type, String filename, File file})>> _documentsFor(
      VisitMember member) async {
    final folder = Directory.systemTemp;
    final wanted = <({String type, Future<File?> Function() build})>[];

    switch (member.kind) {
      case 'rawrmp':
        final repository = RawRmpRepository(database: database, baseUrl: '');
        wanted.addAll([
          (
            type: 'compliance',
            build: () =>
                repository.buildLabellingChecklist(member.uuid, into: folder)
          ),
          (
            type: 'lab_form',
            build: () =>
                repository.buildSamplingChecklist(member.uuid, into: folder)
          ),
          (
            type: 'composition',
            build: () =>
                repository.buildCompositionChecklist(member.uuid, into: folder)
          ),
          // The notice served on the client. The direction record was going
          // up on its own and the office had to draw the sheet itself.
          (
            type: 'direction',
            build: () => repository.buildDirection(member.uuid, into: folder)
          ),
        ]);
      case 'pmp':
        final repository = PmpRepository(database: database, baseUrl: '');
        wanted.addAll([
          (
            type: 'compliance',
            build: () =>
                repository.buildLabellingChecklist(member.uuid, into: folder)
          ),
          (
            type: 'lab_form',
            build: () =>
                repository.buildSamplingChecklist(member.uuid, into: folder)
          ),
          // The notice served on the client, as raw already sends.
          (
            type: 'direction',
            build: () => repository.buildDirection(member.uuid, into: folder)
          ),
        ]);
      case 'egg':
        final repository = EggsRepository(database: database, baseUrl: '');
        wanted.addAll([
          (
            type: 'compliance',
            build: () =>
                repository.buildLabellingChecklist(member.uuid, into: folder)
          ),
          (
            type: 'compliance',
            build: () =>
                repository.buildWeighingChecklist(member.uuid, into: folder)
          ),
          // The rejection itself. It was raised, numbered and uploaded as
          // data, and the sheet the client was served existed nowhere.
          (
            type: 'direction',
            build: () => repository.buildDirection(member.uuid, into: folder)
          ),
        ]);
      case 'quid':
        // A QUID member used to fall through to the default and send the
        // office no sheet at all, only figures.
        final repository = PoultryRepository(database: database, baseUrl: '');
        wanted.addAll([
          (
            type: 'compliance',
            build: () =>
                repository.buildQuidChecklist(member.uuid, into: folder)
          ),
          // The rejection the weighing ended in, as served on the facility.
          // Null while there is none.
          (
            type: 'direction',
            build: () =>
                repository.buildQuidRejection(member.uuid, into: folder)
          ),
        ]);
      case 'poultry':
      case 'poultry_label':
        final repository = PoultryRepository(database: database, baseUrl: '');
        wanted.addAll([
          (
            type: 'compliance',
            build: () =>
                repository.buildGradingChecklist(member.uuid, into: folder)
          ),
          (
            type: 'compliance',
            build: () => repository.buildPoultryLabellingChecklist(member.uuid,
                into: folder)
          ),
          // The direction served off this record, when one was.
          (
            type: 'direction',
            build: () => repository.buildDirection(member.uuid, into: folder)
          ),
        ]);
      default:
        return const [];
    }

    // The seizure served off this record, when one was: FSA-SOP-APS-001
    // Annexure E, the same sheet whatever the commodity, so it travels with
    // the visit like the rejection does and is filed beside it.
    wanted.add((
      type: 'seizure',
      build: () => SeizureRepository(database: database)
          .buildDocument(member.uuid, into: folder),
    ));

    final built = <({String type, String filename, File file})>[];
    for (final one in wanted) {
      try {
        final file = await one.build();
        // A document that could not be rendered — a block the inspector
        // never opened, say — is simply not sent; the rest still go.
        if (file == null || !file.existsSync()) continue;
        built.add((
          type: one.type,
          filename: file.uri.pathSegments.last,
          file: file,
        ));
      } on Object {
        // One document failing must not cost the office the others.
      }
    }
    return built;
  }

  Future<Map<String, Object?>> _labDetails(VisitMember member) async {
    int? laboratoryId;
    int? categoryId;
    var categoryIds = '';
    var calcium = false;
    var dnaText = '';
    switch (member.kind) {
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null || !row.isSampled) return const {};
        laboratoryId = row.laboratoryId;
        categoryId = row.sampleCategoryId;
        categoryIds = row.sampleCategoryIds;
        calcium = row.calciumTestRequired;
        dnaText = row.dnaSpeciesText;
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        if (row == null || !row.isSampled) return const {};
        laboratoryId = row.laboratoryId;
      default:
        return const {};
    }

    final laboratory = await _nameOf(
        member.kind == 'rawrmp' ? 'raw_rmp_laboratories' : 'pmp_laboratories',
        laboratoryId);
    // Every category the sample went for; a record from before the list
    // holds one.
    final ids = [
      for (final s in categoryIds.split(','))
        if (int.tryParse(s.trim()) != null) int.parse(s.trim()),
    ];
    if (ids.isEmpty && categoryId != null) ids.add(categoryId);
    final names = <String>[];
    for (final id in ids) {
      names.add(await _nameOf('raw_rmp_sample_categories', id));
    }

    // The categories name what the laboratory is asked to determine —
    // "Category A - Meat (Protein) & Fat Content" and so on — so the flags
    // are read off the categories rather than asked for twice.
    final wanted = names.join(' ').toLowerCase();
    return {
      // The office record calls this `laboratory`; sending `lab` meant the
      // name was quietly dropped on arrival.
      'laboratory': laboratory,
      'fat': wanted.contains('fat'),
      'protein': wanted.contains('protein'),
      'calcium': calcium,
      'dna': dnaText.trim().isNotEmpty ||
          wanted.contains('specie') ||
          wanted.contains('dna'),
    };
  }

  Future<bool> _wasSampled(VisitMember member) async {
    switch (member.kind) {
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.isSampled ?? false;
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.isSampled ?? false;
      default:
        return false;
    }
  }

  Future<String> _nameOf(String table, int? id) async {
    if (id == null) return '';
    final rows = await database.customSelect(
        'SELECT name FROM $table WHERE id = ?',
        variables: [Variable<int>(id)]).get();
    return rows.isEmpty ? '' : (rows.first.data['name'] as String? ?? '');
  }

  Future<List<StoreVisit>> openVisits() =>
      (database.select(database.storeVisits)
            ..where((t) => t.completedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .get();

  Future<StoreVisit?> byUuid(String uuid) =>
      (database.select(database.storeVisits)..where((t) => t.uuid.equals(uuid)))
          .getSingleOrNull();

  /// Removes the group record itself. Member inspections are standalone
  /// rows and are deliberately left in place — discarding a plan must never
  /// delete captured evidence. Members waiting as `ready` step back to
  /// `draft`: with the group gone there is no sign-off coming to submit
  /// them, and nothing may upload unsubmitted.
  Future<void> discard(String uuid) async {
    await _setReadyMembers(uuid, 'draft', DateTime.now());
    await (database.delete(database.storeVisits)
          ..where((t) => t.uuid.equals(uuid)))
        .go();
  }

  /// Discards an unsigned visit and every inspection captured under it.
  ///
  /// [discard] on its own leaves the member inspections behind, which is
  /// right when a plan is being put away but wrong when the inspector means
  /// to be rid of the visit: the records were left orphaned, counted by
  /// nothing and reachable from nowhere. Before sign-off the office has
  /// none of it, so the whole visit goes together.
  ///
  /// Refuses a visit that has been signed off — that work belongs to the
  /// office, and the caller is expected not to offer it.
  Future<bool> discardWithMembers(String uuid) async {
    final visit = await byUuid(uuid);
    if (visit == null || visit.completedAt != null) return false;
    // Each pass takes the newest of that commodity; repeat until the visit
    // holds none. The per-commodity path already clears the samples,
    // photographs and signatures that hang off a record.
    for (final kind in const [
      'egg',
      'poultry',
      'poultry_label',
      'quid',
      'pmp',
      'rawrmp',
    ]) {
      // A plan can hold at most sixty of one commodity; the bound is only
      // there so a row that will not delete cannot spin for ever.
      for (var i = 0; i < 60; i++) {
        final removed =
            await discardDraftMember(uuid, kind, includeCaptured: true);
        if (!removed) break;
      }
    }
    await discard(uuid);
    return true;
  }

  /// Removes a QUID determination and everything that hangs off it.
  ///
  /// Its carcasses and the set-up's injector list belong to the record; left
  /// behind they are rows nothing can reach.
  Future<void> _deleteQuid(String uuid) async {
    await (database.delete(database.poultryQuidSamples)
          ..where((t) => t.inspectionUuid.equals(uuid)))
        .go();
    await (database.delete(database.poultryQuidInjectors)
          ..where((t) => t.inspectionUuid.equals(uuid)))
        .go();
    await (database.delete(database.poultryQuidInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .go();
  }

  /// Drops the newest removable inspection of [kind] from this visit.
  ///
  /// The way back out of a commodity added by mistake: an inspector who
  /// plans two raws, opens the second and then finds it is not needed has
  /// to be able to take it off the plan.
  ///
  /// By default only a draft goes. With [includeCaptured] a finished record
  /// goes too, which is what an inspector needs before the group is signed
  /// off: an egg inspection captured in full and then found to be the wrong
  /// product could not be taken off the plan at all, and the visit could
  /// not be signed off without it. Nothing here can touch work the office
  /// already has — the group has to be unsigned for the caller to offer it,
  /// and an uploaded record is never in that state.
  ///
  /// Returns whether anything was removed.
  Future<bool> discardDraftMember(
    String visitUuid,
    String kind, {
    bool includeCaptured = false,
  }) async {
    // Draft only, or anything this visit still holds — newest first either
    // way, so it is the one just added that goes.
    Expression<bool> removable(Expression<String> status) =>
        includeCaptured ? const Constant(true) : status.equals('draft');
    String? uuid;
    switch (kind) {
      case 'egg':
        final row = await (database.select(database.eggInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        uuid = row?.clientUuid;
        if (uuid != null) {
          await (database.delete(database.eggSamples)
                ..where((t) => t.inspectionUuid.equals(uuid!)))
              .go();
          await (database.delete(database.eggPhotos)
                ..where((t) => t.inspectionUuid.equals(uuid!)))
              .go();
          await (database.delete(database.eggSignatures)
                ..where((t) => t.inspectionUuid.equals(uuid!)))
              .go();
          await (database.delete(database.eggInspections)
                ..where((t) => t.clientUuid.equals(uuid!)))
              .go();
        }
      case 'poultry':
        // One plan row covers all three poultry records — grading, the
        // label checklist and a QUID determination — so reducing it has to
        // take the newest of whichever was captured. Looking only in the
        // grading table left a QUID record listed under "captured so far"
        // that nothing on the plan asked for, and the visit could not be
        // signed off without it.
        final grading = await (database.select(database.poultryInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        final labelled =
            await (database.select(database.poultryLabelInspections)
                  ..where((t) =>
                      t.visitUuid.equals(visitUuid) & removable(t.status))
                  ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
                  ..limit(1))
                .getSingleOrNull();
        final determined =
            await (database.select(database.poultryQuidInspections)
                  ..where((t) =>
                      t.visitUuid.equals(visitUuid) & removable(t.status))
                  ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
                  ..limit(1))
                .getSingleOrNull();
        final newest = <({String uuid, DateTime at, String kind})>[
          if (grading != null)
            (uuid: grading.clientUuid, at: grading.updatedAt, kind: 'poultry'),
          if (labelled != null)
            (
              uuid: labelled.clientUuid,
              at: labelled.updatedAt,
              kind: 'poultry_label'
            ),
          if (determined != null)
            (
              uuid: determined.clientUuid,
              at: determined.updatedAt,
              kind: 'quid'
            ),
        ]..sort((a, b) => b.at.compareTo(a.at));
        if (newest.isNotEmpty) {
          uuid = newest.first.uuid;
          switch (newest.first.kind) {
            case 'poultry':
              await (database.delete(database.poultryInspections)
                    ..where((t) => t.clientUuid.equals(uuid!)))
                  .go();
            case 'poultry_label':
              await (database.delete(database.poultryLabelInspections)
                    ..where((t) => t.clientUuid.equals(uuid!)))
                  .go();
            default:
              await _deleteQuid(uuid);
          }
        }
      case 'quid':
        final row = await (database.select(database.poultryQuidInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        uuid = row?.clientUuid;
        if (uuid != null) await _deleteQuid(uuid);
      case 'poultry_label':
        final row = await (database.select(database.poultryLabelInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        uuid = row?.clientUuid;
        if (uuid != null) {
          await (database.delete(database.poultryLabelInspections)
                ..where((t) => t.clientUuid.equals(uuid!)))
              .go();
        }
      case 'pmp':
        final row = await (database.select(database.pmpInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        uuid = row?.clientUuid;
        if (uuid != null) {
          await (database.delete(database.pmpInspections)
                ..where((t) => t.clientUuid.equals(uuid!)))
              .go();
        }
      // Named rather than left to a default: an unrecognised kind falling
      // through here deleted the newest raw record instead, which is how
      // asking to remove one commodity took another one with it.
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where(
                  (t) => t.visitUuid.equals(visitUuid) & removable(t.status))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
        uuid = row?.clientUuid;
        if (uuid != null) {
          await (database.delete(database.rawRmpInspections)
                ..where((t) => t.clientUuid.equals(uuid!)))
              .go();
        }
      default:
        return false;
    }

    if (uuid == null) return false;
    // The photographs and signatures of the meat and poultry records live
    // in the one evidence store, keyed on the record.
    await (database.delete(database.poultryPhotos)
          ..where((t) => t.recordUuid.equals(uuid!)))
        .go();
    await (database.delete(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(uuid!)))
        .go();
    return true;
  }

  Future<void> create(String uuid, String inspectorUsername) =>
      database.into(database.storeVisits).insert(
            StoreVisitsCompanion.insert(
              uuid: uuid,
              inspectorUsername: Value(inspectorUsername),
              startedAt: DateTime.now(),
              // Nothing to tell the server about approval yet.
              approvalSent: const Value(true),
            ),
          );

  Future<void> saveDetails(StoreVisitsCompanion companion) => database
      .update(database.storeVisits)
      .replace(companion); // ignore: unawaited_futures

  Future<void> updateDetails(String uuid, StoreVisitsCompanion companion) =>
      (database.update(database.storeVisits)..where((t) => t.uuid.equals(uuid)))
          .write(companion);

  VisitPrefill prefillOf(StoreVisit visit) => VisitPrefill(
        uuid: visit.uuid,
        facilityName: visit.facilityName,
        facilityAddress: visit.facilityAddress,
        facilityPhone: visit.facilityPhone,
        contactPerson: visit.contactPerson,
        contactEmail: visit.contactEmail,
        representative: visit.representative,
        managerName: visit.managerName,
        managerEmail: visit.managerEmail,
        additionalEmail1: visit.additionalEmail1,
        additionalEmail2: visit.additionalEmail2,
        additionalEmail3: visit.additionalEmail3,
        facilityType: visit.facilityType,
        inspectionReason: visit.inspectionReason,
        distanceTravelledKm: visit.distanceTravelledKm,
        producer: visit.producerName,
      );

  /// Every inspection captured under this visit, across the commodities.
  Future<List<VisitMember>> members(String visitUuid) async {
    final members = <VisitMember>[];

    final eggs = await (database.select(database.eggInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in eggs) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'egg',
        label: 'Egg inspection',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final poultry = await (database.select(database.poultryInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in poultry) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'poultry',
        label: 'Poultry inspection',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final quid = await (database.select(database.poultryQuidInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in quid) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'quid',
        label: 'Poultry QUID verification',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in raw) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'rawrmp',
        label: row.recordKind == RawRecordKind.composition.stored
            ? 'Compositional checklist'
            : 'Certain Raw Processed Meat Product inspection',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final pmp = await (database.select(database.pmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in pmp) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'pmp',
        label: 'Processed Meat Product inspection',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final labels = await (database.select(database.poultryLabelInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in labels) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'poultry_label',
        label: 'Label/Container inspection',
        completed: row.status == 'completed' || row.status == 'ready',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    return members;
  }

  /// Every visit ever captured on this device, newest first — the grouped
  /// inspections the management screen lists, open and signed-off alike.
  Future<List<StoreVisit>> allVisits() => (database.select(database.storeVisits)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .get();

  /// Frees device storage from completed visits only after the server has
  /// confirmed the group and every constituent record/evidence item.
  ///
  /// This deliberately never touches drafts, pending uploads, or records
  /// whose three-day retention period has not elapsed.
  Future<int> purgeUploadedVisits({Duration retention = localRetention}) async {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final storage = await PhotoStorage.instance();
    var removed = 0;

    for (final visit in await allVisits()) {
      if (!visit.isUploaded || visit.completedAt == null) continue;
      final uploadedAt = DateTime.tryParse(
        await database.readSyncState('$_uploadedAtPrefix${visit.uuid}') ?? '',
      );
      if (uploadedAt == null || uploadedAt.toUtc().isAfter(cutoff)) continue;

      final members = await this.members(visit.uuid);
      if (members.isEmpty || members.any((member) => !member.isUploaded)) {
        continue;
      }

      final imagePaths = <String>[];
      var evidenceComplete = true;
      for (final member in members) {
        final evidence = await _evidenceFor(member.uuid, member.kind);
        if (!evidence.complete) {
          evidenceComplete = false;
          break;
        }
        imagePaths.addAll(evidence.paths);
      }
      if (!evidenceComplete) continue;

      final invoice = await (database.select(database.invoiceRequests)
            ..where((t) => t.visitUuid.equals(visit.uuid)))
          .getSingleOrNull();
      if (invoice != null && invoice.pdfPath.isNotEmpty) {
        imagePaths.add(invoice.pdfPath);
      }

      await database.transaction(() async {
        for (final member in members) {
          await _deleteMember(member);
        }
        await (database.delete(database.invoiceRequests)
              ..where((t) => t.visitUuid.equals(visit.uuid)))
            .go();
        await (database.delete(database.storeVisits)
              ..where((t) => t.uuid.equals(visit.uuid)))
            .go();
        await database.writeSyncState('$_uploadedAtPrefix${visit.uuid}', '');
      });
      for (final path in imagePaths.toSet()) {
        await storage.delete(path);
      }
      removed++;
    }
    return removed;
  }

  Future<_Evidence> _evidenceFor(String uuid, String kind) async {
    final paths = <String>[];
    var complete = true;
    if (kind == 'egg') {
      final photos = await (database.select(database.eggPhotos)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .get();
      final signatures = await (database.select(database.eggSignatures)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .get();
      complete = photos.every((row) => row.isUploaded) &&
          signatures.every((row) => row.isUploaded);
      paths.addAll(photos.map((row) => row.filePath));
      paths.addAll(signatures.map((row) => row.filePath));
    } else {
      final photos = await (database.select(database.poultryPhotos)
            ..where((t) => t.recordUuid.equals(uuid)))
          .get();
      final signatures = await (database.select(database.poultrySignatures)
            ..where((t) => t.recordUuid.equals(uuid)))
          .get();
      complete = photos.every((row) => row.isUploaded) &&
          signatures.every((row) => row.isUploaded);
      paths.addAll(photos.map((row) => row.filePath));
      paths.addAll(signatures.map((row) => row.filePath));
    }
    return _Evidence(complete: complete, paths: paths);
  }

  Future<void> _deleteMember(VisitMember member) async {
    final uuid = member.uuid;
    if (member.kind == 'egg') {
      await (database.delete(database.eggSamples)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.eggPhotos)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.eggSignatures)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.eggInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .go();
      return;
    }

    await (database.delete(database.poultryPhotos)
          ..where((t) => t.recordUuid.equals(uuid)))
        .go();
    await (database.delete(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(uuid)))
        .go();
    switch (member.kind) {
      case 'poultry':
        await (database.delete(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .go();
        return;
      case 'poultry_label':
        await (database.delete(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .go();
        return;
      case 'pmp':
        await (database.delete(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .go();
        return;
      case 'quid':
        await (database.delete(database.poultryQuidSamples)
              ..where((t) => t.inspectionUuid.equals(uuid)))
            .go();
        // The set-up's injector list belongs to the record and was being
        // left behind, so a new determination on the same plant inherited
        // injectors nobody had entered.
        await (database.delete(database.poultryQuidInjectors)
              ..where((t) => t.inspectionUuid.equals(uuid)))
            .go();
        await (database.delete(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .go();
        return;
      default:
        await (database.delete(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .go();
    }
  }

  /// Inspections captured outside any surviving visit — standalone records,
  /// plus members whose visit was discarded (the group is gone but captured
  /// evidence is never deleted).
  Future<List<VisitMember>> standaloneInspections() async {
    final visitUuids = database.selectOnly(database.storeVisits)
      ..addColumns([database.storeVisits.uuid]);

    final members = <VisitMember>[];

    final eggs = await (database.select(database.eggInspections)
          ..where((t) =>
              t.visitUuid.equals('') | t.visitUuid.isNotInQuery(visitUuids)))
        .get();
    for (final row in eggs) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'egg',
        label: 'Egg inspection',
        completed: row.status == 'completed',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final poultry = await (database.select(database.poultryInspections)
          ..where((t) =>
              t.visitUuid.equals('') | t.visitUuid.isNotInQuery(visitUuids)))
        .get();
    for (final row in poultry) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'poultry',
        label: 'Poultry inspection',
        completed: row.status == 'completed',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) =>
              t.visitUuid.equals('') | t.visitUuid.isNotInQuery(visitUuids)))
        .get();
    for (final row in raw) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'rawrmp',
        label: 'Certain Raw Processed Meat Product inspection',
        completed: row.status == 'completed',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    final labels = await (database.select(database.poultryLabelInspections)
          ..where((t) =>
              t.visitUuid.equals('') | t.visitUuid.isNotInQuery(visitUuids)))
        .get();
    for (final row in labels) {
      members.add(VisitMember(
        uuid: row.clientUuid,
        kind: 'poultry_label',
        label: 'Label/Container inspection',
        completed: row.status == 'completed',
        status: row.status,
        isUploaded: row.isUploaded,
        inspectedAt: row.inspectedAt,
      ));
    }

    members.sort((a, b) {
      final at = a.inspectedAt ?? DateTime(2000);
      final bt = b.inspectedAt ?? DateTime(2000);
      return bt.compareTo(at);
    });
    return members;
  }

  /// The facility each standalone record names, for the management list.
  Future<String> facilityOf(VisitMember member) async {
    switch (member.kind) {
      case 'egg':
        final row = await (database.select(database.eggInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.facilityName ?? '';
      case 'poultry':
        final row = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.facilityName ?? '';
      case 'rawrmp':
        final row = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.facilityName ?? '';
      case 'quid':
        final row = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.facilityName ?? '';
      default:
        final row = await (database.select(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(member.uuid)))
            .getSingleOrNull();
        return row?.facilityName ?? '';
    }
  }

  /// Stamps the closing signatures into every member and closes the visit.
  ///
  /// Each member gets its own copy of the signature image files, because
  /// records upload — and are later cleaned up — independently; two records
  /// sharing one file would lose the image the moment either was tidied.
  ///
  /// An empty [managerSignaturePath] means the client declined to sign. That
  /// is recorded the way the standalone forms record it — a declined
  /// signature row and the record's "no client signature present" flag — so
  /// the office can tell a refusal from a signature nobody collected.
  Future<void> complete({
    required String visitUuid,
    required String managerSignaturePath,
    required String inspectorSignaturePath,
    required String managerName,
    required String inspectorName,
    double? latitude,
    double? longitude,
  }) async {
    final all = await members(visitUuid);
    final now = DateTime.now();
    final clientDeclined = managerSignaturePath.isEmpty;

    Future<String> copyFor(String source, String member, String role) async {
      final dot = source.lastIndexOf('.');
      final ext = dot == -1 ? '.png' : source.substring(dot);
      final stem =
          source.replaceRange(dot == -1 ? source.length : dot, null, '');
      final target = '${stem}_${member}_$role$ext';
      await File(source).copy(target);
      return target;
    }

    for (final member in all) {
      if (member.kind == 'egg') {
        await database.into(database.eggSignatures).insert(
              EggSignaturesCompanion.insert(
                inspectionUuid: member.uuid,
                role: 'manager',
                filePath: clientDeclined
                    ? ''
                    : await copyFor(
                        managerSignaturePath, member.uuid, 'manager'),
                signedName: Value(managerName),
                declined: Value(clientDeclined),
                signedAt: Value(now),
              ),
            );
        await database.into(database.eggSignatures).insert(
              EggSignaturesCompanion.insert(
                inspectionUuid: member.uuid,
                role: 'inspector',
                filePath: await copyFor(
                    inspectorSignaturePath, member.uuid, 'inspector'),
                signedName: Value(inspectorName),
                signedAt: Value(now),
              ),
            );
      } else {
        // Both poultry capture kinds share one signature table, keyed on the
        // record uuid — the roles mirror the standalone evidence section.
        if (clientDeclined) {
          // The evidence section's own way of saying so: a `no_client` row.
          await database.into(database.poultrySignatures).insert(
                PoultrySignaturesCompanion.insert(
                  recordUuid: member.uuid,
                  role: 'no_client',
                  signedName: Value(managerName),
                  declined: const Value(true),
                  signedAt: now,
                ),
              );
        } else {
          await database.into(database.poultrySignatures).insert(
                PoultrySignaturesCompanion.insert(
                  recordUuid: member.uuid,
                  role: 'client',
                  signedName: Value(managerName),
                  filePath: Value(await copyFor(
                      managerSignaturePath, member.uuid, 'client')),
                  signedAt: now,
                ),
              );
        }
        await database.into(database.poultrySignatures).insert(
              PoultrySignaturesCompanion.insert(
                recordUuid: member.uuid,
                role: 'inspector',
                signedName: Value(inspectorName),
                filePath: Value(await copyFor(
                    inspectorSignaturePath, member.uuid, 'inspector')),
                signedAt: now,
              ),
            );
      }
    }

    if (clientDeclined) await _markNoClientSignature(visitUuid);

    // The single submit: every member captured as `ready` becomes
    // `completed` now, which is what the upload path sends. Until this
    // moment nothing in the visit has been submitted.
    await _setReadyMembers(
      visitUuid,
      'completed',
      now,
      latitude: latitude,
      longitude: longitude,
    );

    await updateDetails(
      visitUuid,
      StoreVisitsCompanion(
        completedAt: Value(now),
        // Kept on the visit as well: an occurrence report with no
        // inspections has nowhere else to hold its signatures.
        managerSignaturePath: Value(managerSignaturePath),
        inspectorSignaturePath: Value(inspectorSignaturePath),
      ),
    );
  }

  /// The record-level flag the original carries for a refused client
  /// signature, set on every inspection in the visit that has one.
  Future<void> _markNoClientSignature(String visitUuid) async {
    await (database.update(database.poultryInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .write(const PoultryInspectionsCompanion(
            noClientSignaturePresent: Value(true)));
    await (database.update(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .write(const RawRmpInspectionsCompanion(
            noClientSignaturePresent: Value(true)));
    await (database.update(database.poultryLabelInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .write(const PoultryLabelInspectionsCompanion(
            noClientSignaturePresent: Value(true)));
    await (database.update(database.pmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .write(const PmpInspectionsCompanion(
            noClientSignaturePresent: Value(true)));
    await (database.update(database.poultryQuidInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .write(const PoultryQuidInspectionsCompanion(
            noClientSignaturePresent: Value(true)));
  }

  Future<void> _setReadyMembers(
    String visitUuid,
    String status,
    DateTime now, {
    double? latitude,
    double? longitude,
  }) async {
    await (database.update(database.eggInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(EggInspectionsCompanion(
      status: Value(status),
      updatedAt: Value(now),
      latitude: Value(latitude),
      longitude: Value(longitude),
    ));
    await (database.update(database.poultryInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(PoultryInspectionsCompanion(
            status: Value(status), updatedAt: Value(now)));
    await (database.update(database.rawRmpInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(RawRmpInspectionsCompanion(
            status: Value(status), updatedAt: Value(now)));
    await (database.update(database.poultryLabelInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(PoultryLabelInspectionsCompanion(
            status: Value(status), updatedAt: Value(now)));
    await (database.update(database.pmpInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(PmpInspectionsCompanion(
            status: Value(status), updatedAt: Value(now)));
    // QUID was completing itself the moment the inspector left the screen,
    // so the group's one sign-off had nothing to promote and the record was
    // filed before anyone had signed it.
    await (database.update(database.poultryQuidInspections)
          ..where(
              (t) => t.visitUuid.equals(visitUuid) & t.status.equals('ready')))
        .write(PoultryQuidInspectionsCompanion(
            status: Value(status), updatedAt: Value(now)));
  }
}
