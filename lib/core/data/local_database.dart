import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'eggs_tables.dart';
import 'fruitveg_tables.dart';
import 'poultry_capture_tables.dart';
import 'poultry_tables.dart';

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
    PoultryQuidInspections,
    PoultryQuidSamples,
    PoultryDirections,
    PoultryPhotos,
    PoultrySignatures,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'fsa_local'));

  @override
  int get schemaVersion => 13;

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

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
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
          if (from < 7) {
            // Egg suppliers become a directory rather than free text.
            // Reference data, so an empty table is safe: the next sync fills
            // it.
            await m.createTable(eggSuppliers);
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
            await m.addColumn(eggInspections, eggInspections.declaredSizeId);
            await m.addColumn(eggInspections, eggInspections.declaredGradeId);
            await m.addColumn(eggDirections, eggDirections.labellingPart);
            await m.addColumn(eggDirections, eggDirections.qualityPart);
            await m.addColumn(eggDirections, eggDirections.labelCorrectBy);
            await m.addColumn(eggDirections, eggDirections.qualityCorrectBy);
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
          if (from < 8) {
            // Inspections and directions become owned by the inspector who
            // captured them, so a shared handset stops showing everyone
            // everyone else's work — and stops uploading it under whichever
            // account happened to be signed in at the time.
            await m.addColumn(
              eggInspections,
              eggInspections.inspectorUsername,
            );
            await m.addColumn(
              eggDirections,
              eggDirections.inspectorUsername,
            );

            for (final statement in ownerBackfillStatements) {
              await customStatement(statement);
            }
          }
          if (from < 13) {
            // Photographs and signatures for the poultry records.
            await m.createTable(poultryPhotos);
            await m.createTable(poultrySignatures);
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
            await m.addColumn(
              poultryChecklistItems,
              poultryChecklistItems.minLetteringHeight,
            );
          }
          if (from < 11) {
            // Two fields the first cut of the poultry form left out: the
            // second client email address and the facility's trading name.
            await m.addColumn(
              poultryInspections,
              poultryInspections.clientEmail2,
            );
            await m.addColumn(
              poultryInspections,
              poultryInspections.producerTradingName,
            );
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
          if (from < 9) {
            // Sizes gain a flag separating a mass band from a declaration
            // printed on the pack. Defaults to true, which is right for every
            // band already stored; the one declaration ("Mixed Size") arrives
            // with the next reference sync carrying false.
            await m.addColumn(eggSizes, eggSizes.isMassBand);
          }
        },
      );

  Future<SyncedUser?> findUser(String username) =>
      (select(syncedUsers)
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

  Future<void> writeSyncState(String key, String value) => into(syncState)
      .insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));
}
