import 'package:drift/drift.dart';

/// A seizure served under section 8 of the APS Act — FSA-SOP-APS-001
/// Annexure E, the Department's standard seizure document.
///
/// One row per inspection record it was raised off, whatever the commodity:
/// the paper form is the same for eggs, poultry and both meat products, so
/// the record is too. It carries everything the sheet prints — the client's
/// particulars, the product, the deviation and the receiver — as they stood
/// when the inspector chose to seize, so the document reads the same
/// afterwards as it did on the premises.
class Seizures extends Table {
  TextColumn get clientUuid => text()();

  /// The inspection this seizure was raised off, and which register it
  /// sits in: 'egg', 'pmp', 'rawrmp', 'poultry', 'poultry_label', 'quid'.
  TextColumn get recordUuid => text()();
  TextColumn get recordKind => text()();

  /// The store visit the record was captured under, empty when standalone.
  TextColumn get visitUuid => text().withDefault(const Constant(''))();
  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();
  DateTimeColumn get issuedAt => dateTime()();

  // --- Particulars of the client or owner of the consignment
  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get clientAddress => text().withDefault(const Constant(''))();
  TextColumn get clientTelephone => text().withDefault(const Constant(''))();
  TextColumn get clientFax => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();

  /// "Inspection Point" — where on the premises: the butchery, the shelf.
  TextColumn get inspectionPoint => text().withDefault(const Constant(''))();

  // --- The product seized
  TextColumn get productName => text().withDefault(const Constant(''))();
  TextColumn get productClass => text().withDefault(const Constant(''))();
  TextColumn get quantity => text().withDefault(const Constant(''))();
  TextColumn get regulation => text().withDefault(const Constant(''))();
  TextColumn get natureOfDeviation => text().withDefault(const Constant(''))();

  /// "Corrective actions: period and kind of treatment as per section
  /// 8(3)". An immediate seizure is exactly that.
  TextColumn get correctiveAction =>
      text().withDefault(const Constant('Immediate'))();
  TextColumn get remarks => text().withDefault(const Constant(''))();

  // --- Acknowledgement of receipt
  TextColumn get receiverName => text().withDefault(const Constant(''))();
  TextColumn get receiverIdNumber => text().withDefault(const Constant(''))();
  TextColumn get receiverDesignation =>
      text().withDefault(const Constant(''))();

  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}
