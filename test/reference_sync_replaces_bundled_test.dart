import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The first sync against the server must leave the tables holding the
/// server's rows and nothing else.
///
/// The rules ship inside the APK under their own ids so a handset works before
/// it has signal. The server numbers the same rows differently, and a sync
/// that only upserts by id leaves both sets side by side: "Jumbo" twice,
/// "Grade 1" twice, and an inspector picking the wrong twin captures ids the
/// server will refuse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Map<String, dynamic> serverReference({String? cursor}) => {
        'cursor': cursor ?? '2026-08-27T09:00:00Z',
        'counts': {},
        'data': {
          'sizes': [
            {'id': 1, 'name': 'Small', 'min_mass_g': 33, 'max_mass_g': 43, 'sort_order': 1},
            {'id': 5, 'name': 'Jumbo', 'min_mass_g': 66, 'max_mass_g': null, 'sort_order': 5},
            {'id': 6, 'name': 'Super Jumbo', 'min_mass_g': 73, 'max_mass_g': null, 'sort_order': 6},
          ],
          'grades': [
            {'id': 1, 'name': 'Grade 1', 'rank': 1},
            {'id': 2, 'name': 'Grade 2', 'rank': 2},
          ],
          'inspection_reasons': [
            {'id': 1, 'name': 'Inspection'},
            {'id': 2, 'name': 'Follow-up Inspection'},
          ],
        },
      };

  EggsRepository repo(http.Client client) =>
      EggsRepository(baseUrl: 'http://prod.test', database: db, client: client);

  Future<List<String>> sizeNames() async =>
      (await db.select(db.eggSizes).get()).map((s) => s.name).toList()..sort();

  test('the bundled rules are replaced by the server rows, not joined by them',
      () async {
    final r = repo(MockClient((request) async {
      if (request.url.path.contains('reference')) {
        return http.Response(jsonEncode(serverReference()), 200);
      }
      return http.Response('{}', 404);
    }));

    await r.seedRulesFromBundle();
    final bundled = await sizeNames();
    expect(bundled, contains('Jumbo'), reason: 'the bundle has the rules');

    await r.syncReference();

    final names = await sizeNames();
    expect(names.where((n) => n == 'Jumbo'), hasLength(1),
        reason: 'one Jumbo, the server\'s');
    expect(names.where((n) => n == 'Super Jumbo'), hasLength(1));
    expect(names, ['Jumbo', 'Small', 'Super Jumbo'],
        reason: 'only what the server sent');
    final jumbo = (await db.select(db.eggSizes).get()).singleWhere((s) => s.name == 'Jumbo');
    expect(jumbo.id, 5, reason: 'the server\'s id, not the bundle\'s 11');
    expect((await db.select(db.eggGrades).get()).map((g) => g.name).toList()..sort(),
        ['Grade 1', 'Grade 2']);
  });

  test('a later delta sync only adds and updates, never wipes', () async {
    var calls = 0;
    final r = repo(MockClient((request) async {
      calls++;
      if (request.url.queryParameters.containsKey('since')) {
        // The delta: one renamed size, nothing else.
        return http.Response(
            jsonEncode({
              'cursor': '2026-08-27T10:00:00Z',
              'counts': {},
              'data': {
                'sizes': [
                  {'id': 5, 'name': 'Jumbo (renamed)', 'min_mass_g': 66, 'max_mass_g': null, 'sort_order': 5},
                ],
              },
            }),
            200);
      }
      return http.Response(jsonEncode(serverReference()), 200);
    }));

    await r.syncReference(); // full
    await r.syncReference(); // delta, cursor set by the first
    expect(calls, 2);

    final names = await sizeNames();
    expect(names, ['Jumbo (renamed)', 'Small', 'Super Jumbo'],
        reason: 'the other rows survive a delta');
    expect((await db.select(db.eggGrades).get()), hasLength(2));
    expect((await db.select(db.eggInspectionReasons).get()), hasLength(2));
  });

  test('a full sync that fails leaves the old rows in place', () async {
    var first = true;
    final r = repo(MockClient((request) async {
      if (first) {
        first = false;
        return http.Response(jsonEncode(serverReference()), 200);
      }
      return http.Response('boom', 500);
    }));
    await r.syncReference();
    expect(await sizeNames(), ['Jumbo', 'Small', 'Super Jumbo']);

    await expectLater(r.syncReference(full: true), throwsA(anything));
    expect(await sizeNames(), ['Jumbo', 'Small', 'Super Jumbo'],
        reason: 'a failed download must never empty the handset');
  });
}
