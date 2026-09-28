import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../../core/data/local_database.dart';
import '../domain/grading_engine.dart';

/// Syncs Fruit & Veg reference data and reads it back for the form.
///
/// The server returns every lookup table in one response, so a full refresh is
/// a single request, rather than dozens of block-paged calls.
class FruitVegRepository {
  FruitVegRepository({
    required this.baseUrl,
    required this.database,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  static const cursorKey = 'fruitveg.cursor';
  static const lastSyncAtKey = 'fruitveg.lastSyncAt';

  final String baseUrl;
  final LocalDatabase database;
  final Duration timeout;
  final http.Client _client;

  /// Pulls reference data and returns the number of rows written.
  Future<int> syncReference({bool full = false}) async {
    final cursor = full ? null : await database.readSyncState(cursorKey);
    final uri = Uri.parse('$baseUrl/api/fruitveg/reference/').replace(
      queryParameters: {
        if (cursor != null && cursor.isNotEmpty) 'since': cursor,
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Reference sync failed with status ${response.statusCode}.',
        uri,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    var written = 0;

    List<Map<String, dynamic>> rows(String key) =>
        ((data[key] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>();

    await database.transaction(() async {
      written += await _write(rows('commodity_groups'), (j) async {
        await database.into(database.fvCommodityGroups).insertOnConflictUpdate(
              FvCommodityGroupsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('commodities'), (j) async {
        await database.into(database.fvCommodities).insertOnConflictUpdate(
              FvCommoditiesCompanion.insert(
                id: Value(j['id'] as int),
                groupId: j['group'] as int,
                name: j['name'] as String,
                requiresBrix: Value(j['requires_brix'] as bool? ?? false),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('cultivars'), (j) async {
        await database.into(database.fvCultivars).insertOnConflictUpdate(
              FvCultivarsCompanion.insert(
                id: Value(j['id'] as int),
                commodityId: j['commodity'] as int,
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('countries'), (j) async {
        await database.into(database.fvCountries).insertOnConflictUpdate(
              FvCountriesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                code: Value(j['code'] as String? ?? ''),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('grades'), (j) async {
        await database.into(database.fvGrades).insertOnConflictUpdate(
              FvGradesCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                rank: j['rank'] as int,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('defect_groups'), (j) async {
        await database.into(database.fvDefectGroups).insertOnConflictUpdate(
              FvDefectGroupsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                isInternal: Value(j['is_internal'] as bool? ?? false),
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('sub_defects'), (j) async {
        await database.into(database.fvSubDefects).insertOnConflictUpdate(
              FvSubDefectsCompanion.insert(
                id: Value(j['id'] as int),
                groupId: j['group'] as int,
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('tolerances'), (j) async {
        await database.into(database.fvTolerances).insertOnConflictUpdate(
              FvTolerancesCompanion.insert(
                id: Value(j['id'] as int),
                commodityId: j['commodity'] as int,
                defectGroupId: j['defect_group'] as int,
                gradeId: j['grade'] as int,
                maxPercentage: double.parse(j['max_percentage'].toString()),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('requirements'), (j) async {
        await database.into(database.fvRequirements).insertOnConflictUpdate(
              FvRequirementsCompanion.insert(
                id: Value(j['id'] as int),
                kind: j['kind'] as String,
                description: j['description'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
      written += await _write(rows('inspection_points'), (j) async {
        await database.into(database.fvInspectionPoints).insertOnConflictUpdate(
              FvInspectionPointsCompanion.insert(
                id: Value(j['id'] as int),
                name: j['name'] as String,
                isActive: Value(j['is_active'] as bool? ?? true),
                updatedAt: Value(j['updated_at'] as String? ?? ''),
              ),
            );
      });
    });

    final nextCursor = body['cursor'] as String?;
    if (nextCursor != null) {
      await database.writeSyncState(cursorKey, nextCursor);
    }
    await database.writeSyncState(
      lastSyncAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    return written;
  }

  Future<int> _write(
    List<Map<String, dynamic>> rows,
    Future<void> Function(Map<String, dynamic>) insert,
  ) async {
    for (final row in rows) {
      await insert(row);
    }
    return rows.length;
  }

  // --- Reads for the form -------------------------------------------------

  Future<bool> get hasReferenceData async =>
      (await database.select(database.fvCommodities).get()).isNotEmpty;

  Future<List<FvCommodityGroup>> commodityGroups() =>
      (database.select(database.fvCommodityGroups)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<FvCommodity>> commodities({int? groupId}) {
    final q = database.select(database.fvCommodities)
      ..where((t) => t.isActive.equals(true));
    if (groupId != null) q.where((t) => t.groupId.equals(groupId));
    q.orderBy([(t) => OrderingTerm(expression: t.name)]);
    return q.get();
  }

  Future<List<FvCultivar>> cultivars(int commodityId) =>
      (database.select(database.fvCultivars)
            ..where((t) =>
                t.isActive.equals(true) & t.commodityId.equals(commodityId))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<FvCountry>> countries() => (database.select(database.fvCountries)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .get();

  Future<List<FvGrade>> grades() => (database.select(database.fvGrades)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.rank)]))
      .get();

  Future<List<FvDefectGroup>> defectGroups() =>
      (database.select(database.fvDefectGroups)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<FvSubDefect>> subDefects(int groupId) =>
      (database.select(database.fvSubDefects)
            ..where((t) => t.isActive.equals(true) & t.groupId.equals(groupId))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<FvInspectionPoint>> inspectionPoints() =>
      (database.select(database.fvInspectionPoints)
            ..where((t) => t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<List<FvRequirement>> requirements(String kind) =>
      (database.select(database.fvRequirements)
            ..where((t) => t.isActive.equals(true) & t.kind.equals(kind))
            ..orderBy([(t) => OrderingTerm(expression: t.description)]))
          .get();

  /// Tolerances for a commodity, joined to grade rank/name so the engine can
  /// order classes without a second query.
  Future<List<Tolerance>> tolerancesFor(int commodityId) async {
    final query = database.select(database.fvTolerances).join([
      innerJoin(
        database.fvGrades,
        database.fvGrades.id.equalsExp(database.fvTolerances.gradeId),
      ),
    ])
      ..where(database.fvTolerances.commodityId.equals(commodityId));

    final rows = await query.get();
    return [
      for (final row in rows)
        Tolerance(
          defectGroupId: row.readTable(database.fvTolerances).defectGroupId,
          gradeId: row.readTable(database.fvGrades).id,
          gradeRank: row.readTable(database.fvGrades).rank,
          gradeName: row.readTable(database.fvGrades).name,
          maxPercentage: row.readTable(database.fvTolerances).maxPercentage,
        ),
    ];
  }

  // --- Inspection persistence ---------------------------------------------

  Future<void> saveInspection(
    FvInspectionsCompanion inspection,
    List<FvInspectionDefectsCompanion> defects,
  ) async {
    await database.transaction(() async {
      await database
          .into(database.fvInspections)
          .insertOnConflictUpdate(inspection);
      final uuid = inspection.clientUuid.value;
      await (database.delete(database.fvInspectionDefects)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .go();
      for (final d in defects) {
        await database.into(database.fvInspectionDefects).insert(d);
      }
    });
  }

  Future<List<FvInspection>> savedInspections() =>
      (database.select(database.fvInspections)
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.inspectedAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .get();

  Future<int> pendingUploadCount() async {
    final rows = await (database.select(database.fvInspections)
          ..where((t) => t.isUploaded.equals(false)))
        .get();
    return rows.length;
  }

  Future<void> addPhoto(FvInspectionPhotosCompanion photo) =>
      database.into(database.fvInspectionPhotos).insert(photo);

  Future<List<FvInspectionPhoto>> photosFor(String uuid) =>
      (database.select(database.fvInspectionPhotos)
            ..where((t) => t.inspectionUuid.equals(uuid)))
          .get();

  void dispose() => _client.close();
}
