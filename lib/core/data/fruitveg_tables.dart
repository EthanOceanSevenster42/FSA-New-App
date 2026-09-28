import 'package:drift/drift.dart';

/// Fruit & Vegetable reference data, mirrored from the server so inspections
/// can be captured and graded with no signal.
///
/// Every table carries `updatedAt` so one delta-sync mechanism covers them all.

class FvCommodityGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvCommodities extends Table {
  IntColumn get id => integer()();
  IntColumn get groupId => integer()();
  TextColumn get name => text()();
  BoolColumn get requiresBrix => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvCultivars extends Table {
  IntColumn get id => integer()();
  IntColumn get commodityId => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvCountries extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvGrades extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// 1 is the best class; the overall result takes the worst rank.
  IntColumn get rank => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvDefectGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// Internal defects are weighed; external ones counted.
  BoolColumn get isInternal => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvSubDefects extends Table {
  IntColumn get id => integer()();
  IntColumn get groupId => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The grading rule: max share of the sample a class tolerates for a defect
/// group on a commodity. This is the whole rule engine, as data.
class FvTolerances extends Table {
  IntColumn get id => integer()();
  IntColumn get commodityId => integer()();
  IntColumn get defectGroupId => integer()();
  IntColumn get gradeId => integer()();
  RealColumn get maxPercentage => real()();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvRequirements extends Table {
  IntColumn get id => integer()();

  /// 'marking' or 'packing'.
  TextColumn get kind => text()();
  TextColumn get description => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class FvInspectionPoints extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Captured inspections (local, pending upload)
// ---------------------------------------------------------------------------

class FvInspections extends Table {
  /// Generated on the device. Also the server-side idempotency key, so a
  /// retried upload updates rather than duplicates.
  TextColumn get clientUuid => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  IntColumn get inspectionPointId => integer().nullable()();
  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get clientAddress => text().withDefault(const Constant(''))();
  TextColumn get clientContactPerson =>
      text().withDefault(const Constant(''))();
  TextColumn get clientContactNumber =>
      text().withDefault(const Constant(''))();
  TextColumn get marketPlace => text().withDefault(const Constant(''))();

  IntColumn get commodityId => integer()();
  IntColumn get cultivarId => integer().nullable()();
  IntColumn get countryId => integer().nullable()();
  TextColumn get consignmentDescription =>
      text().withDefault(const Constant(''))();
  TextColumn get containerNumbers => text().withDefault(const Constant(''))();
  TextColumn get barcode => text().withDefault(const Constant(''))();
  TextColumn get grnVoucher => text().withDefault(const Constant(''))();
  TextColumn get billOfEntry => text().withDefault(const Constant(''))();

  RealColumn get sampleWeightKg => real().nullable()();
  RealColumn get markedContainerWeightKg => real().nullable()();
  IntColumn get markedGradeId => integer().nullable()();
  RealColumn get brixReading => real().nullable()();

  IntColumn get determinedGradeId => integer().nullable()();
  BoolColumn get gradeOverridden =>
      boolean().withDefault(const Constant(false))();
  TextColumn get overrideReason => text().withDefault(const Constant(''))();
  TextColumn get remarks => text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// Comma-separated requirement ids that failed.
  TextColumn get failedRequirementIds =>
      text().withDefault(const Constant(''))();

  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

class FvInspectionDefects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();
  IntColumn get defectGroupId => integer()();
  IntColumn get subDefectId => integer().nullable()();
  IntColumn get count => integer().nullable()();
  RealColumn get weightG => real().nullable()();
  RealColumn get percentage => real().nullable()();
}

class FvInspectionPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();

  /// 'grn' | 'label' | 'gps' | 'defect'
  TextColumn get kind => text()();

  /// Absolute path on the device. Images stay on disk, never in the database.
  TextColumn get filePath => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}
