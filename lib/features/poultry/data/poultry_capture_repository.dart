import 'dart:convert';

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';

/// Capture and upload for the Label/Container, QUID and Direction records.
///
/// Separate from [PoultryRepository], which owns the reference data and the
/// grading inspection. The split is by record rather than by concern so each
/// screen depends on one object, and the reference loader does not grow a
/// method per screen.
class PoultryCaptureRepository {
  PoultryCaptureRepository({
    required this.database,
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final LocalDatabase database;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  Future<String?> storedToken() => database.readSyncState('auth.accessToken');

  /// True when [value] falls on or between the calendar days [from] and [to].
  ///
  /// By day rather than by instant, so a record captured at 16:40 on the
  /// closing day of a range is inside it.
  static bool withinDays(DateTime value, DateTime from, DateTime to) {
    final day = DateTime(value.year, value.month, value.day);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Rows belonging to [username], or to nobody.
  ///
  /// Unowned rows predate ownership and are shown to whoever is signed in,
  /// because there is no better answer available.
  static bool _mine(String owner, String username) =>
      owner.isEmpty || owner.toLowerCase() == username.toLowerCase();

  // ------------------------------------------------------- label checklist

  Future<void> saveLabelInspection(PoultryLabelInspectionsCompanion row) =>
      database
          .into(database.poultryLabelInspections)
          .insertOnConflictUpdate(row);

  Future<List<PoultryLabelInspection>> labelInspections(String username) async {
    final rows = await (database.select(database.poultryLabelInspections)
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

  Future<PoultryLabelInspection?> labelInspectionByUuid(String uuid) =>
      (database.select(database.poultryLabelInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  /// The registration number already recorded for this visit, or empty.
  ///
  /// It is a fact about the premises, not about the product, and the three
  /// poultry records each ask for it — so an inspector doing a grading and a
  /// label checklist at one abattoir was typing it twice. The first record to
  /// capture it answers for the rest of the visit. It stays editable: the
  /// answer is carried, not locked.
  Future<String> registrationNumberForVisit(String visitUuid) async {
    if (visitUuid.isEmpty) return '';

    final label = await (database.select(database.poultryLabelInspections)
          ..where((t) => t.visitUuid.equals(visitUuid))
          ..where((t) => t.registrationNumber.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (label != null) return label.registrationNumber;

    final grading = await (database.select(database.poultryInspections)
          ..where((t) => t.visitUuid.equals(visitUuid))
          ..where((t) => t.companyRegNumber.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (grading != null) return grading.companyRegNumber;

    final quid = await (database.select(database.poultryQuidInspections)
          ..where((t) => t.visitUuid.equals(visitUuid))
          ..where((t) => t.companyRegNumber.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    return quid?.companyRegNumber ?? '';
  }

  Future<void> uploadLabelInspection(
    PoultryLabelInspection i, {
    required String token,
  }) async {
    await _post(
      'label-inspections',
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
        'registration_number': i.registrationNumber,
        'contact_person': i.contactPerson,
        'contact_person_email': i.contactPersonEmail,
        'product_details': i.productDetails,
        'selected_direction_for_followup': i.selectedDirectionForFollowup,
        // Meat type, portion type, designation, grade and sample number are
        // not sent: they belong to the grading inspection, which is a record
        // of its own. The server's columns for them stay nullable, so a
        // labelling record simply leaves them empty.
        'outer_labels_present': i.outerLabelsPresent,
        'restricted_particulars': idsOf(i.restrictedParticularIds),
        'restricted_particulars_text': i.restrictedParticularsText,
        'compliant_item_ids': i.compliantItemIds,
        'non_conformance_comments': i.nonConformanceComments,
        'direction_remarks': i.directionRemarks,
        'direction_remark_type': i.directionRemarkTypeId,
        'class_omitted': i.classOmitted,
        'grade_omitted': i.gradeOmitted,
        'seizure_decision': i.seizureDecision,
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
    await (database.update(database.poultryLabelInspections)
          ..where((t) => t.clientUuid.equals(i.clientUuid)))
        .write(const PoultryLabelInspectionsCompanion(isUploaded: Value(true)));
  }

  // ------------------------------------------------------------------ QUID

  Future<void> saveQuidInspection(PoultryQuidInspectionsCompanion row) =>
      database
          .into(database.poultryQuidInspections)
          .insertOnConflictUpdate(row);

  Future<List<PoultryQuidInspection>> quidInspections(String username) async {
    final rows = await (database.select(database.poultryQuidInspections)
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

  Future<PoultryQuidInspection?> quidInspectionByUuid(String uuid) =>
      (database.select(database.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  Future<List<PoultryQuidSample>> quidSamples(String inspectionUuid) =>
      (database.select(database.poultryQuidSamples)
            ..where((t) => t.inspectionUuid.equals(inspectionUuid)))
          .get();

  /// The injectors a QUID set-up listed, in the order they were added.
  Future<List<PoultryQuidInjector>> quidInjectors(String inspectionUuid) =>
      (database.select(database.poultryQuidInjectors)
            ..where((t) => t.inspectionUuid.equals(inspectionUuid))
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .get();

  /// Replaced wholesale, as the samples are: the set-up screen owns the list
  /// and its positions are what the carcasses are assigned against.
  Future<void> replaceQuidInjectors(
    String inspectionUuid,
    List<PoultryQuidInjectorsCompanion> rows,
  ) async {
    await database.transaction(() async {
      await (database.delete(database.poultryQuidInjectors)
            ..where((t) => t.inspectionUuid.equals(inspectionUuid)))
          .go();
      for (final row in rows) {
        await database.into(database.poultryQuidInjectors).insert(row);
      }
    });
  }

  Future<void> replaceQuidSamples(
    String inspectionUuid,
    List<PoultryQuidSamplesCompanion> rows,
  ) async {
    // Replaced wholesale rather than merged: the screen owns the list, and
    // matching rows up by index would reassign masses to the wrong carcass
    // the moment one is deleted.
    await database.transaction(() async {
      await (database.delete(database.poultryQuidSamples)
            ..where((t) => t.inspectionUuid.equals(inspectionUuid)))
          .go();
      for (final row in rows) {
        await database.into(database.poultryQuidSamples).insert(row);
      }
    });
  }

  Future<void> uploadQuidInspection(
    PoultryQuidInspection i, {
    required String token,
  }) async {
    final samples = await quidSamples(i.clientUuid);
    final injectors = await quidInjectors(i.clientUuid);
    await _post(
      'quid-inspections',
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
        'company_reg_number': i.companyRegNumber,
        'contact_person': i.contactPerson,
        'contact_person_email': i.contactPersonEmail,
        'product_details': i.productDetails,
        'is_water_chilled': i.isWaterChilled,
        'is_whole_carcass': i.isWholeCarcass,
        'injector_name': i.injectorName,
        'is_regulated_standard': i.isRegulatedStandard,
        'dispensation_quid_percent': i.dispensationQuidPercent,
        'setup_complete': i.setupComplete,
        'client_name': i.clientName,
        'iteration_number': i.iterationNumber,
        'average_water_chill_pickup': i.averageWaterChillPickup,
        'water_chilling_complete': i.waterChillingComplete,
        'air_chilling_complete': i.airChillingComplete,
        'average_injector_pickup': i.averageInjectorPickup,
        'injector_sampling_complete': i.injectorSamplingComplete,
        'quid_initial_mass_g': i.quidInitialMassG,
        'quid_after_mass_g': i.quidAfterMassG,
        'quid_gain_mass_g': i.quidGainMassG,
        'quid_percent': i.quidPercent,
        'quid_determination_complete': i.quidDeterminationComplete,
        'repeat_quid_determination': i.repeatQuidDetermination,
        'set_injector_quid_percent': i.setInjectorQuidPercent,
        // The date on the record being verified. It was captured on the
        // handset and stopped there, so the office had a verification with
        // no date against it.
        'document_date': i.documentDate?.toIso8601String().split('T').first,
        'document_name': i.documentName,
        'document_verified': i.documentVerified,
        'document_deviation_present': i.documentDeviationPresent,
        'document_deviation_comment': i.documentDeviationComment,
        'verification_records_json': i.verificationRecordsJson,
        'direction_required': i.directionRequired,
        'direction_reason': i.directionReason,
        'correct_by_date':
            i.correctByDate?.toIso8601String().split('T').first,
        'direction_remark_type': i.directionRemarkTypeId,
        'direction_remarks': i.directionRemarks,
        'direction_action': i.directionAction,
        'seizure_decision': i.seizureDecision,
        'manager_name': i.managerName,
        'manager_email': i.managerEmail,
        'client_email': i.clientEmail,
        'client_email_2': i.clientEmail2,
        'no_client_signature_present': i.noClientSignaturePresent,
        'general_comments': i.generalComments,
        'latitude': i.latitude,
        'longitude': i.longitude,
        'samples': [
          for (final s in samples)
            {
              'carcass_number': s.carcassNumber,
              'injector_number': s.injectorNumber,
              'initial_mass_g': s.initialMassG,
              'after_mass_g': s.afterMassG,
              'final_mass_g': s.finalMassG,
              'pickup_percent': s.pickupPercent,
              // The injector weighings and this carcass's own determination.
              // Both were captured and neither travelled, so the office was
              // reading averages it could not check.
              'before_mass_g': s.beforeMassG,
              'injector_after_mass_g': s.injectorAfterMassG,
              'gain_g': s.gainG,
              'injector_rate_percent': s.injectorRatePercent,
              'quid_final_mass_g': s.quidFinalMassG,
              'quid_gain_g': s.quidGainG,
              'quid_percent': s.quidPercent,
              'assigned_injector': s.assignedInjector,
              'iteration': s.iteration,
            },
        ],
        // The set-up's injector list. The finding compares what an injector
        // was set to against what its carcasses gained, so without it the
        // office has one half of the comparison.
        'injectors': [
          for (final inj in injectors)
            {
              'position': inj.position,
              'name': inj.name,
              'quid_percent': inj.quidPercent,
            },
        ],
      },
    );
    await (database.update(database.poultryQuidInspections)
          ..where((t) => t.clientUuid.equals(i.clientUuid)))
        .write(const PoultryQuidInspectionsCompanion(isUploaded: Value(true)));
  }

  // ------------------------------------------------------------ directions

  Future<void> saveDirection(PoultryDirectionsCompanion row) =>
      database.into(database.poultryDirections).insertOnConflictUpdate(row);

  Future<List<PoultryDirection>> directions(String username) async {
    final rows = await (database.select(database.poultryDirections)
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

  Future<PoultryDirection?> directionByUuid(String uuid) =>
      (database.select(database.poultryDirections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingleOrNull();

  Future<void> uploadDirection(
    PoultryDirection d, {
    required String token,
  }) async {
    await _post(
      'directions',
      token: token,
      body: {
        'client_uuid': d.clientUuid,
        'status': d.status,
        'issued_at': d.issuedAt.toUtc().toIso8601String(),
        'facility_name': d.facilityName,
        'client_name': d.clientName,
        'client_email': d.clientEmail,
        'remark_type': d.remarkTypeId,
        'remarks': d.remarks,
        'comments': d.comments,
        'action_taken': d.actionTaken,
        'non_conformance_ids': d.nonConformanceIds,
        'correct_by_date':
            d.correctByDate?.toIso8601String().split('T').first,
        'latitude': d.latitude,
        'longitude': d.longitude,
      },
    );
    await (database.update(database.poultryDirections)
          ..where((t) => t.clientUuid.equals(d.clientUuid)))
        .write(const PoultryDirectionsCompanion(isUploaded: Value(true)));
  }

  // ------------------------------------------------- photos and signatures

  Future<int> addPhoto(PoultryPhotosCompanion row) =>
      database.into(database.poultryPhotos).insert(row);

  /// The photographs on [recordUuid], oldest first — all of them, or only
  /// those of one [kind]. A QUID record holds two kinds: the `quid` shots
  /// its rejection needs and a `document` shot per verification record.
  Future<List<PoultryPhoto>> photosFor(String recordUuid, {String? kind}) =>
      (database.select(database.poultryPhotos)
            ..where((t) => kind == null
                ? t.recordUuid.equals(recordUuid)
                : t.recordUuid.equals(recordUuid) & t.kind.equals(kind))
            ..orderBy([(t) => OrderingTerm(expression: t.capturedAt)]))
          .get();

  /// Removes a QUID determination and everything captured under it — the
  /// set-up's injectors, the carcasses weighed, its photographs and
  /// signatures. "Abandon Checklist" on the weighing screen, which the
  /// original answers by invalidating the sample and set-up data.
  Future<void> deleteQuidInspection(String uuid) async {
    final photos = await photosFor(uuid);
    final signatures = await signaturesFor(uuid);
    await database.transaction(() async {
      await (database.delete(database.poultryQuidSamples)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.poultryQuidInjectors)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      await (database.delete(database.poultryPhotos)
            ..where((t) => t.recordUuid.equals(uuid)))
          .go();
      await (database.delete(database.poultrySignatures)
            ..where((t) => t.recordUuid.equals(uuid)))
          .go();
      await (database.delete(database.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .go();
    });
    // The files go after the rows: a row that outlives its file is a
    // photograph lost, a file that outlives its row is only space.
    for (final path in [
      for (final p in photos) p.filePath,
      for (final s in signatures) s.filePath,
    ]) {
      if (path.trim().isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Left behind; nothing refers to it any more.
      }
    }
  }

  Future<void> deletePhoto(int id) =>
      (database.delete(database.poultryPhotos)..where((t) => t.id.equals(id)))
          .go();

  /// Records a signature, or that one was refused.
  ///
  /// Upserts on (record, role): a client who re-signs because the first
  /// attempt was unreadable replaces it rather than leaving two.
  Future<void> saveSignature(PoultrySignaturesCompanion row) async {
    final recordUuid = row.recordUuid.value;
    final role = row.role.value;
    await database.transaction(() async {
      await (database.delete(database.poultrySignatures)
            ..where(
              (t) => t.recordUuid.equals(recordUuid) & t.role.equals(role),
            ))
          .go();
      await database.into(database.poultrySignatures).insert(row);
    });
  }

  Future<List<PoultrySignature>> signaturesFor(String recordUuid) =>
      (database.select(database.poultrySignatures)
            ..where((t) => t.recordUuid.equals(recordUuid)))
          .get();

  /// True when [recordUuid] still has photographs or signatures to send.
  ///
  /// Drives the Send button on records whose own upload already succeeded but
  /// whose attachments did not — without this, a failed attachment upload had
  /// no retry path, because Send disappears once the record is marked sent.
  Future<bool> hasPendingEvidenceFor(String recordUuid) async {
    final photos = await photosFor(recordUuid);
    if (photos.any((p) => !p.isUploaded)) return true;
    final signatures = await signaturesFor(recordUuid);
    return signatures.any((s) => !s.isUploaded);
  }

  /// Sends every photograph and signature still pending on [recordUuid].
  ///
  /// Each item is attempted even when an earlier one fails — a dropped
  /// connection mid-way should not stop the attachments after it — and a
  /// single error is thrown at the end so the caller can say "some of the
  /// attachments did not go" rather than silently reporting success.
  Future<void> uploadEvidenceFor(
    String recordUuid, {
    required String token,
  }) async {
    final failures = <Object>[];
    for (final photo in await photosFor(recordUuid)) {
      if (photo.isUploaded) continue;
      // An attachment whose file is gone cannot be sent, and trying costs
      // the whole sync: the server refuses it as "no file was submitted",
      // the attempt is counted a failure, and the same row is tried again
      // on every pass for ever. It is marked done so the queue drains —
      // the photograph is already lost, and saying so once is better than
      // failing the sync until someone notices.
      if (!_hasFile(photo.filePath)) {
        await _markPhotoSent(photo.id);
        continue;
      }
      try {
        await uploadPhoto(photo, token: token);
      } on Object catch (e) {
        failures.add(e);
      }
    }
    for (final signature in await signaturesFor(recordUuid)) {
      if (signature.isUploaded) continue;
      if (!_hasFile(signature.filePath)) {
        await _markSignatureSent(signature.id);
        continue;
      }
      try {
        await uploadSignature(signature, token: token);
      } on Object catch (e) {
        failures.add(e);
      }
    }
    if (failures.isNotEmpty) {
      throw http.ClientException(
        '${failures.length} attachment(s) did not upload; the record itself '
        'is sent. Press Send again to retry them. First error: '
        '${failures.first}',
      );
    }
  }

  /// Whether the attachment still has something to send.
  static bool _hasFile(String path) =>
      path.trim().isNotEmpty && File(path).existsSync();

  Future<void> _markPhotoSent(int id) =>
      (database.update(database.poultryPhotos)..where((t) => t.id.equals(id)))
          .write(const PoultryPhotosCompanion(isUploaded: Value(true)));

  Future<void> _markSignatureSent(int id) =>
      (database.update(database.poultrySignatures)
            ..where((t) => t.id.equals(id)))
          .write(const PoultrySignaturesCompanion(isUploaded: Value(true)));

  /// Sends a photograph. Multipart, and the record need not exist yet.
  Future<void> uploadPhoto(PoultryPhoto photo, {required String token}) async {
    await _upload(
      'photos',
      token: token,
      fields: {
        'record_uuid': photo.recordUuid,
        'kind': photo.kind,
        'caption': photo.caption,
        'captured_at': photo.capturedAt.toUtc().toIso8601String(),
      },
      filePath: photo.filePath,
      fileField: 'image',
      partFilename: 'photo_${photo.kind}.jpg',
    );
    await (database.update(database.poultryPhotos)
          ..where((t) => t.id.equals(photo.id)))
        .write(const PoultryPhotosCompanion(isUploaded: Value(true)));
  }

  Future<void> uploadSignature(
    PoultrySignature signature, {
    required String token,
  }) async {
    await _upload(
      'signatures',
      token: token,
      fields: {
        'record_uuid': signature.recordUuid,
        'role': signature.role,
        'signed_name': signature.signedName,
        'declined': signature.declined.toString(),
        'signed_at': signature.signedAt.toUtc().toIso8601String(),
      },
      // A refusal has no image, and sending an empty part would fail
      // validation on a field that is legitimately blank.
      filePath: signature.declined ? null : signature.filePath,
      fileField: 'image',
      partFilename: 'signature_${signature.role}.png',
    );
    await (database.update(database.poultrySignatures)
          ..where((t) => t.id.equals(signature.id)))
        .write(const PoultrySignaturesCompanion(isUploaded: Value(true)));
  }

  Future<void> _upload(
    String collection, {
    required String token,
    required Map<String, String> fields,
    required String fileField,
    String? filePath,
    String? partFilename,
  }) async {
    final uri = Uri.parse('$baseUrl/api/poultry/$collection/');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);

    if (filePath != null && filePath.isNotEmpty) {
      request.files.add(
        // A short part-filename, whatever the file is called on disk: the
        // server's FileField caps the stored name at 100 characters, and
        // the visit sign-off's copies carry two uuids in theirs.
        await http.MultipartFile.fromPath(fileField, filePath,
            filename: partFilename),
      );
    }

    // Files get far longer than [timeout]: a photo on a slow uplink to the
    // live server took minutes (Ethan, 2026-09-24).
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(minutes: 5)),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw http.ClientException(
        'Upload failed with status ${response.statusCode}: ${response.body}',
        uri,
      );
    }
  }

  // ---------------------------------------------------------------- shared

  Future<void> _post(
    String collection, {
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$baseUrl/api/poultry/$collection/');
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

  static List<int> idsOf(String csv) => [
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ];

  void dispose() => _client.close();
}
