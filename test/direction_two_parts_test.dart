import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A direction is one notice that may carry two parts, each with its own date.
///
/// Modelling it as one type per record forced an inspection failing both
/// labelling and quality to be served as two notices with two reference
/// numbers, which is not the document the client receives.
void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });
  tearDown(() async => db.close());

  EggDirectionsCompanion direction({
    String uuid = 'dir-1',
    bool labelling = false,
    bool quality = false,
    DateTime? labelBy,
    DateTime? qualityBy,
    String? inspectionUuid,
  }) {
    final at = DateTime(2026, 8, 2, 9);
    return EggDirectionsCompanion.insert(
      clientUuid: uuid,
      inspectionUuid: Value(inspectionUuid),
      issuedAt: at,
      updatedAt: at,
      status: const Value('completed'),
      directionNumber: const Value('D-001'),
      labellingPart: Value(labelling),
      qualityPart: Value(quality),
      labelCorrectBy: Value(labelBy),
      qualityCorrectBy: Value(qualityBy),
      clientName: const Value('Acacia Farm Fresh Depot'),
    );
  }

  group('storing both parts on one notice', () {
    test('a direction carries labelling and quality together', () async {
      final repo = EggsRepository(baseUrl: 'http://example.test', database: db);
      await repo.saveDirection(
        direction(
          labelling: true,
          quality: true,
          labelBy: DateTime(2026, 8, 16),
          qualityBy: DateTime(2026, 8, 9),
        ),
      );

      final saved = await repo.directionByUuid('dir-1');

      expect(saved, isNotNull);
      expect(saved!.labellingPart, isTrue);
      expect(saved.qualityPart, isTrue);
      // Two deadlines on one notice: re-labelling and re-grading are not the
      // same job and are not given the same time.
      expect(saved.labelCorrectBy, DateTime(2026, 8, 16));
      expect(saved.qualityCorrectBy, DateTime(2026, 8, 9));
    });

    test('one notice, not two records', () async {
      final repo = EggsRepository(baseUrl: 'http://example.test', database: db);
      await repo.saveDirection(direction(labelling: true, quality: true));

      expect((await repo.savedDirections()).length, 1);
    });

    test('a quality-only direction has no labelling date', () async {
      final repo = EggsRepository(baseUrl: 'http://example.test', database: db);
      await repo.saveDirection(
        direction(quality: true, qualityBy: DateTime(2026, 8, 9)),
      );

      final saved = await repo.directionByUuid('dir-1');
      expect(saved!.qualityPart, isTrue);
      expect(saved.labellingPart, isFalse);
      expect(saved.labelCorrectBy, isNull);
    });
  });

  group('what reaches the server', () {
    test('both parts, both dates and the source inspection are sent', () async {
      Map<String, dynamic>? body;
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );
      await db.writeSyncState('auth.accessToken', 'token');
      await repo.saveDirection(
        direction(
          labelling: true,
          quality: true,
          labelBy: DateTime(2026, 8, 16),
          qualityBy: DateTime(2026, 8, 9),
          inspectionUuid: 'insp-7',
        ),
      );

      await repo.uploadDirection(
        (await repo.directionByUuid('dir-1'))!,
        token: 'token',
      );

      expect(body, isNotNull);
      expect(body!['labelling_part'], isTrue);
      expect(body!['quality_part'], isTrue);
      expect(body!['label_correct_by'], '2026-08-16');
      expect(body!['quality_correct_by'], '2026-08-09');
      // Without this the server cannot tie the notice to the inspection that
      // caused it, and the summary claims it was issued on its own.
      expect(body!['inspection_uuid'], 'insp-7');
      // The old single-type field must be gone, not merely ignored.
      expect(body!.containsKey('direction_type'), isFalse);
      expect(body!.containsKey('correct_by'), isFalse);
    });

    test('a part that is off sends no date for itself', () async {
      Map<String, dynamic>? body;
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );
      await db.writeSyncState('auth.accessToken', 'token');
      await repo.saveDirection(
        direction(quality: true, qualityBy: DateTime(2026, 8, 9)),
      );

      await repo.uploadDirection(
        (await repo.directionByUuid('dir-1'))!,
        token: 'token',
      );

      expect(body!['quality_part'], isTrue);
      expect(body!['labelling_part'], isFalse);
      expect(body!['label_correct_by'], isNull);
    });
  });

  group('coming back from the server', () {
    test('a downloaded direction keeps both parts and both dates', () async {
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          if (request.url.path.contains('directions')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'client_uuid': 'dir-remote',
                    'inspection_uuid': 'insp-9',
                    'issued_at': '2026-08-02T07:00:00Z',
                    'status': 'completed',
                    'direction_number': 'D-REMOTE',
                    'labelling_part': true,
                    'quality_part': true,
                    'label_correct_by': '2026-08-16',
                    'quality_correct_by': '2026-08-09',
                    'remarks': <int>[],
                    'client_name': 'Acacia Farm Fresh Depot',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );
      await db.writeSyncState('auth.accessToken', 'token');

      await repo.downloadMine(token: 'token');

      final saved = await repo.directionByUuid('dir-remote');
      expect(saved, isNotNull);
      expect(saved!.labellingPart, isTrue);
      expect(saved.qualityPart, isTrue);
      expect(saved.labelCorrectBy, isNotNull);
      expect(saved.qualityCorrectBy, isNotNull);
      expect(saved.inspectionUuid, 'insp-9');
    });
  });
}
