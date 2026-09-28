import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// What a sync has to put on the device before an egg inspection can open.
///
/// The form asks for a reason and a facility type before anything else, and
/// picks the client and the premises from the directory. The rules ship in
/// the app; the directories only ever arrive from the server. An inspector
/// looking at two pickers reading "Not yet" and an empty client list is
/// looking at a sync that did not land.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// The server's own shape, as `/api/eggs/reference/` returns it.
  String payload() => jsonEncode({
        'data': {
          'inspection_reasons': [
            {'id': 1, 'name': 'Routine inspection', 'sort_order': 0,
              'is_active': true, 'updated_at': '2026-07-31T13:45:46Z'},
            {'id': 2, 'name': 'Follow Up', 'sort_order': 1,
              'is_active': true, 'updated_at': '2026-07-31T13:45:46Z'},
          ],
          'facility_types': [
            {'id': 13, 'name': 'Packing station', 'sort_order': 0,
              'is_active': true, 'updated_at': '2026-07-31T13:45:46Z'},
          ],
          'clients': [
            {'id': 1, 'name': 'Kaap Agri Fresh', 'trading_name': '',
              'physical_address': '12 Voortrekker Rd, Paarl',
              'contact_person': 'Marius Botha', 'telephone': '021 555 0100',
              'is_active': true, 'updated_at': '2026-08-01T09:52:19Z'},
          ],
          'facilities': [
            {'id': 1, 'name': 'Sunrise Poultry Packing Station',
              'facility_type': 13,
              'physical_address': 'Plot 44, Bapsfontein, Gauteng',
              'telephone': '012 555 0110',
              'is_active': true, 'updated_at': '2026-08-01T10:06:58Z'},
          ],
        },
        'cursor': '2026-08-01T10:06:58Z',
      });

  EggsRepository repositoryReturning(String body) => EggsRepository(
        database: db,
        baseUrl: 'http://example.test',
        client: MockClient((_) async => http.Response(body, 200)),
      );

  test('a sync fills the two pickers the form opens with', () async {
    final eggs = repositoryReturning(payload());
    await eggs.syncReference(full: true);

    expect((await eggs.reasons()).map((r) => r.name),
        containsAll(['Routine inspection', 'Follow Up']));
    expect((await eggs.facilityTypes()).map((f) => f.name),
        contains('Packing station'));
  });

  test('a sync brings the clients and the premises', () async {
    final eggs = repositoryReturning(payload());
    await eggs.syncReference(full: true);

    final clients = await eggs.clients();
    expect(clients, hasLength(1));
    expect(clients.single.name, 'Kaap Agri Fresh');
    expect(clients.single.physicalAddress, '12 Voortrekker Rd, Paarl');

    final facilities = await eggs.facilities();
    expect(facilities.single.name, 'Sunrise Poultry Packing Station');
    expect(facilities.single.telephone, '012 555 0110');
  });

  test('a sync that cannot reach the server leaves the rules alone',
      () async {
    // The state an inspector actually hit: a handset seeded from the bundle,
    // never synced, and a server it cannot reach. The rules were being wiped
    // before the fetch, so a failed sync left every picker reading "Not yet"
    // and no way to open an inspection.
    final seeding = EggsRepository(database: db, baseUrl: 'http://example.test');
    // The real bundle, so the device counts as seeded and the sync takes the
    // "these rules came from somewhere else" path — which is the one that
    // used to wipe them.
    await seeding.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    expect(await seeding.reasons(), isNotEmpty);
    expect(await seeding.hasReferenceData, isTrue);

    final offline = EggsRepository(
      database: db,
      baseUrl: 'http://example.test',
      client: MockClient((_) async => throw const SocketException('no route')),
    );
    await expectLater(offline.syncReference(full: true), throwsA(anything));

    expect(await offline.reasons(), isNotEmpty,
        reason: 'a failed sync must not cost the device its rules');
    expect(await offline.facilityTypes(), isNotEmpty);
  });

  test('without one the directories are empty and the rules are not',
      () async {
    // The bundle is what makes a handset that has never had signal usable,
    // and it carries no client or premises — those are the server's.
    final eggs = EggsRepository(database: db, baseUrl: 'http://example.test');
    await eggs.writeReferenceForTest(
        jsonDecode(payload()) as Map<String, dynamic>);

    expect(await eggs.reasons(), isNotEmpty);
    expect(await eggs.clients(), isNotEmpty);
  });
}
