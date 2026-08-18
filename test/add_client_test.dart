import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Registering a client or premises met in the field.
///
/// Inspectors arrive at places the directory does not hold. The id must come
/// from the server, never be invented locally: a made-up id is what produced
/// "Invalid pk … object does not exist" on every subsequent upload.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('a new client takes the id the server gives it', () async {
    Map<String, dynamic>? posted;
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((request) async {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 4821, 'updated_at': '2026-08-02T13:00:00Z'}),
          201,
        );
      }),
    );
    await db.writeSyncState('auth.accessToken', 'token');

    final client = await repo.addClient(
      name: 'Karoo Free Range Eggs',
      physicalAddress: '12 Mill Road',
      telephone: '051 555 1234',
    );

    expect(client.id, 4821, reason: 'the server owns the numbering');
    expect(client.name, 'Karoo Free Range Eggs');
    expect(posted!['name'], 'Karoo Free Range Eggs');
    expect(posted!['physical_address'], '12 Mill Road');

    // …and it is immediately searchable on the device.
    expect((await repo.clients()).map((c) => c.name),
        contains('Karoo Free Range Eggs'));
  });

  test('an existing name comes back as the same record, not a duplicate',
      () async {
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response(
            // The server upserts on the name and answers 200, not 201.
            jsonEncode({'id': 77, 'updated_at': ''}),
            200,
          )),
    );
    await db.writeSyncState('auth.accessToken', 'token');

    final first = await repo.addClient(name: 'Sunrise Poultry');
    final again = await repo.addClient(name: 'Sunrise Poultry');

    expect(first.id, 77);
    expect(again.id, 77);
    expect((await repo.clients()).length, 1, reason: 'one client, not two');
  });

  group('with no signal', () {
    test('the client is still usable, with an id that cannot collide',
        () async {
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((_) async => throw const SocketishFailure()),
      );
      await db.writeSyncState('auth.accessToken', 'token');

      final client = await repo.addClient(name: 'Roadside Depot');

      expect(client.name, 'Roadside Depot');
      expect(client.id, lessThan(0),
          reason: 'negative marks it as not yet registered, and keeps it out '
              'of the range the server allocates');
      expect((await repo.clients()).length, 1);
    });

    test('two offline clients do not collide with each other', () async {
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((_) async => throw const SocketishFailure()),
      );

      final a = await repo.addClient(name: 'Depot One');
      final b = await repo.addClient(name: 'Depot Two');

      expect(a.id, isNot(b.id));
      expect((await repo.clients()).length, 2);
    });
  });

  test('premises register the same way', () async {
    final repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async =>
          http.Response(jsonEncode({'id': 91, 'updated_at': ''}), 201)),
    );
    await db.writeSyncState('auth.accessToken', 'token');

    final facility = await repo.addFacility(
      name: 'Bloemfontein Packhouse',
      physicalAddress: '5 Station Street',
    );

    expect(facility.id, 91);
    expect((await repo.facilities()).map((f) => f.name),
        contains('Bloemfontein Packhouse'));
  });
}

/// Stands in for "there is no network", which is the ordinary case here.
class SocketishFailure implements Exception {
  const SocketishFailure();
}
