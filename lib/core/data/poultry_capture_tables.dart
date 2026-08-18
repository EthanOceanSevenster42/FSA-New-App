import 'package:drift/drift.dart';

/// The rest of the poultry module's captured work.
///
/// Kept beside `poultry_tables.dart` rather than inside it: that file is the
/// reference data plus the grading inspection, and this one is the three
/// records the other screens produce. One file for all of it would be a
/// thousand lines before the first screen was written.

/// A captured Label/Container Checklist.
class PoultryLabelInspections extends Table {
  TextColumn get clientUuid => text()();
  TextColumn get inspectorUsername =>
      text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  IntColumn get locationId => integer().nullable()();
  IntColumn get reasonId => integer().nullable()();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get producerTradingName =>
      text().withDefault(const Constant(''))();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityTelephone => text().withDefault(const Constant(''))();
  TextColumn get registrationNumber =>
      text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get contactPersonEmail =>
      text().withDefault(const Constant(''))();
  TextColumn get productDetails => text().withDefault(const Constant(''))();
  TextColumn get selectedDirectionForFollowup =>
      text().withDefault(const Constant(''))();

  IntColumn get meatTypeId => integer().nullable()();
  IntColumn get portionTypeId => integer().nullable()();
  IntColumn get designationClassId => integer().nullable()();
  IntColumn get altDesignationClassId => integer().nullable()();
  IntColumn get gradeId => integer().nullable()();
  TextColumn get sampleNumber => text().withDefault(const Constant(''))();

  /// Whether the consignment carries an outer container label at all. With
  /// none, the outer lettering rows do not apply and are not findings — which
  /// is different from failing them.
  BoolColumn get outerLabelsPresent =>
      boolean().withDefault(const Constant(false))();

  TextColumn get compliantItemIds => text().withDefault(const Constant(''))();
  TextColumn get restrictedParticularIds =>
      text().withDefault(const Constant(''))();
  TextColumn get restrictedParticularsText =>
      text().withDefault(const Constant(''))();

  TextColumn get nonConformanceComments =>
      text().withDefault(const Constant(''))();
  TextColumn get directionRemarks => text().withDefault(const Constant(''))();
  IntColumn get directionRemarkTypeId => integer().nullable()();

  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail2 => text().withDefault(const Constant(''))();
  BoolColumn get noClientSignaturePresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get generalComments => text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

/// A QUID checklist — set up on one screen, continued on another.
///
/// One row, not two. The original's "Continue with QUID Checklist" reopens the
/// same inspection, and splitting it here would let the halves drift apart.
class PoultryQuidInspections extends Table {
  TextColumn get clientUuid => text()();
  TextColumn get inspectorUsername =>
      text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  IntColumn get locationId => integer().nullable()();
  IntColumn get reasonId => integer().nullable()();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get producerTradingName =>
      text().withDefault(const Constant(''))();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityTelephone => text().withDefault(const Constant(''))();
  TextColumn get companyRegNumber => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get contactPersonEmail =>
      text().withDefault(const Constant(''))();
  TextColumn get productDetails => text().withDefault(const Constant(''))();

  BoolColumn get isWaterChilled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isWholeCarcass =>
      boolean().withDefault(const Constant(false))();
  TextColumn get injectorName => text().withDefault(const Constant(''))();
  BoolColumn get isRegulatedStandard =>
      boolean().withDefault(const Constant(false))();
  TextColumn get dispensationQuidPercent =>
      text().withDefault(const Constant(''))();
  BoolColumn get setupComplete =>
      boolean().withDefault(const Constant(false))();

  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get iterationNumber => text().withDefault(const Constant(''))();
  TextColumn get averageWaterChillPickup =>
      text().withDefault(const Constant(''))();
  BoolColumn get waterChillingComplete =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get airChillingComplete =>
      boolean().withDefault(const Constant(false))();
  TextColumn get averageInjectorPickup =>
      text().withDefault(const Constant(''))();
  BoolColumn get injectorSamplingComplete =>
      boolean().withDefault(const Constant(false))();

  TextColumn get quidInitialMassG => text().withDefault(const Constant(''))();
  TextColumn get quidAfterMassG => text().withDefault(const Constant(''))();
  TextColumn get quidGainMassG => text().withDefault(const Constant(''))();
  TextColumn get quidPercent => text().withDefault(const Constant(''))();
  BoolColumn get quidDeterminationComplete =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get repeatQuidDetermination =>
      boolean().withDefault(const Constant(false))();
  TextColumn get setInjectorQuidPercent =>
      text().withDefault(const Constant(''))();

  TextColumn get documentName => text().withDefault(const Constant(''))();
  BoolColumn get documentVerified =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get documentDeviationPresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get documentDeviationComment =>
      text().withDefault(const Constant(''))();

  IntColumn get directionRemarkTypeId => integer().nullable()();
  TextColumn get directionRemarks => text().withDefault(const Constant(''))();
  TextColumn get directionAction => text().withDefault(const Constant(''))();

  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail2 => text().withDefault(const Constant(''))();
  BoolColumn get noClientSignaturePresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get generalComments => text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

/// One carcass weighed through the QUID process.
///
/// Masses are stored as entered rather than as a computed percentage: the
/// original shows the inspector the arithmetic, and a percentage with no
/// masses behind it cannot be checked afterwards.
class PoultryQuidSamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();
  TextColumn get carcassNumber => text().withDefault(const Constant(''))();
  TextColumn get injectorNumber => text().withDefault(const Constant(''))();
  TextColumn get initialMassG => text().withDefault(const Constant(''))();
  TextColumn get afterMassG => text().withDefault(const Constant(''))();
  TextColumn get finalMassG => text().withDefault(const Constant(''))();
  TextColumn get pickupPercent => text().withDefault(const Constant(''))();
}

/// A direction served on a client.
///
/// Recorded in its own right rather than as a field on an inspection: the
/// original's Direction Management screen lists directions by date,
/// independently of which inspection produced them.
class PoultryDirections extends Table {
  TextColumn get clientUuid => text()();
  TextColumn get inspectorUsername =>
      text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get issuedAt => dateTime()();

  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  IntColumn get remarkTypeId => integer().nullable()();
  TextColumn get remarks => text().withDefault(const Constant(''))();
  TextColumn get comments => text().withDefault(const Constant(''))();
  TextColumn get actionTaken => text().withDefault(const Constant(''))();

  /// Which non-conformances this direction cites, comma separated.
  TextColumn get nonConformanceIds =>
      text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

/// A photograph attached to any poultry record.
///
/// Keyed on the record's uuid plus a kind rather than a foreign key to one
/// inspection type — the original has a single photo table with a kind, and
/// three near-identical tables here would need three sync paths to say the
/// same thing.
class PoultryPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordUuid => text()();

  /// `label`, `grading` or `quid` — which screen took it.
  TextColumn get kind => text()();
  TextColumn get filePath => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}

/// A signature captured against a poultry record.
///
/// One row per role per record. "No Client Signature" is itself a role in the
/// original rather than an absence, so a refusal is recorded rather than left
/// as a missing row — otherwise it cannot be told apart from an inspection
/// nobody finished.
class PoultrySignatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordUuid => text()();
  TextColumn get role => text()();
  TextColumn get signedName => text().withDefault(const Constant(''))();

  /// Empty when [declined] — there is no image to store for a refusal.
  TextColumn get filePath => text().withDefault(const Constant(''))();
  BoolColumn get declined => boolean().withDefault(const Constant(false))();
  DateTimeColumn get signedAt => dateTime()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}
