import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/data/local_database.dart';
import '../../../core/documents/seizure_pdf.dart';

/// The seizures served from this handset, and the document each one prints
/// to — FSA-SOP-APS-001 Annexure E.
///
/// Shared by every commodity: the paper form is the same whatever was
/// seized, so one register and one sheet serve eggs, poultry and both meat
/// products rather than four copies of each.
class SeizureRepository {
  SeizureRepository({required this.database});

  final LocalDatabase database;

  /// Records a seizure against an inspection, replacing any earlier one on
  /// the same record: a consignment is seized once.
  Future<void> record(SeizuresCompanion row) async {
    await (database.delete(database.seizures)
          ..where((t) => t.recordUuid.equals(row.recordUuid.value)))
        .go();
    await database.into(database.seizures).insert(row);
  }

  Future<Seizure?> forRecord(String recordUuid) =>
      (database.select(database.seizures)
            ..where((t) => t.recordUuid.equals(recordUuid)))
          .getSingleOrNull();

  /// The seizure on [recordUuid] as it reads now — see [current].
  Future<Seizure?> currentForRecord(String recordUuid) async {
    final s = await forRecord(recordUuid);
    return s == null ? null : current(s);
  }

  /// The seizure with the client's particulars as the record holds them
  /// today, not as they stood when the inspector chose to seize.
  ///
  /// The seizure used to keep its own copy of the facility name, address,
  /// telephone and e-mail, taken at that moment, so a visit corrected
  /// afterwards still printed the old details on the sheet (Ethan,
  /// 2026-09-29). They are read from the visit — or, for a record captured
  /// outside a visit, from the record itself — and the copy is only the
  /// fallback. What was seized, how much and who took receipt stay the
  /// seizure's own: those are changed with [updateParticulars].
  Future<Seizure> current(Seizure s) async {
    String pick(String live, String kept) =>
        live.trim().isNotEmpty ? live.trim() : kept;
    if (s.visitUuid.isNotEmpty) {
      final v = await (database.select(database.storeVisits)
            ..where((t) => t.uuid.equals(s.visitUuid)))
          .getSingleOrNull();
      if (v != null) {
        return s.copyWith(
          clientName: pick(v.facilityName, s.clientName),
          clientAddress: pick(v.facilityAddress, s.clientAddress),
          clientTelephone: pick(v.facilityPhone, s.clientTelephone),
          clientEmail: pick(v.contactEmail, s.clientEmail),
          inspectionPoint: pick(v.facilityType, s.inspectionPoint),
        );
      }
    }
    final live = await _recordFacility(s);
    if (live == null) return s;
    return s.copyWith(
      clientName: pick(live.name, s.clientName),
      clientAddress: pick(live.address, s.clientAddress),
      clientTelephone: pick(live.phone, s.clientTelephone),
      clientEmail: pick(live.email, s.clientEmail),
    );
  }

  /// The facility as the record the seizure was raised off holds it.
  Future<({String name, String address, String phone, String email})?>
      _recordFacility(Seizure s) async {
    final id = s.recordUuid;
    switch (s.recordKind) {
      case 'egg':
        final r = await (database.select(database.eggInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityPhone,
                email: r.clientEmail,
              );
      case 'rawrmp':
        final r = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityTelephone,
                email: r.contactPersonEmail,
              );
      case 'pmp':
        final r = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityTelephone,
                email: r.contactPersonEmail,
              );
      case 'poultry':
        final r = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityTelephone,
                email: r.contactPersonEmail,
              );
      case 'poultry_label':
        final r = await (database.select(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityTelephone,
                email: r.contactPersonEmail,
              );
      case 'quid':
        final r = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(id)))
            .getSingleOrNull();
        return r == null
            ? null
            : (
                name: r.facilityName,
                address: r.facilityAddress,
                phone: r.facilityTelephone,
                email: r.contactPersonEmail,
              );
    }
    return null;
  }

  /// Changes what was seized, how much, and who took receipt — the answers
  /// only the inspector can give, corrected after the fact. The seizure is
  /// marked as changed so the next sync sends it again.
  Future<void> updateParticulars(
    Seizure s, {
    required String productName,
    required String productClass,
    required String quantity,
    required String remarks,
    required String receiverName,
    required String receiverIdNumber,
    required String receiverDesignation,
  }) =>
      (database.update(database.seizures)
            ..where((t) => t.clientUuid.equals(s.clientUuid)))
          .write(SeizuresCompanion(
        productName: Value(productName.trim()),
        productClass: Value(productClass.trim()),
        quantity: Value(quantity.trim()),
        remarks: Value(remarks.trim()),
        receiverName: Value(receiverName.trim()),
        receiverIdNumber: Value(receiverIdNumber.trim()),
        receiverDesignation: Value(receiverDesignation.trim()),
        isUploaded: const Value(false),
        updatedAt: Value(DateTime.now()),
      ));

  Future<List<Seizure>> forVisit(String visitUuid) =>
      (database.select(database.seizures)
            ..where((t) => t.visitUuid.equals(visitUuid)))
          .get();

  /// The seizures raised off any of [recordUuids].
  Future<List<Seizure>> forRecords(Iterable<String> recordUuids) async {
    final ids = recordUuids.toList();
    if (ids.isEmpty) return const [];
    return (database.select(database.seizures)
          ..where((t) => t.recordUuid.isIn(ids)))
        .get();
  }

  /// A seizure as the server takes it, and gives it back.
  static Map<String, Object?> toJson(Seizure s) => {
        'client_uuid': s.clientUuid,
        'record_uuid': s.recordUuid,
        'record_kind': s.recordKind,
        'issued_at': s.issuedAt.toUtc().toIso8601String(),
        'client_name': s.clientName,
        'client_address': s.clientAddress,
        'client_telephone': s.clientTelephone,
        'client_fax': s.clientFax,
        'client_email': s.clientEmail,
        'inspection_point': s.inspectionPoint,
        'product_name': s.productName,
        'product_class': s.productClass,
        'quantity': s.quantity,
        'regulation': s.regulation,
        'nature_of_deviation': s.natureOfDeviation,
        'corrective_action': s.correctiveAction,
        'remarks': s.remarks,
        'receiver_name': s.receiverName,
        'receiver_id_number': s.receiverIdNumber,
        'receiver_designation': s.receiverDesignation,
      };

  /// Which of [recordUuids] had their consignment seized — one read for a
  /// whole visit, so a list of visits does not query record by record.
  Future<Set<String>> seizedAmong(Iterable<String> recordUuids) async {
    final ids = recordUuids.toList();
    if (ids.isEmpty) return const {};
    final rows = await (database.select(database.seizures)
          ..where((t) => t.recordUuid.isIn(ids)))
        .get();
    return {for (final r in rows) r.recordUuid};
  }

  /// The seizure as the record pages show it, label beside value, in the
  /// order the Annexure E sheet prints it.
  static List<(String, String)> rowsFor(Seizure s) {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = s.issuedAt;
    return [
      ('Issued', '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}'),
      ('Product', s.productName),
      ('Product class', s.productClass),
      ('Quantity seized', s.quantity),
      ('Applicable regulation', s.regulation),
      ('Nature of deviation', s.natureOfDeviation),
      ('Corrective action', s.correctiveAction),
      ('Remarks', s.remarks),
      ('Received by', s.receiverName),
      ('Receiver ID number', s.receiverIdNumber),
      ('Receiver designation', s.receiverDesignation),
    ];
  }

  Future<int> pendingCount() async => (await (database.select(database.seizures)
            ..where((t) => t.isUploaded.equals(false)))
          .get())
      .length;

  Future<void> markUploaded(String clientUuid) =>
      (database.update(database.seizures)
            ..where((t) => t.clientUuid.equals(clientUuid)))
          .write(const SeizuresCompanion(isUploaded: Value(true)));

  /// The seizure document for [recordUuid], or null when nothing was
  /// seized off that record.
  ///
  /// The signatures are the visit's own: at sign-off the manager's and the
  /// inspector's are stamped onto every member record, and the seizure
  /// reads them off the record it was raised from — the inspector's under
  /// "Issued", the manager's under "Acknowledgement of receipt".
  Future<File?> buildDocument(String recordUuid, {Directory? into}) async {
    final s = await currentForRecord(recordUuid);
    if (s == null) return null;
    final signatures = await _signatures(s);
    final user = await database.findUser(s.inspectorUsername);
    final full =
        user == null ? '' : '${user.firstName} ${user.lastName}'.trim();
    return SeizurePdf.write(
      out: documentFile(s, into),
      clientName: s.clientName,
      clientAddress: s.clientAddress,
      clientTelephone: s.clientTelephone,
      clientFax: s.clientFax,
      clientEmail: s.clientEmail,
      inspectionPoint: s.inspectionPoint,
      products: [
        SeizedProduct(
          productName: s.productName,
          productClass: s.productClass,
          quantity: s.quantity,
          regulation: s.regulation,
          natureOfDeviation: s.natureOfDeviation,
          correctiveAction: s.correctiveAction,
          remarks: s.remarks,
        ),
      ],
      issuedAt: s.issuedAt,
      issuedPlace: s.clientName,
      inspectorName: full.isEmpty ? s.inspectorUsername : full,
      inspectorSignaturePath: signatures.inspector,
      receiverName:
          s.receiverName.isNotEmpty ? s.receiverName : signatures.clientName,
      receiverIdNumber: s.receiverIdNumber,
      receiverDesignation: s.receiverDesignation,
      receiverSignaturePath: signatures.client,
      receivedAt: signatures.signedAt ?? s.issuedAt,
    );
  }

  /// Where the sheet is written: the Agency's naming, keyed on the record
  /// so two seizures on one visit do not overwrite each other.
  File documentFile(Seizure s, Directory? into) {
    final dir = into ?? Directory.systemTemp;
    final short = s.recordUuid.length < 8
        ? s.recordUuid
        : s.recordUuid.substring(0, 8);
    final slug = s.clientName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return File('${dir.path}/FSA-$slug-Seizure-$short.pdf');
  }

  /// The signatures on the record the seizure was raised off. Eggs keep
  /// theirs in their own table; every other commodity shares the poultry
  /// evidence store.
  Future<({String inspector, String client, String clientName, DateTime? signedAt})>
      _signatures(Seizure s) async {
    if (s.recordKind == 'egg') {
      final rows = await (database.select(database.eggSignatures)
            ..where((t) => t.inspectionUuid.equals(s.recordUuid)))
          .get();
      String pathOf(String role) => rows
          .where(
              (r) => r.role == role && !r.declined && r.filePath.isNotEmpty)
          .map((r) => r.filePath)
          .firstWhere((_) => true, orElse: () => '');
      final client = rows.where((r) => r.role == 'client').toList();
      return (
        inspector: pathOf('inspector'),
        client: pathOf('client'),
        clientName: client.isEmpty ? '' : client.first.signedName,
        signedAt: client.isEmpty ? null : client.first.signedAt,
      );
    }
    final rows = await (database.select(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(s.recordUuid)))
        .get();
    String pathOf(String role) => rows
        .where((r) => r.role == role && !r.declined && r.filePath.isNotEmpty)
        .map((r) => r.filePath)
        .firstWhere((_) => true, orElse: () => '');
    final client = rows.where((r) => r.role == 'client').toList();
    return (
      inspector: pathOf('inspector'),
      client: pathOf('client'),
      clientName: client.isEmpty ? '' : client.first.signedName,
      signedAt: client.isEmpty ? null : client.first.signedAt,
    );
  }
}
