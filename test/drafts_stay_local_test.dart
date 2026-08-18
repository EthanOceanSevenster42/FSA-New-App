import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A draft belongs to the handset capturing it, and nowhere else.
///
/// One reached the server through the Send button in Inspection Management,
/// which had no status check. From there every device downloaded it back as an
/// unfinished inspection — so discarding it worked, and then the banner
/// returned on the very next menu refresh, for good.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<EggInspection> saved(String uuid, String status) async {
    final at = DateTime(2026, 8, 2, 9);
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            inspectedAt: at,
            updatedAt: at,
            status: Value(status),
          ),
        );
    return (await (db.select(db.eggInspections)
              ..where((t) => t.clientUuid.equals(uuid)))
            .getSingle());
  }

  test('an unfinished inspection is refused by the upload', () async {
    var posted = 0;
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.method == 'POST') posted++;
        return http.Response(jsonEncode({'ok': true}), 201);
      }),
    );
    final draft = await saved('half', 'draft');

    expect(
      () => repo.upload(draft, token: 'token'),
      throwsA(isA<StateError>()),
      reason: 'half an inspection is not a record to distribute',
    );
    expect(posted, 0, reason: 'nothing should reach the server');
  });

  test('a completed inspection still uploads', () async {
    var posted = 0;
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.method == 'POST') posted++;
        return http.Response(jsonEncode({'ok': true}), 201);
      }),
    );
    final done = await saved('done', 'completed');

    await repo.upload(done, token: 'token');
    expect(posted, 1);
  });

  test('a draft on the server is not written back to the device', () async {
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('inspections')) {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'client_uuid': 'ghost',
                  'status': 'draft',
                  'inspected_at': '2026-08-02T07:00:00Z',
                  'samples': [],
                  'photos': [],
                },
                {
                  'client_uuid': 'real',
                  'status': 'completed',
                  'inspected_at': '2026-08-02T08:00:00Z',
                  'samples': [],
                  'photos': [],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );

    await repo.downloadMine(token: 'token');

    expect(await repo.inspectionByUuid('ghost'), isNull,
        reason: 'a discarded draft must not come back on the next refresh');
    expect(await repo.inspectionByUuid('real'), isNotNull);
    expect(await repo.drafts(), isEmpty);
  });

  test('discarding then refreshing leaves nothing behind', () async {
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        if (request.url.path.contains('inspections')) {
          // The server still holds it, as it did before the clean-up.
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'client_uuid': 'half',
                  'status': 'draft',
                  'inspected_at': '2026-08-02T07:00:00Z',
                  'samples': [],
                  'photos': [],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await saved('half', 'draft');

    await repo.deleteAllDrafts();
    expect(await repo.drafts(), isEmpty);

    // The menu refreshes, which downloads in the background.
    await repo.downloadMine(token: 'token');

    expect(await repo.drafts(), isEmpty,
        reason: 'this is exactly what kept bringing the banner back');
  });
}
