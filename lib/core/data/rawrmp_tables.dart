import 'package:drift/drift.dart';

/// Certain Raw Processed Meat Products reference data and captured work.
///
/// Mirrors the backend's `rawrmp` app. Reference rows keep the server's id as
/// their primary key and carry `isActive`, so a retired row still resolves for
/// records already written against it. Storage is the one list where
/// `isActive` gates the picker itself: the original seeds "Shelf" inactive
/// and filters it off the screen.

class RawRmpProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpProducers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpStorageTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpLaboratories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get locationDetails => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Category A/B/C. The original's picker shows these bullet-prefixed; the
/// bullet is presentation and added by the screen, not stored.
class RawRmpSampleCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get subCategoryName => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpRestrictedParticulars extends Table {
  IntColumn get id => integer()();
  TextColumn get description => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpDirectionRemarks extends Table {
  IntColumn get id => integer()();
  TextColumn get remarkText => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawRmpInspectionReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Where the inspection happens. Carries both `name` and `description` for
/// the same reason as PMP's: the original's seed gave several rows the
/// description "Import", and the filter's "Importer"/"Pack House" exclusions
/// never fire against them.
class RawRmpInspectionLocations extends Table {
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
class RawRmpChecklistItems extends Table {
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

class RawRmpLabelNonConformances extends Table {
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

/// A captured RawRMP inspection, including its sampling and courier leg.
class RawRmpInspections extends Table {
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

  /// The producer and the product are picked from the directory, or typed as
  /// new — either way what travels is the text.
  TextColumn get producerName => text().withDefault(const Constant(''))();

  /// "New Producer Details" — the free entry beside the picker.
  TextColumn get newProducerDetails => text().withDefault(const Constant(''))();
  TextColumn get productItem => text().withDefault(const Constant(''))();

  /// "New Raw Meat Product Item" — the free entry beside the picker.
  TextColumn get newProductItem => text().withDefault(const Constant(''))();
  TextColumn get batchNumber => text().withDefault(const Constant(''))();
  TextColumn get manufacturedPackedDate =>
      text().withDefault(const Constant(''))();
  IntColumn get storageTypeId => integer().nullable()();

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
  IntColumn get laboratoryId => integer().nullable()();
  TextColumn get internalSampleNumber =>
      text().withDefault(const Constant(''))();
  TextColumn get testSampleSize => text().withDefault(const Constant(''))();

  /// "Primary Sample Size" — the quantity looked at, as the original raw
  /// form asks for it beside the batch (Ethan, 2026-09-24).
  TextColumn get primarySampleSize => text().withDefault(const Constant(''))();
  IntColumn get sampleCategoryId => integer().nullable()();

  /// Every testing category chosen, comma-separated (Ethan, 2026-09-25):
  /// a sample can go for more than one. [sampleCategoryId] keeps the first,
  /// for readers that know only one.
  TextColumn get sampleCategoryIds => text().withDefault(const Constant(''))();

  /// In the original's data model but never on its screen — the entry is
  /// permanently hidden. Carried so nothing is lost if that ever changes.
  TextColumn get dnaSpeciesText => text().withDefault(const Constant(''))();

  /// "Request Calcuim Content Test (for MRM only)" — the original's caption,
  /// typo and all.
  /// The inspector's answer when the product-name row is unticked: was the
  /// name absent altogether (a seizure) or merely deficient (a deviation)?
  BoolColumn get productNameAbsent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get calciumTestRequired =>
      boolean().withDefault(const Constant(false))();

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

  /// "Correct by/on Date" — RawRMP's direction form carries a deadline.
  DateTimeColumn get correctByDate => dateTime().nullable()();
  TextColumn get nonConformanceComments =>
      text().withDefault(const Constant(''))();

  RealColumn get distanceTravelledKm => real().nullable()();
  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  TextColumn get clientEmail2 => text().withDefault(const Constant(''))();
  BoolColumn get noClientSignaturePresent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get generalComments => text().withDefault(const Constant(''))();

  /// SOP-APS-RAW-003, the Compositional Requirements Checklist (Regulation 5
  /// of R.2410): the nine answers as JSON, the comments/actions under them,
  /// and the site representative's position. An FSA addition (2026-08-28) —
  /// the original had no such checklist.
  TextColumn get compositionChecklistJson =>
      text().withDefault(const Constant(''))();
  TextColumn get compositionComments =>
      text().withDefault(const Constant(''))();

  /// `inspection` or `composition` — which record the inspector said this
  /// is when it was started. Empty on records from before the question,
  /// which show both parts. See RawRecordKind.
  TextColumn get recordKind => text().withDefault(const Constant(''))();

  /// What the inspector chose when the findings turned out to require a
  /// seizure: `seize`, or `inspect` to carry on and decide later. Empty
  /// until the question has been put.
  ///
  /// FSA-SOP-APS-001 makes a seizure a different outcome from a rejection,
  /// not a harder one — an omitted product name or grade designation is
  /// seized under s.8 rather than given a rectification period. The choice
  /// is the inspector's to make on the premises, so it is recorded with the
  /// record that prompted it rather than inferred later by the office.
  TextColumn get seizureDecision => text().withDefault(const Constant(''))();

  TextColumn get representativePosition =>
      text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

/// A direction served on a client.
class RawRmpDirections extends Table {
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

  /// The number the direction is known by, generated when it is raised.
  ///
  /// `client / inspector id / date / nn`, where nn counts the
  /// directions this inspector has raised today — the original's
  /// `UniqueReferenceNumber`. The office quotes it back, so it is written
  /// once and never renumbered when the direction is refreshed.
  TextColumn get referenceNumber => text().withDefault(const Constant(''))();

  /// The deadline on the notice. It is captured on the inspection and
  /// copied here, because the notice is what the client is served with and
  /// the office reads the date off the direction.
  DateTimeColumn get correctByDate => dateTime().nullable()();

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
