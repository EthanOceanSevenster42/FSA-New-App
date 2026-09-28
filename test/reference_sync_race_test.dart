import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// First launch, online: the app seeds the bundled rules and starts the first
/// server sync at the same moment. Whatever order the two land in, the tables
/// must end up holding the server's rows only — never the bundle's twins
/// beside them ("Jumbo" 11 next to "Jumbo" 5).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final serverBody = jsonEncode({
    'cursor': '2026-08-27T09:00:00Z',
    'counts': {},
    'data': {
      'sizes': [
        {'id': 5, 'name': 'Jumbo', 'min_mass_g': 66, 'max_mass_g': null},
        {'id': 6, 'name': 'Super Jumbo', 'min_mass_g': 73, 'max_mass_g': null},
      ],
      'grades': [
        {'id': 1, 'name': 'Grade 1', 'rank': 1},
      ],
    },
  });

  Future<List<(int, String)>> sizes() async =>
      (await db.select(db.eggSizes).get()).map((s) => (s.id, s.name)).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));

  test('bundle seeded while the first sync is downloading: server rows win',
      () async {
    final release = Completer<void>();
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((request) async {
        await release.future; // the download is slow
        return http.Response(serverBody, 200);
      }),
    );

    // Empty device, so the sync goes out as a full fetch...
    final sync = repo.syncReference();
    // ...and while it is in flight the bundle lands.
    await repo.seedRulesFromBundle();
    expect(await sizes(), isNotEmpty, reason: 'the bundle wrote its rows');
    release.complete();
    await sync;

    final rows = await sizes();
    expect(rows.where((r) => r.$2 == 'Jumbo'), hasLength(1),
        reason: 'no second Jumbo from the bundle');
    expect(rows, [(5, 'Jumbo'), (6, 'Super Jumbo')]);
    expect((await db.select(db.eggGrades).get()).map((g) => g.name), ['Grade 1']);
  });

  test('bundle seeded first, then the first sync: server rows win', () async {
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((_) async => http.Response(serverBody, 200)),
    );
    await repo.seedRulesFromBundle();
    await repo.syncReference();
    final rows = await sizes();
    expect(rows.where((r) => r.$2 == 'Jumbo'), hasLength(1));
    expect(rows, [(5, 'Jumbo'), (6, 'Super Jumbo')]);
  });

  test('sync finished first, then the bundle: the bundle stays out', () async {
    final repo = EggsRepository(
      baseUrl: 'http://prod.test',
      database: db,
      client: MockClient((_) async => http.Response(serverBody, 200)),
    );
    await repo.syncReference();
    expect(await repo.seedRulesFromBundle(), 0,
        reason: 'a device with rules does not get the bundle on top');
    expect(await sizes(), [(5, 'Jumbo'), (6, 'Super Jumbo')]);
  });
}
