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

  Future<List<Seizure>> forVisit(String visitUuid) =>
      (database.select(database.seizures)
            ..where((t) => t.visitUuid.equals(visitUuid)))
          .get();

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
    final s = await forRecord(recordUuid);
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
