import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An inspection pulled down from the server must bring everything the
/// summary screen shows — photographs, location, and the fields that were
/// silently dropped before.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const uuid = '11111111-2222-3333-4444-555555555555';

  EggsRepository repoServing(List<Map<String, dynamic>> photos) =>
      EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          if (request.url.path == '/api/eggs/inspections/') {
            return http.Response(
              jsonEncode([
                {
                  'client_uuid': uuid,
                  'inspected_at': '2026-08-01T09:00:00Z',
                  'status': 'completed',
                  'client_name': 'Sunrise Poultry Farm',
                  'samples': <dynamic>[],
                  'photos': photos,
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode([]), 200,
              headers: {'content-type': 'application/json'});
        }),
      );

  test('photographs come down with the inspection', () async {
    final repo = repoServing([
      {
        'kind': 'label',
        'image': '/media/eggs/2026/08/label.jpg',
        'caption': 'outer label',
        'captured_at': '2026-08-01T08:55:00Z',
      },
      {
        'kind': 'deviation',
        'image': '/media/eggs/2026/08/crack.jpg',
        'caption': '',
        'captured_at': '2026-08-01T09:05:00Z',
      },
    ]);

    await repo.downloadMine(token: 'token');
    final photos = await repo.photosFor(uuid);

    expect(photos.length, 2);
    expect(photos.map((p) => p.kind).toSet(), {'label', 'deviation'});
  });

  test('a relative path is stored absolute so it can be fetched', () async {
    final repo = repoServing([
      {
        'kind': 'label',
        'image': '/media/eggs/2026/08/label.jpg',
        'captured_at': '2026-08-01T08:55:00Z',
      },
    ]);

    await repo.downloadMine(token: 'token');

    expect(
      (await repo.photosFor(uuid)).single.filePath,
      'http://example.test/media/eggs/2026/08/label.jpg',
    );
  });

  test('an absolute URL is left alone', () async {
    final repo = repoServing([
      {
        'kind': 'egg',
        'image': 'https://cdn.example.test/x.jpg',
        'captured_at': '2026-08-01T08:55:00Z',
      },
    ]);

    await repo.downloadMine(token: 'token');

    expect(
      (await repo.photosFor(uuid)).single.filePath,
      'https://cdn.example.test/x.jpg',
    );
  });

  test('the capture time is kept, not replaced by the download time',
      () async {
    final repo = repoServing([
      {
        'kind': 'label',
        'image': '/media/x.jpg',
        'captured_at': '2026-08-01T08:55:00Z',
      },
    ]);

    await repo.downloadMine(token: 'token');
    final photo = (await repo.photosFor(uuid)).single;

    expect(photo.capturedAt.toUtc(), DateTime.utc(2026, 8, 1, 8, 55));
  });

  test('a downloaded photo is already marked uploaded', () async {
    final repo = repoServing([
      {'kind': 'label', 'image': '/media/x.jpg'},
    ]);

    await repo.downloadMine(token: 'token');

    // It came from the server, so re-sending it would be pointless work.
    expect((await repo.photosFor(uuid)).single.isUploaded, isTrue);
  });

  test('locally captured photos are never replaced by server copies',
      () async {
    // This handset took the photo; its row points at a file on this device.
    // Overwriting that with a URL would lose the local original.
    final at = DateTime(2026, 8, 1, 9);
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            inspectedAt: at,
            updatedAt: at,
            isUploaded: const Value(true),
          ),
        );
    await db.into(db.eggPhotos).insert(
          EggPhotosCompanion.insert(
            inspectionUuid: uuid,
            kind: 'label',
            filePath: '/data/user/0/za.co.eclick.fsa_app/mine.jpg',
            capturedAt: at,
          ),
        );

    final repo = repoServing([
      {'kind': 'label', 'image': '/media/theirs.jpg'},
    ]);
    await repo.downloadMine(token: 'token');

    final photos = await repo.photosFor(uuid);
    expect(photos.length, 1);
    expect(photos.single.filePath, contains('mine.jpg'));
  });

  test('a photo row with no image is skipped rather than stored blank',
      () async {
    final repo = repoServing([
      {'kind': 'label', 'image': ''},
      {'kind': 'egg', 'image': '/media/ok.jpg'},
    ]);

    await repo.downloadMine(token: 'token');

    expect((await repo.photosFor(uuid)).length, 1);
  });

  group('every field the summary shows survives the download', () {
    EggsRepository repoServingInspection(Map<String, dynamic> extra) =>
        EggsRepository(
          baseUrl: 'http://example.test',
          database: db,
          client: MockClient((request) async {
            if (request.url.path == '/api/eggs/inspections/') {
              return http.Response(
                jsonEncode([
                  {
                    'client_uuid': uuid,
                    'inspected_at': '2026-08-01T09:00:00Z',
                    'status': 'completed',
                    'samples': <dynamic>[],
                    'photos': <dynamic>[],
                    ...extra,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(jsonEncode([]), 200,
                headers: {'content-type': 'application/json'});
          }),
        );

    test('the location is kept, not reported as never captured', () async {
      // Django serialises DecimalField as a *string*, so a plain cast dropped
      // every coordinate and the summary read "Not captured".
      final repo = repoServingInspection({
        'latitude': '-29.118312',
        'longitude': '26.234896',
      });

      await repo.downloadMine(token: 'token');
      final saved = (await repo.inspectionByUuid(uuid))!;

      expect(saved.latitude, closeTo(-29.118312, 0.000001));
      expect(saved.longitude, closeTo(26.234896, 0.000001));
    });

    test('a coordinate sent as a JSON number also parses', () async {
      final repo = repoServingInspection({'latitude': -29.5, 'longitude': 26.5});
      await repo.downloadMine(token: 'token');
      final saved = (await repo.inspectionByUuid(uuid))!;

      expect(saved.latitude, -29.5);
    });

    test('an unlocated record stays null rather than becoming zero',
        () async {
      // 0,0 is a real place in the Gulf of Guinea.
      final repo = repoServingInspection({'latitude': null, 'longitude': null});
      await repo.downloadMine(token: 'token');
      final saved = (await repo.inspectionByUuid(uuid))!;

      expect(saved.latitude, isNull);
      expect(saved.longitude, isNull);
    });

    test('labelling failures and restricted particulars come down', () async {
      final repo = repoServingInspection({
        'failed_requirements': [9, 8, 10],
        'restricted_particulars': [5, 2],
      });

      await repo.downloadMine(token: 'token');
      final saved = (await repo.inspectionByUuid(uuid))!;

      expect(saved.failedRequirementIds, '9,8,10');
      expect(saved.restrictedParticularIds, '5,2');
    });

    test('best before, representative and comments come down', () async {
      final repo = repoServingInspection({
        'best_before': '2026-08-19',
        'representative_name': 'T. Mokoena',
        'non_conformance_comments': 'Shell damage on two eggs.',
        'pasteurised_present': true,
        'haugh_not_required': true,
        'override_reason': 'Inspector judgement',
      });

      await repo.downloadMine(token: 'token');
      final saved = (await repo.inspectionByUuid(uuid))!;

      expect(saved.bestBefore, DateTime(2026, 8, 19));
      expect(saved.representativeName, 'T. Mokoena');
      expect(saved.nonConformanceComments, 'Shell damage on two eggs.');
      expect(saved.pasteurisedPresent, isTrue);
      expect(saved.haughNotRequired, isTrue);
      expect(saved.overrideReason, 'Inspector judgement');
    });
  });

  group('directions', () {
    EggsRepository repoServingDirection(Map<String, dynamic> extra) =>
        EggsRepository(
          baseUrl: 'http://example.test',
          database: db,
          client: MockClient((request) async {
            if (request.url.path == '/api/eggs/directions/') {
              return http.Response(
                jsonEncode([
                  {
                    'client_uuid': 'dir-uuid-1',
                    'direction_type': 'quality',
                    'issued_at': '2026-08-01T09:00:00Z',
                    'status': 'completed',
                    ...extra,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(jsonEncode([]), 200,
                headers: {'content-type': 'application/json'});
          }),
        );

    test('the link back to the source inspection survives', () async {
      // Without it the summary claims every downloaded direction was issued
      // on its own, and the "open the inspection" route disappears.
      final repo = repoServingDirection({'inspection_uuid': uuid});

      await repo.downloadMine(token: 'token');

      expect((await repo.directionByUuid('dir-uuid-1'))!.inspectionUuid, uuid);
    });

    test('a direction issued on its own has no link', () async {
      final repo = repoServingDirection({'inspection_uuid': null});
      await repo.downloadMine(token: 'token');

      expect(
        (await repo.directionByUuid('dir-uuid-1'))!.inspectionUuid,
        isNull,
      );
    });

    test('the location comes down', () async {
      final repo = repoServingDirection({
        'latitude': '-29.118312',
        'longitude': '26.234896',
      });

      await repo.downloadMine(token: 'token');
      final saved = (await repo.directionByUuid('dir-uuid-1'))!;

      expect(saved.latitude, closeTo(-29.118312, 0.000001));
      expect(saved.longitude, closeTo(26.234896, 0.000001));
    });
  });
}
