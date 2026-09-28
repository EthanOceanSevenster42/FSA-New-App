import 'package:drift/drift.dart';

/// Poultry Egg reference data and captured inspections.
///
/// Unlike Fruit & Veg, egg inspection records INDIVIDUAL EGGS — each with its
/// own mass, size, grade, Haugh reading and set of deviations. `EggSamples`
/// and `EggSampleDeviations` carry that structure.

class EggSizes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  RealColumn get minMassG => real()();

  /// Null on the open-topped band (Jumbo).
  RealColumn get maxMassG => real().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// False for a size declared on the pack that is not a mass an individual
  /// egg can fall into - "Mixed Size" describes an assorted consignment.
  /// [EggRules.sizeFor] skips these, so a reading can never derive one.
  BoolColumn get isMassBand => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggGrades extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get rank => integer()();
  TextColumn get description => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggDeviationCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggDeviations extends Table {
  IntColumn get id => integer()();
  IntColumn get categoryId => integer()();
  TextColumn get description => text()();

  /// Grade this deviation forces. Null = recorded but not grade-affecting.
  IntColumn get downgradesToGradeId => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// How many eggs may show a deviation before the consignment is a finding.
///
/// Keyed on the deviation together with the size and grade the consignment is
/// *declared* as. Held on the device because whether a direction must be served
/// has to be answerable with no signal, standing at the consignment.
///
/// A combination with no row has no tolerance: one affected egg is a finding.
class EggDeviationTolerances extends Table {
  IntColumn get id => integer()();
  IntColumn get deviationId => integer()();
  IntColumn get sizeId => integer()();
  IntColumn get gradeId => integer()();
  IntColumn get minimum => integer().withDefault(const Constant(0))();
  IntColumn get maximum => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggRequirements extends Table {
  IntColumn get id => integer()();

  /// 'label_pack' | 'label_outer' | 'packing'
  TextColumn get kind => text()();
  TextColumn get description => text()();

  /// What the original's own screen calls this row.
  ///
  /// The original words each checklist row twice: the XAML label an inspector
  /// reads, and the description its direction and report print. They differ —
  /// the description prefixes the container and spells several words
  /// differently. Empty falls back to [description].
  TextColumn get screenLabel => text().withDefault(const Constant(''))();

  /// The original's own list order, which is not alphabetical.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get regulation => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggRestrictedParticulars extends Table {
  IntColumn get id => integer()();
  TextColumn get keyword => text()();

  /// The original's own list order, which is not alphabetical.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggTraySizes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get eggCount => integer()();

  /// Seed order, not numeric — the original lists 15-Pack last.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggFacilityTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// The original lists these in its own seed order, not alphabetically.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Named premises, so an inspector picks a facility instead of retyping its
/// name, type, address and telephone at every visit.
class EggFacilities extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  IntColumn get facilityTypeId => integer().nullable()();
  TextColumn get physicalAddress => text().withDefault(const Constant(''))();
  TextColumn get telephone => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggInspectionReasons extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  /// The original's own list order, which is not alphabetical.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Clients synced from the server, so an inspector picks one instead of
/// retyping a name, address and telephone at every consignment.
class EggClients extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get tradingName => text().withDefault(const Constant(''))();
  TextColumn get physicalAddress => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get telephone => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  BoolColumn get isRegistered => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A producer or packer eggs were supplied by.
///
/// Captured as free text until now, so the same farm was spelled three ways
/// across three inspections. Held as a directory for the same reason clients
/// and facilities are: so an inspector picks rather than types.
class EggSuppliers extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get physicalAddress => text().withDefault(const Constant(''))();
  TextColumn get contactPerson => text().withDefault(const Constant(''))();
  TextColumn get telephone => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

class EggDirectionRemarks extends Table {
  IntColumn get id => integer()();

  /// 'quality' | 'labelling'
  TextColumn get directionType => text()();

  /// Named `remarkText`, not `text`: a getter called `text` would shadow
  /// Drift's own `text()` column builder and the table would not generate.
  TextColumn get remarkText => text().named('text')();

  /// The original's own list order, which is not alphabetical.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Captured inspections
// ---------------------------------------------------------------------------

class EggInspections extends Table {
  TextColumn get clientUuid => text()();

  /// The store visit this record was captured under, empty when standalone.
  /// The visit's closing signatures find their members through this.
  TextColumn get visitUuid => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get inspectedAt => dateTime()();

  TextColumn get facilityName => text().withDefault(const Constant(''))();
  IntColumn get facilityTypeId => integer().nullable()();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityPhone => text().withDefault(const Constant(''))();
  IntColumn get reasonId => integer().nullable()();

  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get clientAddress => text().withDefault(const Constant(''))();
  TextColumn get clientContactPerson =>
      text().withDefault(const Constant(''))();
  TextColumn get clientContactNumber =>
      text().withDefault(const Constant(''))();
  TextColumn get clientEmail => text().withDefault(const Constant(''))();
  TextColumn get representativeName => text().withDefault(const Constant(''))();

  /// The original's Signatures Control block: the authorised manager who
  /// signs, and their email.
  TextColumn get managerName => text().withDefault(const Constant(''))();
  TextColumn get managerEmail => text().withDefault(const Constant(''))();

  TextColumn get producerSupplier => text().withDefault(const Constant(''))();
  TextColumn get batchNumber => text().withDefault(const Constant(''))();
  DateTimeColumn get bestBefore => dateTime().nullable()();
  IntColumn get traySizeId => integer().nullable()();

  /// What the consignment is *declared* as — the claim on the packaging, not
  /// what the sample turns out to be. Deviation tolerances are keyed on these,
  /// because a Grade 1 Jumbo claim is held to a tighter standard than a Grade 3
  /// Small one. Distinct from [determinedGradeId], which is the outcome.
  IntColumn get declaredSizeId => integer().nullable()();
  IntColumn get declaredGradeId => integer().nullable()();
  IntColumn get sampleSize => integer().nullable()();
  BoolColumn get pasteurisedPresent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get haughNotRequired =>
      boolean().withDefault(const Constant(false))();

  /// The original's `switchEggWeighingInspectionNotRequired`. Eggs cannot be
  /// broken open on a retailer's premises, so at a retailer the inspector may
  /// record that no weighing or grading was possible. The sizing and grading
  /// block then comes off the page entirely and the inspection goes straight
  /// to signature.
  BoolColumn get weighingNotRequired =>
      boolean().withDefault(const Constant(false))();

  /// The two gating switches a draft must not forget across a restart:
  /// outer labelling available (opens the outer-packaging checklist) and
  /// the confirmed-and-locked label checklist (opens sampling).
  BoolColumn get outerLabellingAvailable =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get labelChecklistComplete =>
      boolean().withDefault(const Constant(false))();

  IntColumn get determinedGradeId => integer().nullable()();
  BoolColumn get gradeOverridden =>
      boolean().withDefault(const Constant(false))();
  TextColumn get overrideReason => text().withDefault(const Constant(''))();
  TextColumn get generalComments => text().withDefault(const Constant(''))();
  TextColumn get nonConformanceComments =>
      text().withDefault(const Constant(''))();

  /// Comma-separated ids.
  TextColumn get failedRequirementIds =>
      text().withDefault(const Constant(''))();
  TextColumn get restrictedParticularIds =>
      text().withDefault(const Constant(''))();

  /// Particulars typed in at the inspection because the Agency's list
  /// did not have them; one per line. See TypedParticulars.
  TextColumn get restrictedParticularsText =>
      text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();


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

  /// The inspector's answers when the "Eggs" expression row or the
  /// best-before row is unticked: omitted altogether (a seizure under
  /// FSA-SOP-APS-001 Annexure D) or shown but wrong (30 days).
  BoolColumn get eggsExpressionAbsent =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get bestBeforeAbsent =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  /// Which inspector captured this, by username.
  ///
  /// Handsets get shared, and without this every list on the device showed
  /// every inspection on it. Worse, an inspection captured by one inspector but
  /// uploaded while another was signed in went up under the second one's token
  /// and was recorded against them permanently — misattributed evidence in a
  /// food-safety record.
  ///
  /// Username rather than the server's user id: an inspection can be captured
  /// offline by someone whose numeric id this device has never been told, and
  /// the username is what both the session and the sync payload carry.
  ///
  /// Nullable only so the column can be added to existing databases; the
  /// migration back-fills it and every row written since carries a value.
  TextColumn get inspectorUsername => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

class EggSamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();
  IntColumn get eggNumber => integer()();
  RealColumn get massG => real().nullable()();
  IntColumn get sizeId => integer().nullable()();
  IntColumn get gradeId => integer().nullable()();
  RealColumn get albumenHeightMm => real().nullable()();
  RealColumn get haughUnit => real().nullable()();

  /// Comma-separated deviation ids ticked on this egg.
  TextColumn get deviationIds => text().withDefault(const Constant(''))();
}

/// A direction issued off the back of an inspection.
class EggDirections extends Table {
  TextColumn get clientUuid => text()();

  /// Links back to the inspection, when raised from one.
  TextColumn get inspectionUuid => text().nullable()();

  /// One notice may carry either part or both — it is not two directions.
  /// Each part has its own deadline: a mislabelled consignment and a failing
  /// one are not put right on the same timescale.
  BoolColumn get labellingPart =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get qualityPart => boolean().withDefault(const Constant(false))();
  DateTimeColumn get labelCorrectBy => dateTime().nullable()();
  DateTimeColumn get qualityCorrectBy => dateTime().nullable()();

  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get issuedAt => dateTime()();

  TextColumn get directionNumber => text().withDefault(const Constant(''))();
  RealColumn get quantityRemoved => real().nullable()();

  /// Comma-separated remark ids.
  TextColumn get remarkIds => text().withDefault(const Constant(''))();
  TextColumn get additionalRemarks => text().withDefault(const Constant(''))();

  TextColumn get clientName => text().withDefault(const Constant(''))();
  TextColumn get producerSupplier => text().withDefault(const Constant(''))();

  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  /// Which inspector issued this notice. See the note on
  /// [EggInspections.inspectorUsername] — a direction is a legal instruction to
  /// a client, so attributing one to the wrong inspector matters more here than
  /// anywhere else in the app.
  TextColumn get inspectorUsername => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientUuid};
}

/// A signature captured against an egg inspection.
///
/// One row per role ('manager' or 'inspector'), mirroring the server's
/// unique_together — re-signing replaces the earlier image.
class EggSignatures extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();
  TextColumn get role => text()();
  TextColumn get filePath => text()();
  TextColumn get signedName => text().withDefault(const Constant(''))();
  BoolColumn get declined => boolean().withDefault(const Constant(false))();
  DateTimeColumn get signedAt => dateTime().nullable()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}

class EggPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get inspectionUuid => text()();

  /// 'egg' | 'label' | 'deviation' | 'numbering'
  TextColumn get kind => text()();
  TextColumn get filePath => text()();
  TextColumn get caption => text().withDefault(const Constant(''))();
  DateTimeColumn get capturedAt => dateTime()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}
