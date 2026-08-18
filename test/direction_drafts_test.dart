import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A direction can be picked back up, the way an inspection can.
///
/// A notice is written standing next to the consignment, and the app can be
/// killed for memory at any point. Until now a half-written direction was
/// simply gone.
void main() {
  late LocalDatabase db;
  late EggsRepository repo;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(baseUrl: 'http://example.test', database: db);
    // Work on a handset now belongs to whoever captured it, and the app
    // has no way to capture anything without signing in first.
    await db.writeSyncState(EggsRepository.sessionUserKey, 'inspector1');
  });
  tearDown(() async => db.close());

  Future<void> direction(
    String uuid,
    DateTime at, {
    String status = 'draft',
    String client = 'Acacia Farm Fresh',
  }) async {
    await repo.saveDirection(
      EggDirectionsCompanion.insert(
        clientUuid: uuid,
        issuedAt: at,
        updatedAt: at,
        status: Value(status),
        clientName: Value(client),
        directionNumber: const Value('D-1'),
        qualityPart: const Value(true),
      ),
    );
  }

  group('picking one back up', () {
    test('an unfinished direction is offered back', () async {
      await direction('half', DateTime(2026, 8, 2, 9));

      final drafts = await repo.directionDrafts();

      expect(drafts.length, 1);
      expect(drafts.single.clientName, 'Acacia Farm Fresh');
    });

    test('a finished one is not', () async {
      await direction('done', DateTime(2026, 8, 2, 9), status: 'completed');

      expect(await repo.directionDrafts(), isEmpty);
    });

    test('the most recent comes first, for Resume', () async {
      await direction('older', DateTime(2026, 8, 2, 8), client: 'Older');
      await direction('newer', DateTime(2026, 8, 2, 12), client: 'Newer');

      expect((await repo.directionDrafts()).first.clientName, 'Newer');
    });

    test('what was entered survives', () async {
      await repo.saveDirection(
        EggDirectionsCompanion.insert(
          clientUuid: 'half',
          issuedAt: DateTime(2026, 8, 2, 9),
          updatedAt: DateTime(2026, 8, 2, 9),
          status: const Value('draft'),
          directionNumber: const Value('D-77'),
          labellingPart: const Value(true),
          qualityPart: const Value(true),
          labelCorrectBy: Value(DateTime(2026, 9, 30)),
          qualityCorrectBy: Value(DateTime(2026, 9, 15)),
          remarkIds: const Value('1,3'),
          additionalRemarks: const Value('Half written'),
        ),
      );

      final back = await repo.directionByUuid('half');

      expect(back!.directionNumber, 'D-77');
      expect(back.labellingPart, isTrue);
      expect(back.qualityPart, isTrue);
      expect(back.labelCorrectBy, DateTime(2026, 9, 30));
      expect(back.remarkIds, '1,3');
      expect(back.additionalRemarks, 'Half written');
    });
  });

  group('discarding', () {
    test('removes every unfinished direction at once', () async {
      await direction('a', DateTime(2026, 8, 2, 8));
      await direction('b', DateTime(2026, 8, 2, 9));
      await direction('c', DateTime(2026, 8, 2, 10));

      expect(await repo.deleteAllDirectionDrafts(), 3);
      expect(await repo.directionDrafts(), isEmpty);
    });

    test('leaves finished notices alone', () async {
      await direction('half', DateTime(2026, 8, 2, 8));
      await direction('done', DateTime(2026, 8, 2, 9), status: 'completed');

      expect(await repo.deleteAllDirectionDrafts(), 1);
      expect(await repo.directionByUuid('done'), isNotNull);
    });
  });

  group('a draft stays on the device', () {
    test('the upload refuses it', () async {
      var posted = 0;
      final r = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          if (request.method == 'POST') posted++;
          return http.Response(jsonEncode({'ok': true}), 201);
        }),
      );
      await direction('half', DateTime(2026, 8, 2, 9));
      final draft = await r.directionByUuid('half');

      expect(
        () => r.uploadDirection(draft!, token: 'token'),
        throwsA(isA<StateError>()),
      );
      expect(posted, 0);
    });

    test('a draft on the server is not written back', () async {
      final r = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          if (request.url.path.contains('directions')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'client_uuid': 'ghost',
                    'status': 'draft',
                    'issued_at': '2026-08-02T07:00:00Z',
                    'remarks': <int>[],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'results': []}), 200);
        }),
      );

      await r.downloadMine(token: 'token');

      expect(await r.directionByUuid('ghost'), isNull,
          reason: 'a discarded draft must not come back');
    });
  });
}
