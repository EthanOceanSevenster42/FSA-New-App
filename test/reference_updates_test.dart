import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The "new records available" check that drives the home-screen prompt.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  EggsRepository repoReturning(
    Object body, {
    int status = 200,
    void Function(Uri)? onRequest,
  }) =>
      EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          onRequest?.call(request.url);
          return http.Response(
            body is String ? body : jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  group('summary wording', () {
    test('the headline number is the number that will be downloaded', () {
      // The prompt and the "Downloaded N records" confirmation must agree, so
      // the headline is always `total`, never the itemised subset.
      const updates = ReferenceUpdates(clients: 3, facilities: 2, total: 5);
      expect(updates.summary, '5 records: 3 clients and 2 facilities');
    });

    test('says "including" when the breakdown does not account for the whole',
        () {
      // 30 clients + 30 facilities out of 65 changed rows: the other 5 are
      // rules. Claiming "60 records" here would understate the download.
      const updates = ReferenceUpdates(clients: 30, facilities: 30, total: 65);
      expect(
        updates.summary,
        '65 records, including 30 clients and 30 facilities',
      );
    });

    test('is singular for one of each', () {
      const updates = ReferenceUpdates(clients: 1, facilities: 1, total: 2);
      expect(updates.summary, '2 records: 1 client and 1 facility');
    });

    test('mentions only the categories that changed', () {
      const updates = ReferenceUpdates(clients: 4, facilities: 0, total: 4);
      expect(updates.summary, '4 records: 4 clients');
    });

    test('falls back to a bare count when only rules changed', () {
      // Deviations and tolerances matter, but an inspector does not pick them
      // from a list, so naming them would mean nothing.
      const updates = ReferenceUpdates(clients: 0, facilities: 0, total: 7);
      expect(updates.summary, '7 records to download');
    });

    test('a single record is not pluralised', () {
      const updates = ReferenceUpdates(clients: 0, facilities: 0, total: 1);
      expect(updates.summary, '1 record to download');
    });

    test('nothing changed is not offered', () {
      const updates = ReferenceUpdates.none();
      expect(updates.hasAny, isFalse);
    });
  });

  group('checking the server', () {
    test('reads the counts it is given', () async {
      final repo = repoReturning({
        'counts': {'clients': 5, 'facilities': 2, 'deviations': 1},
        'total': 8,
      });

      final updates = await repo.pendingReferenceUpdates();

      expect(updates.clients, 5);
      expect(updates.facilities, 2);
      expect(updates.total, 8);
      expect(updates.hasAny, isTrue);
    });

    test('sends the stored cursor so only new rows are counted', () async {
      Uri? asked;
      await db.writeSyncState(
        EggsRepository.cursorKey,
        '2026-08-01T00:00:00Z',
      );
      final repo = repoReturning(
        {'counts': <String, int>{}, 'total': 0},
        onRequest: (uri) => asked = uri,
      );

      await repo.pendingReferenceUpdates();

      expect(asked!.path, '/api/eggs/reference/status/');
      expect(asked!.queryParameters['since'], '2026-08-01T00:00:00Z');
    });

    test('asks for everything when the device has never synced', () async {
      Uri? asked;
      final repo = repoReturning(
        {'counts': <String, int>{}, 'total': 0},
        onRequest: (uri) => asked = uri,
      );

      await repo.pendingReferenceUpdates();

      // No cursor means a first sync, which must pull the whole directory.
      expect(asked!.queryParameters.containsKey('since'), isFalse);
    });

    test('a server error throws rather than reporting "nothing new"',
        () async {
      // Silently showing no prompt would tell the inspector they are up to
      // date when nobody actually checked.
      final repo = repoReturning('{}', status: 503);
      expect(repo.pendingReferenceUpdates(), throwsA(isA<http.ClientException>()));
    });

    test('missing counts read as zero, not as a crash', () async {
      final repo = repoReturning({'total': 0});
      final updates = await repo.pendingReferenceUpdates();
      expect(updates.clients, 0);
      expect(updates.hasAny, isFalse);
    });
  });
}
