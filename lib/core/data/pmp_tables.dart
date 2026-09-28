import 'package:drift/drift.dart';

/// Processed Meat Product reference data and captured work.
///
/// Mirrors the backend's `pmp` app. Reference rows keep the server's id as
/// their primary key and carry `isActive`, so a retired row still resolves for
/// records already written against it.

class PmpProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// Pack weight and the minimum sample the laboratory needs — the product
  /// carries its own sampling arithmetic in the original.
  IntColumn get weightGrams => integer().nullable()();
  IntColumn get minSampleQuantity => integer().nullable()();
  TextColumn get producerName => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Producers of processed meat products. The original seeds none — the list
/// is filled by server sync — so this starts empty too.
class PmpProducers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpSubClassProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpStorageTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpIngredients extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpLaboratories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get locationDetails => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpRestrictedParticulars extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get description => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpDirectionRemarks extends Table {
  IntColumn get id => integer()();
  TextColumn get remarkText => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpInspectionReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Where the inspection happens. Carries both `name` and `description` for
/// the same reason as poultry's: the original's seed gave ids 5 and 6 the
/// description "Import", and the PMP filter's "Importer"/"Pack House"
/// exclusions never fire against them.
class PmpInspectionLocations extends Table {
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

/// One tick-box on the inspection screen.
///
/// `section` is `marking`, `scale`, `container`, `fridge` or `notice` — the
/// five blocks the screen gates behind "... Present" switches. A TICK MEANS
/// COMPLIANT, and a section that is not present contributes nothing.
class PmpChecklistItems extends Table {
  IntColumn get id => integer()();
  TextColumn get section => text()();
  IntColumn get originalId => integer()();
  TextColumn get description => text()();
  TextColumn get regulationReference =>
      text().withDefault(const Constant(''))();
  TextColumn get minLetteringHeight => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class PmpLabelNonConformances extends Table {
  IntColumn get id => integer()();
  IntColumn get markedNumber => integer().nullable()();
  TextColumn get description => text()();
  TextColumn get regulationReference =>
      text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A captured PMP inspection, including its sampling and courier leg.
class PmpInspections extends Table {
  TextColumn get clientUuid => text()();

  /// The grouped inspection this record was captured under, empty when
  /// standalone. The closing signatures find their members through this.
  TextColumn get visitUuid => text().withDefault(const Constant(''))();
  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  IntColumn get locationId => integer().nullable()();
  IntColumn get reasonId => integer().nullable()();
  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get producerTradingName =>
      text().withDefault(const Constant(''))();

  /// "New Facility Name" — the original's entry beside the facility picker,
  /// for a site that is not in the directory ("Use for new Facility"). Its
  /// NewClientName.
  TextColumn get newFacilityName => text().withDefault(const Constant(''))();

  /// "New PMP Item Size (g)" and "New PMP Item Barcode" — the particulars of
  /// an item being added from the screen, which the original captures
  /// alongside the new item's name.
  TextColumn get newItemSizeG => text().withDefault(const Constant(''))();
  TextColumn get newItemBarcode => text().withDefault(const Constant(''))();

  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityTelephone => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get contactPersonEmail => text().withDefault(const Constant(''))();
  TextColumn get followUpDirectionParticulars =>
      text().withDefault(const Constant(''))();

  TextColumn get producerName => text().withDefault(const Constant(''))();

  /// "New Producer Details" — the free entry beside the picker.
  TextColumn get newProducerDetails => text().withDefault(const Constant(''))();
  TextColumn get productItem => text().withDefault(const Constant(''))();

  /// "New Processed Meat Item" — the free entry beside the picker.
  TextColumn get newProductItem => text().withDefault(const Constant(''))();
  TextColumn get batchNumber => text().withDefault(const Constant(''))();

  /// Text, not a date: what is printed on a pack ("12/2025", "JUL 25 B4") is
  /// not always a date, and the original's field is a free entry.
  TextColumn get manufacturedPackedDate =>
      text().withDefault(const Constant(''))();
  IntColumn get storageTypeId => integer().nullable()();
  TextColumn get primarySampleSize => text().withDefault(const Constant(''))();

  BoolColumn get markingLabelsPresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get scaleLabelsPresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get containersPresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get displayFridgePresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get noticeBoardsPresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get compliantItemIds => text().withDefault(const Constant(''))();

  BoolColumn get restrictedParticularsPresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get restrictedParticularIds =>
      text().withDefault(const Constant(''))();
  TextColumn get restrictedParticularsText =>
      text().withDefault(const Constant(''))();
  BoolColumn get labelPackComplete =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get isSampled => boolean().withDefault(const Constant(false))();
  BoolColumn get recipeAvailable =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get recipeComplete =>
      boolean().withDefault(const Constant(false))();
  IntColumn get subClassProductId => integer().nullable()();
  IntColumn get ingredientId => integer().nullable()();
  TextColumn get newIngredient => text().withDefault(const Constant(''))();

  /// "Ingredient Percentage (%)" — the recipe the inspector builds row by
  /// row, serialised one ingredient per line as "<n>. <description> <pct>%".
  TextColumn get ingredientPercentages =>
      text().withDefault(const Constant(''))();
  IntColumn get laboratoryId => integer().nullable()();
  TextColumn get internalSampleNumber =>
      text().withDefault(const Constant(''))();
  TextColumn get testSampleSize => text().withDefault(const Constant(''))();

  /// The original's field is named IsCouriered but captioned "Hand
  /// Delivered" — kept exactly as they are, disagreement included, because
  /// the Pending Courier screen filters on the field.
  BoolColumn get isCouriered => boolean().withDefault(const Constant(false))();
  BoolColumn get labInfoComplete =>
      boolean().withDefault(const Constant(false))();

  /// A couriered sample is not finished until this arrives.
  TextColumn get waybill => text().withDefault(const Constant(''))();

  IntColumn get directionRemarkTypeId => integer().nullable()();
  TextColumn get directionRemarks => text().withDefault(const Constant(''))();

  /// "Correct by/on Date" — the deadline the direction sets.
  DateTimeColumn get correctByDate => dateTime().nullable()();

  /// The inspector's answer when the product-name row is unticked: was the
  /// name absent altogether (a seizure under FSA-SOP-APS-001 Annexure B)
  /// or merely deficient (a 30-day rectification)?
  BoolColumn get productNameAbsent =>
      boolean().withDefault(const Constant(false))();

  /// What the inspector chose when the findings required a seizure:
  /// "seize", "inspect", or empty when the question never arose.
  TextColumn get seizureDecision => text().withDefault(const Constant(''))();
  TextColumn get nonConformanceComments =>
      text().withDefault(const Constant(''))();

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

/// A direction served on a client.
class PmpDirections extends Table {
  TextColumn get clientUuid => text()();
  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get issuedAt => dateTime()();

  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  IntColumn get remarkTypeId => integer().nullable()();
  TextColumn get remarks => text().withDefault(const Constant(''))();
  TextColumn get comments => text().withDefault(const Constant(''))();
  TextColumn get actionTaken => text().withDefault(const Constant(''))();
  TextColumn get nonConformanceIds => text().withDefault(const Constant(''))();

  /// The inspection this direction was raised from. The original creates the
  /// direction inside the inspection save and links it back; the summary's
  /// photographs are the inspection's photographs.
  TextColumn get sourceInspectionUuid => text().nullable()();
  TextColumn get newFacilityName => text().withDefault(const Constant(''))();
  TextColumn get producerName => text().withDefault(const Constant(''))();
  TextColumn get newProducerName => text().withDefault(const Constant(''))();
  TextColumn get batchNumber => text().withDefault(const Constant(''))();
  TextColumn get manufacturedPackedDate =>
      text().withDefault(const Constant(''))();
  TextColumn get primarySampleSize => text().withDefault(const Constant(''))();
  TextColumn get restrictedParticularIds =>
      text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}
