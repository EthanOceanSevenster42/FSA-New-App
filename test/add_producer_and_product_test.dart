import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Registering a producer or product from a raw or PMP inspection.
///
/// It has to work the way adding a facility does: the server hands out the
/// id and every handset gets the row on its next sync. Offline, the row is
/// still kept locally so the inspection can carry on.
void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.writeSyncState('auth.accessToken', 'token');
  });
  tearDown(() async => db.close());

  group('raw processed meat', () {
    test('a new producer takes the id the server gives it', () async {
      String? postedTo;
      final repo = RawRmpRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          postedTo = request.url.path;
          expect(jsonDecode(request.body), {'name': 'Tzaneen Meat Works'});
          return http.Response(
            jsonEncode({'id': 77, 'name': 'Tzaneen Meat Works',
                'is_active': true, 'updated_at': '2026-08-26T10:00:00Z'}),
            201,
          );
        }),
      );

      final producer = await repo.addProducer('  Tzaneen Meat Works ');

      expect(postedTo, '/api/rawrmp/producers/');
      expect(producer.id, 77);
      expect(producer.name, 'Tzaneen Meat Works');
      // And it is on the list the picker reads.
      expect((await repo.producers()).map((p) => p.name),
          contains('Tzaneen Meat Works'));
    });

    test('without signal the producer is kept under a local id', () async {
      final repo = RawRmpRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      final first = await repo.addProducer('Kroonstad Butchery');
      final second = await repo.addProducer('Bethlehem Meats');

      expect(first.id, -1);
      expect(second.id, -2, reason: 'local ids descend so they never collide');
      expect((await repo.producers()).length, 2);
    });

    test('a product is registered the same way', () async {
      final repo = RawRmpRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          expect(request.url.path, '/api/rawrmp/products/');
          return http.Response(
              jsonEncode({'id': 501, 'name': 'Beef Mince'}), 201);
        }),
      );

      final product = await repo.addProduct('Beef Mince');

      expect(product.id, 501);
      expect((await repo.products()).map((p) => p.name), contains('Beef Mince'));
    });
  });

  group('processed meat', () {
    test('a new producer takes the id the server gives it', () async {
      final repo = PmpRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          expect(request.url.path, '/api/pmp/producers/');
          return http.Response(
              jsonEncode({'id': 12, 'name': 'Eskort (Pty) Ltd'}), 201);
        }),
      );

      final producer = await repo.addProducer('Eskort (Pty) Ltd');

      expect(producer.id, 12);
      expect((await repo.producers()).map((p) => p.name),
          contains('Eskort (Pty) Ltd'));
    });

    test('a product is registered the same way', () async {
      final repo = PmpRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          expect(request.url.path, '/api/pmp/products/');
          return http.Response(
              jsonEncode({'id': 33, 'name': 'French Polony'}), 201);
        }),
      );

      final product = await repo.addProduct('French Polony');

      expect(product.id, 33);
      expect((await repo.products()).map((p) => p.name),
          contains('French Polony'));
    });
  });
}
