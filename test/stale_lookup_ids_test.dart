import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/data/eggs_sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An inspection captured against the bundled rules' ids must still reach
/// the server once the server's own rows have replaced them.
///
/// The bundle numbers "Jumbo" 11 and "Grade 1" 4; the server numbers them 5
/// and 1. A handset that synced after the inspector picked from the bundled
/// twin uploads `Invalid pk "11" - object does not exist` — and the record
/// sat at "Pending upload (0 of 1 sent)" for good.
class _Online implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;
  @override
  Stream<bool> get onStatusChanged => const Stream<bool>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;

  // Bundled ids, straight from assets/reference/eggs_reference.json.
  const bundledJumbo = 11, bundledGrade1 = 4, bundledRetailer = 7;
  const bundledJumboDeviation = 39;
  // What the server numbers the same rows.
  const serverJumbo = 5, serverGrade1 = 1, serverRetailer = 1;
  const serverEggSizeCategory = 1, serverJumboDeviation = 2;


  /// What the server's reference endpoint hands back: its own rows, under
  /// its own ids. The refresh that follows a rejection rebuilds the tables
  /// from this, and the heal then matches names against it.
  Map<String, dynamic> serverReference() => {
        'cursor': '2026-08-27T09:00:00Z',
        'counts': {},
        'data': {
          'sizes': [
            {'id': serverJumbo, 'name': 'Jumbo', 'min_mass_g': 66, 'max_mass_g': null},
            {'id': 6, 'name': 'Super Jumbo', 'min_mass_g': 73, 'max_mass_g': null},
          ],
          'grades': [
            {'id': serverGrade1, 'name': 'Grade 1', 'rank': 1},
          ],
          'facility_types': [
            {'id': serverRetailer, 'name': 'Retailer/Distr. Center'},
          ],
          'tray_sizes': [
            {'id': 1, 'name': '6-Pack', 'egg_count': 6},
          ],
          'inspection_reasons': [
            {'id': 1, 'name': 'Inspection'},
          ],
          'deviation_categories': [
            {'id': serverEggSizeCategory, 'name': 'Egg Size'},
          ],
          'deviations': [
            {
              'id': serverJumboDeviation,
              'category': serverEggSizeCategory,
              'description': 'Jumbo - <= 2g of Min. Weight',
            },
          ],
        },
      };

  /// The tables as they stand after a sync: the server's rows only.
  Future<void> serverRows() async {
    await db.into(db.eggSizes).insert(EggSizesCompanion.insert(
        id: const Value(serverJumbo), name: 'Jumbo', minMassG: 66));
    await db.into(db.eggSizes).insert(EggSizesCompanion.insert(
        id: const Value(6), name: 'Super Jumbo', minMassG: 73));
    await db.into(db.eggGrades).insert(EggGradesCompanion.insert(
        id: const Value(serverGrade1), name: 'Grade 1', rank: 1));
    await db.into(db.eggFacilityTypes).insert(EggFacilityTypesCompanion.insert(
        id: const Value(serverRetailer), name: 'Retailer/Distr. Center'));
    await db.into(db.eggTraySizes).insert(EggTraySizesCompanion.insert(
        id: const Value(1), name: '6-Pack', eggCount: 6));
    await db.into(db.eggInspectionReasons).insert(
        EggInspectionReasonsCompanion.insert(id: const Value(1), name: 'Inspection'));
    await db.into(db.eggDeviationCategories).insert(EggDeviationCategoriesCompanion.insert(
        id: const Value(serverEggSizeCategory), name: 'Egg Size'));
    await db.into(db.eggDeviations).insert(EggDeviationsCompanion.insert(
        id: const Value(serverJumboDeviation),
        categoryId: serverEggSizeCategory,
        description: 'Jumbo - <= 2g of Min. Weight'));
    await db.writeSyncState(EggsRepository.referenceOriginKey, 'http://prod.test');
  }

  Future<void> staleInspection(String uuid) async {
    final at = DateTime(2026, 8, 27, 9);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          inspectorUsername: const Value('Ethan'),
          clientUuid: uuid,
          inspectedAt: at,
          updatedAt: at,
          status: const Value('completed'),
          facilityTypeId: const Value(bundledRetailer),
          reasonId: const Value(1), // the same on both sides
          traySizeId: const Value(1),
          declaredSizeId: const Value(bundledJumbo),
          declaredGradeId: const Value(bundledGrade1),
          determinedGradeId: const Value(bundledGrade1),
        ));
    await db.into(db.eggSamples).insert(EggSamplesCompanion.insert(
          inspectionUuid: uuid,
          eggNumber: 1,
          massG: const Value(70),
          sizeId: const Value(bundledJumbo),
          gradeId: const Value(bundledGrade1),
          deviationIds: const Value('$bundledJumboDeviation'),
        ));
  }

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.writeSyncState(EggsRepository.sessionUserKey, 'Ethan');
    await db.writeSyncState('auth.accessToken', 'token');
    await serverRows();
  });
  tearDown(() async => db.close());

  test('a record carrying bundled ids is re-pointed by name and goes up',
      () async {
    final posted = <Map<String, dynamic>>[];
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('reference')) {
          return http.Response(jsonEncode(serverReference()), 200);
        }
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          posted.add(body);
          // The server as it really answers.
          if (body['declared_size'] != serverJumbo) {
            return http.Response(
                jsonEncode({
                  'declared_size': [
                    'Invalid pk "${body['declared_size']}" - object does not exist.'
                  ]
                }),
                400);
          }
          return http.Response(jsonEncode({'ok': true}), 201);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await staleInspection('insp-stale');
    final service = EggsSyncService(repository: repo, connectivity: _Online());

    final sent = await service.sendNow((await repo.inspectionByUuid('insp-stale'))!);

    expect(sent, isTrue, reason: 'the record must not stay pending');
    expect(posted, hasLength(2), reason: 'rejected once, healed, retried');
    final retry = posted.last;
    expect(retry['declared_size'], serverJumbo);
    expect(retry['declared_grade'], serverGrade1);
    expect(retry['determined_grade'], serverGrade1);
    expect(retry['facility_type'], serverRetailer);
    expect(retry['reason'], 1, reason: 'an id the server has is left alone');
    final sample = (retry['samples'] as List).single as Map<String, dynamic>;
    expect(sample['size'], serverJumbo);
    expect(sample['grade'], serverGrade1);
    expect(sample['deviations'], [serverJumboDeviation]);

    // And the stored record now agrees with what was sent.
    final stored = (await repo.inspectionByUuid('insp-stale'))!;
    expect(stored.declaredSizeId, serverJumbo);
    expect(stored.isUploaded, isTrue);
    await service.dispose();
  });

  test('ids the server already knows are not touched', () async {
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final at = DateTime(2026, 8, 27, 9);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          inspectorUsername: const Value('Ethan'),
          clientUuid: 'insp-ok',
          inspectedAt: at,
          updatedAt: at,
          status: const Value('completed'),
          declaredSizeId: const Value(serverJumbo),
          declaredGradeId: const Value(serverGrade1),
        ));
    expect(await repo.repointLookupIds('insp-ok'), isFalse);
    final stored = (await repo.inspectionByUuid('insp-ok'))!;
    expect(stored.declaredSizeId, serverJumbo);
    expect(stored.declaredGradeId, serverGrade1);
  });

  test('an id nobody can name is left as it is, and the rejection reported',
      () async {
    var posts = 0;
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('reference')) {
          return http.Response(jsonEncode(serverReference()), 200);
        }
        if (request.method == 'POST') {
          posts++;
          return http.Response(
              jsonEncode({'declared_size': ['Invalid pk "999" - object does not exist.']}),
              400);
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    final at = DateTime(2026, 8, 27, 9);
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          inspectorUsername: const Value('Ethan'),
          clientUuid: 'insp-odd',
          inspectedAt: at,
          updatedAt: at,
          status: const Value('completed'),
          declaredSizeId: const Value(999),
        ));
    final service = EggsSyncService(repository: repo, connectivity: _Online());
    final sent = await service.sendNow((await repo.inspectionByUuid('insp-odd'))!);
    expect(sent, isFalse);
    expect(service.lastOutcome, SendOutcome.rejected);
    expect(posts, lessThanOrEqualTo(2), reason: 'no endless retry loop');
    expect((await repo.inspectionByUuid('insp-odd'))!.declaredSizeId, 999);
    await service.dispose();
  });
}
