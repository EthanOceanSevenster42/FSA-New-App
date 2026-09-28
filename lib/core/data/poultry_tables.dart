import 'package:drift/drift.dart';

/// Poultry reference data and captured grading inspections.
///
/// Mirrors the backend's `poultry` app. Reference rows keep the server's id as
/// the primary key so a captured inspection can name what it referred to
/// without a second lookup table, and keep `isActive` so a retired row still
/// resolves for work already recorded against it.

class PoultryMeatTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryGrades extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// Null on "Undergrade" and "No Grade" — outcomes rather than tiers.
  IntColumn get rank => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryPortionTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryDesignationClasses extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryAltDesignationClasses extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which grades a designation may carry, for a given meat type.
///
/// Without this the form would offer every grade for every designation, and an
/// inspector could record a combination the original refuses — the record
/// would then disagree with the paper trail it is meant to match.
class PoultryDesignationGradeLinks extends Table {
  IntColumn get id => integer()();
  IntColumn get meatTypeId => integer()();
  IntColumn get designationClassId => integer()();
  IntColumn get gradeId => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryAltDesignationGradeLinks extends Table {
  IntColumn get id => integer()();
  IntColumn get meatTypeId => integer()();
  IntColumn get altDesignationClassId => integer()();
  IntColumn get gradeId => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A tick-box on the grading screen.
///
/// `kind` is one of `grading`, `portion`, `pack`. A TICK MEANS COMPLIANT —
/// the original's column header is "NO Deviation" — so an unticked row is the
/// finding.
class PoultryChecklistItems extends Table {
  IntColumn get id => integer()();
  TextColumn get kind => text()();

  /// The number the original gives the box, so a record captured here lines up
  /// against one captured there.
  IntColumn get originalId => integer()();
  TextColumn get description => text()();
  TextColumn get regulationReference =>
      text().withDefault(const Constant(''))();

  /// Minimum lettering height in millimetres, from the original's "Std (mm)"
  /// column. Text, not a number: many rows state no requirement at all, and 0
  /// would read as "must be at least nothing".
  TextColumn get minLetteringHeight => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryRestrictedParticulars extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get description => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryInspectionReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Where the inspection happens.
///
/// Carries both `name` and `description`. The original seeded ids 5 and 6 with
/// the description "Import" where it meant Producer and Pack House, and the
/// patch that would have fixed it is commented out — so its picker really does
/// show "Import" three times. The data is reproduced as-is; the screen shows
/// `name`, which is unambiguous and invents nothing.
class PoultryInspectionLocations extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get code => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PoultryDirectionRemarks extends Table {
  IntColumn get id => integer()();

  /// Named `remarkText` rather than `text`: a column called `text` collides
  /// with Drift's own `Table.text()` column builder.
  TextColumn get remarkText => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A captured Grading and Classification checklist.
class PoultryInspections extends Table {
  TextColumn get clientUuid => text()();

  /// The store visit this record was captured under, empty when standalone.
  TextColumn get visitUuid => text().withDefault(const Constant(''))();

  /// Who captured it. A shared handset must not show one inspector another's
  /// work, nor upload it under whichever account happens to be signed in.
  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  IntColumn get locationId => integer().nullable()();
  IntColumn get reasonId => integer().nullable()();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityTelephone => text().withDefault(const Constant(''))();
  TextColumn get companyRegNumber => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get contactPersonEmail => text().withDefault(const Constant(''))();
  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();

  /// Two, as the original captures: a direction is commonly copied to a
  /// branch and to head office.
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail2 => text().withDefault(const Constant(''))();

  /// The trading name of a newly met facility, which is not always the
  /// facility name above it.
  TextColumn get producerTradingName =>
      text().withDefault(const Constant(''))();

  /// "New Facility Name" — the original's entry beside the facility picker,
  /// for a site that is not in the directory ("Use for new Facility").
  TextColumn get newFacilityName => text().withDefault(const Constant(''))();

  IntColumn get meatTypeId => integer().nullable()();
  IntColumn get portionTypeId => integer().nullable()();
  IntColumn get designationClassId => integer().nullable()();
  IntColumn get altDesignationClassId => integer().nullable()();
  TextColumn get productDetails => text().withDefault(const Constant(''))();
  TextColumn get sampleNumber => text().withDefault(const Constant(''))();

  IntColumn get gradeId => integer().nullable()();

  /// Comma-separated [PoultryChecklistItems] ids that were ticked, i.e. found
  /// COMPLIANT. Anything active and absent from here is a finding.
  TextColumn get compliantItemIds => text().withDefault(const Constant(''))();

  /// Grading ticks for each carcass, encoded as `1:4,5;2:4`.  The original
  /// grades whole carcass consignments one carcass at a time; the overall
  /// compliant list remains for backwards-compatible reporting.
  TextColumn get gradingBySample => text().withDefault(const Constant(''))();

  TextColumn get restrictedParticularIds =>
      text().withDefault(const Constant(''))();

  TextColumn get inspectionComments => text().withDefault(const Constant(''))();
  TextColumn get directionComments => text().withDefault(const Constant(''))();
  TextColumn get directionRemarks => text().withDefault(const Constant(''))();
  IntColumn get directionRemarkTypeId => integer().nullable()();

  /// 'seize' or 'inspect' once FSA-SOP-APS-001 Annexure C put the seizure
  /// question; empty until.
  TextColumn get seizureDecision => text().withDefault(const Constant(''))();
  BoolColumn get noClientSignaturePresent =>
      boolean().withDefault(const Constant(false))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}
