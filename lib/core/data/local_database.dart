import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'eggs_tables.dart';
import 'fruitveg_tables.dart';
import 'pmp_tables.dart';
import 'rawrmp_tables.dart';
import 'poultry_capture_tables.dart';
import 'invoice_tables.dart';
import 'visits_tables.dart';
import 'poultry_tables.dart';
import 'seizure_tables.dart';

part 'local_database.g.dart';

/// Inspectors synced from the server so they can sign in with no signal.
///
/// This is the first table of what will become the offline store. It carries
/// `offlineVerifier` — a salted, stretched PBKDF2 credential — never a
/// plaintext or reversible password.
class SyncedUsers extends Table {
  IntColumn get id => integer()();
  TextColumn get username => text().withLength(min: 1, max: 150)();
  TextColumn get firstName => text().withDefault(const Constant(''))();
  TextColumn get lastName => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get roleName => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  TextColumn get offlineVerifier => text().withDefault(const Constant(''))();
  TextColumn get updatedAt => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key/value store for sync cursors. Keeps the delta-sync position out of the
/// entity tables so every future synced table can share one mechanism.
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    SyncedUsers,
    SyncState,
    FvCommodityGroups,
    FvCommodities,
    FvCultivars,
    FvCountries,
    FvGrades,
    FvDefectGroups,
    FvSubDefects,
    FvTolerances,
    FvRequirements,
    FvInspectionPoints,
    FvInspections,
    FvInspectionDefects,
    FvInspectionPhotos,
    EggSizes,
    EggGrades,
    EggDeviationCategories,
    EggDeviations,
    EggDeviationTolerances,
    EggRequirements,
    EggRestrictedParticulars,
    EggTraySizes,
    EggFacilityTypes,
    EggInspectionReasons,
    EggInspections,
    EggSamples,
    EggPhotos,
    EggSignatures,
    EggClients,
    EggDirectionRemarks,
    EggSuppliers,
    EggDirections,
    EggFacilities,
    PoultryMeatTypes,
    PoultryGrades,
    PoultryPortionTypes,
    PoultryDesignationClasses,
    PoultryAltDesignationClasses,
    PoultryDesignationGradeLinks,
    PoultryAltDesignationGradeLinks,
    PoultryChecklistItems,
    PoultryRestrictedParticulars,
    PoultryInspectionReasons,
    PoultryInspectionLocations,
    PoultryDirectionRemarks,
    PoultryInspections,
    PoultryLabelInspections,
    StoreVisits,
    Seizures,
    VisitOccurrencePhotos,
    InvoiceRequests,
    PoultryQuidInspections,
    PoultryQuidSamples,
    PoultryQuidInjectors,
    PoultryDirections,
    PoultryPhotos,
    PoultrySignatures,
    PmpProducts,
    PmpProducers,
    PmpSubClassProducts,
    PmpStorageTypes,
    PmpIngredients,
    PmpLaboratories,
    PmpRestrictedParticulars,
    PmpDirectionRemarks,
    PmpInspectionReasons,
    PmpInspectionLocations,
    PmpChecklistItems,
    PmpLabelNonConformances,
    PmpInspections,
    PmpDirections,
    RawRmpProducts,
    RawRmpProducers,
    RawRmpStorageTypes,
    RawRmpLaboratories,
    RawRmpSampleCategories,
    RawRmpRestrictedParticulars,
    RawRmpDirectionRemarks,
    RawRmpInspectionReasons,
    RawRmpInspectionLocations,
    RawRmpChecklistItems,
    RawRmpLabelNonConformances,
    RawRmpInspections,
    RawRmpDirections,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'fsa_local'));

  @override
  int get schemaVersion => 62;

  /// The v8 back-fill: give already-captured work an owner.
  ///
  /// Nothing recorded who captured an inspection before v8, so the session on
  /// this device is the only answer available — and on a handset used by one
  /// inspector, the ordinary case, it is the right one. Rows left null because
  /// no session is stored are unreachable rather than lost: capturing requires
  /// signing in, so a device with no session has no work to orphan.
  ///
  /// Named rather than inlined so a test can run the very statements the
  /// migration runs. A paraphrase in a test proves the paraphrase works.
  static const ownerBackfillStatements = <String>[
    "UPDATE egg_inspections SET inspector_username = "
        "(SELECT value FROM sync_state WHERE key = 'session.userName') "
        "WHERE inspector_username IS NULL",
    "UPDATE egg_directions SET inspector_username = "
        "(SELECT value FROM sync_state WHERE key = 'session.userName') "
        "WHERE inspector_username IS NULL",
    // A cleared session stores an empty string rather than deleting the row,
    // which would otherwise stamp every record with "" and own them to nobody
    // in a way that looks like a real username.
    "UPDATE egg_inspections SET inspector_username = NULL "
        "WHERE inspector_username = ''",
    "UPDATE egg_directions SET inspector_username = NULL "
        "WHERE inspector_username = ''",
  ];

  /// ALTER TABLE ... ADD COLUMN, only when the column is not there yet.
  ///
  /// `Migrator.createTable` builds a table with its *current* full schema, so
  /// a database upgrading across many versions gets the new columns at the
  /// CREATE — and the later blocks that ADD those same columns would then
  /// fail with "duplicate column". Every ALTER in the upgrade goes through
  /// this guard so each block can be written for the schema of its own time
  /// and still run safely on any older database. (An old handset upgrading
  /// straight to v40 crashed on exactly this.)
  Future<void> addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    final info = await customSelect(
      'PRAGMA table_info("${table.actualTableName}")',
    ).get();
    final exists = info.any((row) => row.data['name'] == column.name);
    if (!exists) await m.addColumn(table, column);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Oldest first, always: a later block may ALTER a table an
          // earlier block CREATEs, and a database upgrading across many
          // versions runs every step in this order. (An old handset with a
          // pre-visits database crashed on ALTER store_visits because the
          // new blocks used to sit above the one that created the table.)
          if (from < 2) {
            // Fruit & Veg tables added in v2. Reference data is re-syncable,
            // so creating them empty is safe — no data migration needed.
            await m.createTable(fvCommodityGroups);
            await m.createTable(fvCommodities);
            await m.createTable(fvCultivars);
            await m.createTable(fvCountries);
            await m.createTable(fvGrades);
            await m.createTable(fvDefectGroups);
            await m.createTable(fvSubDefects);
            await m.createTable(fvTolerances);
            await m.createTable(fvRequirements);
            await m.createTable(fvInspectionPoints);
            await m.createTable(fvInspections);
            await m.createTable(fvInspectionDefects);
            await m.createTable(fvInspectionPhotos);
          }
          if (from < 3) {
            // Poultry Egg tables added in v3. Reference data is re-syncable.
            await m.createTable(eggSizes);
            await m.createTable(eggGrades);
            await m.createTable(eggDeviationCategories);
            await m.createTable(eggDeviations);
            await m.createTable(eggRequirements);
            await m.createTable(eggRestrictedParticulars);
            await m.createTable(eggTraySizes);
            await m.createTable(eggFacilityTypes);
            await m.createTable(eggInspectionReasons);
            await m.createTable(eggInspections);
            await m.createTable(eggSamples);
            await m.createTable(eggPhotos);
          }
          if (from < 4) {
            // Clients and directions added in v4.
            await m.createTable(eggClients);
            await m.createTable(eggDirectionRemarks);
            await m.createTable(eggDirections);
          }
          if (from < 5) {
            await m.createTable(eggFacilities);
          }
          if (from < 6) {
            // Deviation tolerances, and directions gaining their two parts.
            //
            // The tolerance table is reference data and re-syncable, so it is
            // created empty. The direction columns are added rather than the
            // table rebuilt, so an inspector mid-round does not lose a notice
            // that has not been uploaded yet; the old single type and date are
            // folded into whichever part they described.
            await m.createTable(eggDeviationTolerances);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.declaredSizeId);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.declaredGradeId);
            await addColumnIfMissing(
                m, eggDirections, eggDirections.labellingPart);
            await addColumnIfMissing(
                m, eggDirections, eggDirections.qualityPart);
            await addColumnIfMissing(
                m, eggDirections, eggDirections.labelCorrectBy);
            await addColumnIfMissing(
                m, eggDirections, eggDirections.qualityCorrectBy);
            await customStatement(
              "UPDATE egg_directions SET quality_part = "
              "CASE WHEN direction_type = 'labelling' THEN 0 ELSE 1 END, "
              "labelling_part = "
              "CASE WHEN direction_type = 'labelling' THEN 1 ELSE 0 END, "
              "quality_correct_by = "
              "CASE WHEN direction_type = 'labelling' THEN NULL "
              "ELSE correct_by END, "
              "label_correct_by = "
              "CASE WHEN direction_type = 'labelling' THEN correct_by "
              "ELSE NULL END",
            );
          }
          if (from < 7) {
            // Egg suppliers become a directory rather than free text.
            // Reference data, so an empty table is safe: the next sync fills
            // it.
            await m.createTable(eggSuppliers);
          }
          if (from < 8) {
            // Inspections and directions become owned by the inspector who
            // captured them, so a shared handset stops showing everyone
            // everyone else's work — and stops uploading it under whichever
            // account happened to be signed in at the time.
            await addColumnIfMissing(
              m,
              eggInspections,
              eggInspections.inspectorUsername,
            );
            await addColumnIfMissing(
              m,
              eggDirections,
              eggDirections.inspectorUsername,
            );

            for (final statement in ownerBackfillStatements) {
              await customStatement(statement);
            }
          }
          if (from < 9) {
            // Sizes gain a flag separating a mass band from a declaration
            // printed on the pack. Defaults to true, which is right for every
            // band already stored; the one declaration ("Mixed Size") arrives
            // with the next reference sync carrying false.
            await addColumnIfMissing(m, eggSizes, eggSizes.isMassBand);
          }
          if (from < 10) {
            // Poultry tables added in v10. Reference data is re-syncable and
            // the app also ships a bundled copy, so creating them empty is
            // safe — nothing captured is lost.
            await m.createTable(poultryMeatTypes);
            await m.createTable(poultryGrades);
            await m.createTable(poultryPortionTypes);
            await m.createTable(poultryDesignationClasses);
            await m.createTable(poultryAltDesignationClasses);
            await m.createTable(poultryDesignationGradeLinks);
            await m.createTable(poultryAltDesignationGradeLinks);
            await m.createTable(poultryChecklistItems);
            await m.createTable(poultryRestrictedParticulars);
            await m.createTable(poultryInspectionReasons);
            await m.createTable(poultryInspectionLocations);
            await m.createTable(poultryDirectionRemarks);
            await m.createTable(poultryInspections);
          }
          if (from < 11) {
            // Two fields the first cut of the poultry form left out: the
            // second client email address and the facility's trading name.
            await addColumnIfMissing(
              m,
              poultryInspections,
              poultryInspections.clientEmail2,
            );
            await addColumnIfMissing(
              m,
              poultryInspections,
              poultryInspections.producerTradingName,
            );
          }
          if (from < 12) {
            // The rest of the poultry module: the Label/Container checklist,
            // the QUID checklist and its per-carcass samples, and directions.
            await m.createTable(poultryLabelInspections);
            await m.createTable(poultryQuidInspections);
            await m.createTable(poultryQuidSamples);
            await m.createTable(poultryDirections);
            // Reference rows gain the lettering height the label screen shows
            // against each row. Empty until the next reference sync, which is
            // correct — no height is a real state on most rows.
            await addColumnIfMissing(
              m,
              poultryChecklistItems,
              poultryChecklistItems.minLetteringHeight,
            );
          }
          if (from < 13) {
            // Photographs and signatures for the poultry records.
            await m.createTable(poultryPhotos);
            await m.createTable(poultrySignatures);
          }
          if (from < 14) {
            // Processed Meat Product tables. Reference data is re-syncable
            // and bundled, so creating them empty is safe.
            await m.createTable(pmpProducts);
            await m.createTable(pmpSubClassProducts);
            await m.createTable(pmpStorageTypes);
            await m.createTable(pmpIngredients);
            await m.createTable(pmpLaboratories);
            await m.createTable(pmpRestrictedParticulars);
            await m.createTable(pmpDirectionRemarks);
            await m.createTable(pmpInspectionReasons);
            await m.createTable(pmpInspectionLocations);
            await m.createTable(pmpChecklistItems);
            await m.createTable(pmpLabelNonConformances);
            await m.createTable(pmpInspections);
            await m.createTable(pmpDirections);
          }
          if (from < 15) {
            // Certain Raw Processed Meat Products arrives whole.
            await m.createTable(rawRmpProducts);
            await m.createTable(rawRmpProducers);
            await m.createTable(rawRmpStorageTypes);
            await m.createTable(rawRmpLaboratories);
            await m.createTable(rawRmpSampleCategories);
            await m.createTable(rawRmpRestrictedParticulars);
            await m.createTable(rawRmpDirectionRemarks);
            await m.createTable(rawRmpInspectionReasons);
            await m.createTable(rawRmpInspectionLocations);
            await m.createTable(rawRmpChecklistItems);
            await m.createTable(rawRmpLabelNonConformances);
            await m.createTable(rawRmpInspections);
            await m.createTable(rawRmpDirections);
          }
          if (from < 16) {
            // The parity audit against the original screens: PMP gains its
            // producer directory, ingredient recipe and direction deadline;
            // RawRMP gains its two "new ..." free entries.
            await m.createTable(pmpProducers);
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.ingredientPercentages);
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.correctByDate);
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.newProducerDetails);
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.newProductItem);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.newProducerDetails);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.newProductItem);
          }
          if (from < 17) {
            // Directions become full reports, raised from the inspection the
            // way the original raises them: they carry the facility, producer,
            // batch and sampling particulars their summary pages show.
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.sourceInspectionUuid);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.newFacilityName);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.producerName);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.newProducerName);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.batchNumber);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.manufacturedPackedDate);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.primarySampleSize);
            await addColumnIfMissing(
                m, pmpDirections, pmpDirections.restrictedParticularIds);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.sourceInspectionUuid);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.newFacilityName);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.producerName);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.newProducerName);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.batchNumber);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.manufacturedPackedDate);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.primarySampleSize);
            await addColumnIfMissing(
                m, rawRmpDirections, rawRmpDirections.restrictedParticularIds);
          }
          if (from < 18) {
            // The eggs form gains the original's Signatures Control block:
            // the authorised manager's name and email on the inspection, and
            // captured signature images of their own.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.managerName);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.managerEmail);
            await m.createTable(eggSignatures);
          }
          if (from < 19) {
            // Facility types gain the original's own picker order.
            await addColumnIfMissing(
                m, eggFacilityTypes, eggFacilityTypes.sortOrder);
          }
          if (from < 20) {
            // Every egg picker gains the original's own list order.
            await addColumnIfMissing(
                m, eggInspectionReasons, eggInspectionReasons.sortOrder);
            await addColumnIfMissing(
                m, eggRequirements, eggRequirements.sortOrder);
            await addColumnIfMissing(m, eggRestrictedParticulars,
                eggRestrictedParticulars.sortOrder);
            await addColumnIfMissing(
                m, eggDirectionRemarks, eggDirectionRemarks.sortOrder);
          }
          if (from < 21) {
            // Tray sizes follow the original's seed order, where 15-Pack is
            // last rather than in numeric position.
            await addColumnIfMissing(m, eggTraySizes, eggTraySizes.sortOrder);
          }
          if (from < 22) {
            // Raw meat: a product name that is not indicated at all is a
            // seizure, not a deviation. The inspector's answer is stored.
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.productNameAbsent);
          }
          if (from < 23) {
            // Poultry grading is captured per carcass across the five-sample
            // lot rather than once for the whole inspection.
            await addColumnIfMissing(m, poultryLabelInspections,
                poultryLabelInspections.gradingBySample);
          }
          if (from < 24) {
            // A retailer inspection can record that no egg weighing was
            // possible on the premises.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.weighingNotRequired);
          }
          if (from < 25) {
            // The checklist rows gained the wording the original shows on
            // screen, alongside the wording it files against the record.
            await addColumnIfMissing(
                m, eggRequirements, eggRequirements.screenLabel);
          }
          if (from < 26) {
            // Store visits: one facility capture shared by several
            // inspections, signed once at the end.
            await m.createTable(storeVisits);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.visitUuid);
            await addColumnIfMissing(
                m, poultryInspections, poultryInspections.visitUuid);
            await addColumnIfMissing(
                m, poultryLabelInspections, poultryLabelInspections.visitUuid);
          }
          if (from < 27) {
            // The grouped inspection gains a plan — how many of each
            // commodity — and Raw Processed Meat joins it.
            await addColumnIfMissing(m, storeVisits, storeVisits.plannedEggs);
            await addColumnIfMissing(
                m, storeVisits, storeVisits.plannedPoultry);
            await addColumnIfMissing(m, storeVisits, storeVisits.plannedLabels);
            await addColumnIfMissing(m, storeVisits, storeVisits.plannedRaw);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.visitUuid);
          }
          if (from < 28) {
            // A resumed egg draft forgot its two gating switches — outer
            // labelling available and the confirmed label checklist — so
            // the sampling block vanished on every restart.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.outerLabellingAvailable);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.labelChecklistComplete);
          }
          if (from < 29) {
            // Processed Meat joins the grouped inspection.
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.visitUuid);
            await addColumnIfMissing(m, storeVisits, storeVisits.plannedPmp);
          }
          if (from < 30) {
            // The Request for Invoice form, completed after a grouped
            // inspection so the visit can be billed.
            await m.createTable(invoiceRequests);
          }
          if (from < 31) {
            // Entries the original's PMP and Raw screens carry and the
            // rebuild had not grown: the new-facility name and the two
            // new-item particulars.
            for (final column in [
              rawRmpInspections.newFacilityName,
              rawRmpInspections.newItemSizeG,
              rawRmpInspections.newItemBarcode,
            ]) {
              await addColumnIfMissing(m, rawRmpInspections, column);
            }
            await addColumnIfMissing(
                m, poultryInspections, poultryInspections.newFacilityName);
            for (final column in [
              pmpInspections.newFacilityName,
              pmpInspections.newItemSizeG,
              pmpInspections.newItemBarcode,
            ]) {
              await addColumnIfMissing(m, pmpInspections, column);
            }
          }
          if (from < 32) {
            // The grouped inspection is uploaded in its own right now, so
            // it needs to remember whether it has been.
            await addColumnIfMissing(m, storeVisits, storeVisits.isUploaded);
          }
          if (from < 33) {
            // The two extra document recipients moved off the commodity
            // forms and onto the visit, which is where a site's addresses
            // are captured.
            await addColumnIfMissing(
                m, storeVisits, storeVisits.additionalEmail1);
            await addColumnIfMissing(
                m, storeVisits, storeVisits.additionalEmail2);
          }
          if (from < 34) {
            // A third recipient, for a visit that already has two.
            await addColumnIfMissing(
                m, storeVisits, storeVisits.additionalEmail3);
          }
          if (from < 35) {
            await addColumnIfMissing(
                m, poultryInspections, poultryInspections.gradingBySample);
          }
          if (from < 36) {
            await addColumnIfMissing(
                m, storeVisits, storeVisits.isOccurrenceReport);
          }
          if (from < 37) {
            await addColumnIfMissing(m, storeVisits, storeVisits.facilityType);
          }
          if (from < 38) {
            await addColumnIfMissing(
                m, storeVisits, storeVisits.occurrenceTimeOfVisit);
            await addColumnIfMissing(
                m, storeVisits, storeVisits.occurrenceRegistrationCode);
            await addColumnIfMissing(
                m, storeVisits, storeVisits.occurrenceDescription);
            await m.createTable(visitOccurrencePhotos);
          }
          if (from < 39) {
            await addColumnIfMissing(
                m, storeVisits, storeVisits.managerSignaturePath);
            await addColumnIfMissing(
                m, storeVisits, storeVisits.inspectorSignaturePath);
          }
          if (from < 40) {
            await addColumnIfMissing(m, rawRmpInspections,
                rawRmpInspections.compositionChecklistJson);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.compositionComments);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.representativePosition);
          }
          if (from < 41) {
            await addColumnIfMissing(m, storeVisits, storeVisits.planOrder);
          }
          if (from < 42) {
            await addColumnIfMissing(
                m, poultryQuidInspections, poultryQuidInspections.visitUuid);
          }
          if (from < 43) {
            // The QUID checklist catches up with the original: a plant runs
            // several injectors, each set to its own percentage, and the
            // injector weighing is recorded apart from the chilling.
            await m.createTable(poultryQuidInjectors);
            for (final column in [
              poultryQuidSamples.beforeMassG,
              poultryQuidSamples.gainG,
              poultryQuidSamples.injectorRatePercent,
              poultryQuidSamples.assignedInjector,
            ]) {
              await addColumnIfMissing(m, poultryQuidSamples, column);
            }
          }
          if (from < 44) {
            // The injector's after-mass was sharing the chilling column, so
            // whichever was weighed second overwrote the other.
            await addColumnIfMissing(m, poultryQuidSamples,
                poultryQuidSamples.injectorAfterMassG);
            await addColumnIfMissing(m, poultryQuidInspections,
                poultryQuidInspections.documentDate);
          }
          if (from < 45) {
            // Asked once at the door instead of on every inspection in the
            // group. Visits captured before this carry no reason, so their
            // forms go on asking.
            await addColumnIfMissing(
                m, storeVisits, storeVisits.inspectionReason);
          }
          if (from < 46) {
            // QUID is determined per carcass. One pair of masses on the
            // inspection could not say which injector produced them.
            for (final column in [
              poultryQuidSamples.quidFinalMassG,
              poultryQuidSamples.quidGainG,
              poultryQuidSamples.quidPercent,
            ]) {
              await addColumnIfMissing(m, poultryQuidSamples, column);
            }
          }
          if (from < 47) {
            // The kilometres belong to the trip, not to a product.
            await addColumnIfMissing(
                m, storeVisits, storeVisits.distanceTravelledKm);
          }
          if (from < 48) {
            // The direction's own number, and the deadline the client is
            // served with.
            for (final column in [
              rawRmpDirections.referenceNumber,
              rawRmpDirections.correctByDate,
            ]) {
              await addColumnIfMissing(m, rawRmpDirections, column);
            }
          }
          if (from < 49) {
            // Whether the inspector chose to seize. A seizure is its own
            // outcome under FSA-SOP-APS-001, not a severer rejection.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.seizureDecision);
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.seizureDecision);
          }
          if (from < 50) {
            // Outer labelling starts Compliant now. Drafts saved by earlier
            // builds still carry the old default — every outer row failed
            // the moment the block was opened — and would come back that
            // way. Repaired once, here, on that exact fingerprint.
            await repairLegacyOuterDrafts();
          }
          if (from < 51) {
            // Restricted particulars typed in at the inspection. The meat
            // forms had a text column for these already; eggs did not.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.restrictedParticularsText);
          }
          if (from < 52) {
            // Poultry is labelling, with grading to follow when the
            // inspector says so; the answer lives on the label record.
            await addColumnIfMissing(m, poultryLabelInspections,
                poultryLabelInspections.gradingToFollow);
          }
          if (from < 53) {
            // Raw is the inspection or the compositional checklist, asked
            // when it is started. Older records keep showing both.
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.recordKind);
          }
          if (from < 54) {
            // QUID weighed stage by stage, as the original does: rounds on
            // each carcass, the rejection it can end in, and the list of
            // records verified.
            await addColumnIfMissing(
                m, poultryQuidSamples, poultryQuidSamples.iteration);
            for (final column in [
              poultryQuidInspections.verificationRecordsJson,
              poultryQuidInspections.directionRequired,
              poultryQuidInspections.directionReason,
              poultryQuidInspections.correctByDate,
            ]) {
              await addColumnIfMissing(m, poultryQuidInspections, column);
            }
          }
          if (from < 55) {
            // The inspector's approval of a visit on the server.
            await addColumnIfMissing(m, storeVisits, storeVisits.approvedAt);
            await addColumnIfMissing(m, storeVisits, storeVisits.approvalSent);
          }
          if (from < 56) {
            // Raw asks for a primary sample size, as PMP already does.
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.primarySampleSize);
          }
          if (from < 57) {
            // The producer, asked once on the visit.
            await addColumnIfMissing(m, storeVisits, storeVisits.producerName);
            // An approval can be taken back now, so "sent" means the server
            // holds the current answer. A visit never approved has nothing
            // to send; before, the flag read false on every visit.
            await customStatement(
                'UPDATE store_visits SET approval_sent = 1 '
                'WHERE approved_at IS NULL');
          }
          if (from < 58) {
            // A sample can go for more than one testing category; the one
            // already chosen becomes the first of them.
            await addColumnIfMissing(
                m, rawRmpInspections, rawRmpInspections.sampleCategoryIds);
            await customStatement(
                'UPDATE raw_rmp_inspections SET sample_category_ids = '
                "CAST(sample_category_id AS TEXT) WHERE sample_category_id "
                "IS NOT NULL AND (sample_category_ids IS NULL OR "
                "sample_category_ids = '')");
          }
          if (from < 59) {
            // PMP follows FSA-SOP-APS-001 Annexure B: the product-name
            // answer and the seizure decision travel with the record.
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.productNameAbsent);
            await addColumnIfMissing(
                m, pmpInspections, pmpInspections.seizureDecision);
          }
          if (from < 60) {
            // Eggs follow FSA-SOP-APS-001 Annexure D: whether "Eggs" or the
            // best-before date was omitted travels with the record.
            await addColumnIfMissing(
                m, eggInspections, eggInspections.eggsExpressionAbsent);
            await addColumnIfMissing(
                m, eggInspections, eggInspections.bestBeforeAbsent);
          }
          if (from < 61) {
            // Poultry follows FSA-SOP-APS-001 Annexure C: the omission
            // answers and the seizure decision travel with the record, and
            // a direction carries the correct-by date the annexure sets.
            await addColumnIfMissing(
                m, poultryInspections, poultryInspections.seizureDecision);
            await addColumnIfMissing(m, poultryLabelInspections,
                poultryLabelInspections.classOmitted);
            await addColumnIfMissing(m, poultryLabelInspections,
                poultryLabelInspections.gradeOmitted);
            await addColumnIfMissing(m, poultryLabelInspections,
                poultryLabelInspections.seizureDecision);
            await addColumnIfMissing(m, poultryQuidInspections,
                poultryQuidInspections.seizureDecision);
            await addColumnIfMissing(
                m, poultryDirections, poultryDirections.correctByDate);
          }
          if (from < 62) {
            // FSA-SOP-APS-001 Annexure E: the seizure served, one row per
            // record it was raised off, whatever the commodity.
            await m.createTable(seizures);
          }
        },
      );

  /// Puts the outer-labelling rows of unfinished drafts back to Compliant.
  ///
  /// Until 2026-09-23 the egg form marked every outer row as a deviation the
  /// moment "Is the outer labelling available" was switched on, and the
  /// poultry label form left every outer row unticked when its block was
  /// opened. Both now start Compliant, but a draft saved by the older build
  /// still holds the old answers and reopens looking exactly as it did.
  ///
  /// Only a draft is touched — a record that is ready or completed is the
  /// inspector's finished word — and only one that carries the old build's
  /// precise signature: the block switched on and *every* outer row failed
  /// (eggs) or *no* outer row compliant (poultry). An inspector who
  /// genuinely failed every outer row on an unfinished draft is far rarer
  /// than the bug that wrote that shape into every draft, and they will
  /// see the rows come back Compliant and mark them again.
  ///
  /// Returns how many drafts were repaired.
  Future<int> repairLegacyOuterDrafts() async {
    Set<int> ids(String csv) => csv
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    var repaired = 0;

    final outerRequirements = (await customSelect(
            "SELECT id FROM egg_requirements WHERE kind = 'label_outer'")
        .get())
        .map((r) => r.read<int>('id'))
        .toSet();
    if (outerRequirements.isNotEmpty) {
      final drafts = await customSelect(
          'SELECT client_uuid, failed_requirement_ids FROM egg_inspections '
          "WHERE status = 'draft' AND outer_labelling_available = 1").get();
      for (final row in drafts) {
        final failed = ids(row.read<String>('failed_requirement_ids'));
        if (!failed.containsAll(outerRequirements)) continue;
        failed.removeAll(outerRequirements);
        await customUpdate(
          'UPDATE egg_inspections SET failed_requirement_ids = ? '
          'WHERE client_uuid = ?',
          variables: [
            Variable.withString((failed.toList()..sort()).join(',')),
            Variable.withString(row.read<String>('client_uuid')),
          ],
          updates: {eggInspections},
        );
        repaired++;
      }
    }

    final outerItems = (await customSelect(
            "SELECT id FROM poultry_checklist_items WHERE kind = 'label_outer'")
        .get())
        .map((r) => r.read<int>('id'))
        .toSet();
    if (outerItems.isNotEmpty) {
      final drafts = await customSelect(
          'SELECT client_uuid, compliant_item_ids FROM poultry_label_inspections '
          "WHERE status = 'draft' AND outer_labels_present = 1").get();
      for (final row in drafts) {
        final compliant = ids(row.read<String>('compliant_item_ids'));
        if (compliant.intersection(outerItems).isNotEmpty) continue;
        compliant.addAll(outerItems);
        await customUpdate(
          'UPDATE poultry_label_inspections SET compliant_item_ids = ? '
          'WHERE client_uuid = ?',
          variables: [
            Variable.withString((compliant.toList()..sort()).join(',')),
            Variable.withString(row.read<String>('client_uuid')),
          ],
          updates: {poultryLabelInspections},
        );
        repaired++;
      }
    }
    return repaired;
  }

  Future<SyncedUser?> findUser(String username) => (select(syncedUsers)
        ..where((u) => u.username.lower().equals(username.toLowerCase()))
        ..limit(1))
      .getSingleOrNull();

  Future<int> countUsers() async {
    final row = await (selectOnly(syncedUsers)
          ..addColumns([syncedUsers.id.count()]))
        .getSingle();
    return row.read(syncedUsers.id.count()) ?? 0;
  }

  /// Upsert a sync batch in one transaction so a dropped connection mid-batch
  /// cannot leave the store half-written.
  ///
  /// Returns how many rows were genuinely new — ids this device did not already
  /// hold. The manual "Sync users" button re-fetches every user, so a count of
  /// rows *written* is always the whole organisation, and reporting that as
  /// "added" told an inspector five new accounts had arrived every time they
  /// pressed the button.
  Future<int> upsertUsers(List<SyncedUsersCompanion> rows) async {
    if (rows.isEmpty) return 0;
    final ids = [for (final row in rows) row.id.value];
    final known = await (selectOnly(syncedUsers)
          ..addColumns([syncedUsers.id])
          ..where(syncedUsers.id.isIn(ids)))
        .map((row) => row.read(syncedUsers.id)!)
        .get();
    final existing = known.toSet();
    await batch((b) => b.insertAllOnConflictUpdate(syncedUsers, rows));
    return ids.where((id) => !existing.contains(id)).length;
  }

  /// Remove every synced user outside [keep], returning how many were dropped.
  ///
  /// [keep] is the server's authoritative id set. A row outside it belongs to
  /// an account that no longer exists, and while it sits here it is a working
  /// offline credential — `findUser` will happily hand it to sign-in.
  ///
  /// Callers must not pass an empty list; see `UserSyncRepository.pruneDeleted`
  /// for why an empty set is treated as a failure rather than an instruction.
  Future<int> deleteUsersNotIn(List<int> keep) =>
      (delete(syncedUsers)..where((u) => u.id.isNotIn(keep))).go();

  Future<String?> readSyncState(String key) async {
    final row = await (select(syncState)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSyncState(String key, String value) =>
      into(syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(key: key, value: value));
}
