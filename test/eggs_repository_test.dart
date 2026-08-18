import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_user.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Covers the reads behind the summary screens and the administrator's bulk
/// upload-status corrections. All in-memory — no server, no files.
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

  Future<void> seedReference() async {
    await db.into(db.eggDeviationCategories).insert(
          EggDeviationCategoriesCompanion.insert(
            id: const Value(1),
            name: 'Shell',
          ),
        );
    await db.into(db.eggDeviations).insert(
          EggDeviationsCompanion.insert(
            id: const Value(10),
            categoryId: 1,
            description: 'Cracked shell',
          ),
        );
    await db.into(db.eggDeviations).insert(
          EggDeviationsCompanion.insert(
            id: const Value(11),
            categoryId: 1,
            description: 'Dirty shell',
          ),
        );
  }

  Future<void> insertInspection(
    String uuid,
    DateTime at, {
    bool uploaded = false,
  }) =>
      db.into(db.eggInspections).insert(
            EggInspectionsCompanion.insert(
              inspectorUsername: const Value('inspector1'),
              clientUuid: uuid,
              inspectedAt: at,
              updatedAt: at,
              status: const Value('completed'),
              isUploaded: Value(uploaded),
            ),
          );

  Future<void> insertSample(String uuid, int eggNumber, String deviationIds) =>
      db.into(db.eggSamples).insert(
            EggSamplesCompanion.insert(
              inspectionUuid: uuid,
              eggNumber: eggNumber,
              deviationIds: Value(deviationIds),
            ),
          );

  group('deviation tally', () {
    test('counts eggs affected, not ticks, and orders by frequency', () async {
      await seedReference();
      await insertInspection('a', DateTime(2026, 8, 1, 9));
      await insertSample('a', 1, '10,11');
      await insertSample('a', 2, '10');
      await insertSample('a', 3, '10');
      await insertSample('a', 4, '');

      final tally = await repo.deviationTally('a');

      expect(tally.map((t) => t.description), ['Cracked shell', 'Dirty shell']);
      expect(tally.first.eggsAffected, 3);
      expect(tally.last.eggsAffected, 1);
      expect(tally.first.category, 'Shell');
    });

    test('a deviation ticked twice on one egg still counts that egg once',
        () async {
      await seedReference();
      await insertInspection('a', DateTime(2026, 8, 1, 9));
      await insertSample('a', 1, '10,10,10');

      final tally = await repo.deviationTally('a');

      expect(tally.single.eggsAffected, 1);
    });

    test('an unknown deviation id is named, never silently dropped', () async {
      // A record can outlive the reference row it points at. Losing the row
      // from the summary would understate what was found.
      await insertInspection('a', DateTime(2026, 8, 1, 9));
      await insertSample('a', 1, '99');

      final tally = await repo.deviationTally('a');

      expect(tally.single.description, 'Deviation #99');
      expect(tally.single.eggsAffected, 1);
    });

    test('no deviations yields an empty tally, not a zero row', () async {
      await seedReference();
      await insertInspection('a', DateTime(2026, 8, 1, 9));
      await insertSample('a', 1, '');

      expect(await repo.deviationTally('a'), isEmpty);
    });
  });

  group('bulk upload-status corrections', () {
    test('re-queue only touches the selected date', () async {
      final target = DateTime(2026, 8, 1, 9);
      await insertInspection('today', target, uploaded: true);
      await insertInspection('yesterday', DateTime(2026, 7, 31, 9),
          uploaded: true);

      final changed = await repo.markInspectionsPendingForDate(target);

      expect(changed, 1);
      expect((await repo.inspectionByUuid('today'))!.isUploaded, isFalse);
      expect((await repo.inspectionByUuid('yesterday'))!.isUploaded, isTrue);
    });

    test('reports zero when nothing needed changing', () async {
      final target = DateTime(2026, 8, 1, 9);
      await insertInspection('a', target, uploaded: false);

      // Already pending, so re-queueing is a no-op and must say so rather
      // than claim it changed a record.
      expect(await repo.markInspectionsPendingForDate(target), 0);
    });

    test('marking as sent does not upload anything', () async {
      final target = DateTime(2026, 8, 1, 9);
      await insertInspection('a', target);

      final changed = await repo.markInspectionsUploadedForDate(target);

      expect(changed, 1);
      expect((await repo.inspectionByUuid('a'))!.isUploaded, isTrue);
    });

    test('matches on local calendar day, not UTC instant', () async {
      // 00:30 local on 1 August is still 31 July in UTC. Picking 1 August in
      // the date selector has to find it.
      final at = DateTime(2026, 8, 1, 0, 30);
      await insertInspection('a', at, uploaded: true);

      expect(await repo.markInspectionsPendingForDate(DateTime(2026, 8, 1)), 1);
    });

    test('a range covers both ends and everything between', () async {
      await insertInspection('before', DateTime(2026, 7, 31, 9), uploaded: true);
      await insertInspection('start', DateTime(2026, 8, 1, 9), uploaded: true);
      await insertInspection('middle', DateTime(2026, 8, 2, 9), uploaded: true);
      await insertInspection('end', DateTime(2026, 8, 3, 9), uploaded: true);
      await insertInspection('after', DateTime(2026, 8, 4, 9), uploaded: true);

      final changed = await repo.markInspectionsPendingBetween(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 3),
      );

      expect(changed, 3);
      // Inclusive at both ends: an administrator who picks 1 to 3 August and
      // sees three days of records expects all three corrected.
      expect((await repo.inspectionByUuid('start'))!.isUploaded, isFalse);
      expect((await repo.inspectionByUuid('middle'))!.isUploaded, isFalse);
      expect((await repo.inspectionByUuid('end'))!.isUploaded, isFalse);
      // And nothing outside it.
      expect((await repo.inspectionByUuid('before'))!.isUploaded, isTrue);
      expect((await repo.inspectionByUuid('after'))!.isUploaded, isTrue);
    });

    test('the closing day includes records captured late in it', () async {
      // 16:40 on the closing day is after 00:00 on that day, so comparing
      // instants rather than calendar days would drop it.
      await insertInspection('late', DateTime(2026, 8, 3, 16, 40));

      final changed = await repo.markInspectionsUploadedBetween(
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 3),
      );

      expect(changed, 1);
      expect((await repo.inspectionByUuid('late'))!.isUploaded, isTrue);
    });

    test('a single-day range behaves exactly like picking that date', () async {
      final target = DateTime(2026, 8, 1, 9);
      await insertInspection('a', target, uploaded: true);
      await insertInspection('b', DateTime(2026, 8, 2, 9), uploaded: true);

      expect(await repo.markInspectionsPendingBetween(target, target), 1);
      expect((await repo.inspectionByUuid('a'))!.isUploaded, isFalse);
      expect((await repo.inspectionByUuid('b'))!.isUploaded, isTrue);
    });

    test('directions are corrected independently of inspections', () async {
      final target = DateTime(2026, 8, 1, 9);
      await insertInspection('i', target, uploaded: true);
      await db.into(db.eggDirections).insert(
            EggDirectionsCompanion.insert(
              inspectorUsername: const Value('inspector1'),
              clientUuid: 'd',
              qualityPart: const Value(true),
              issuedAt: target,
              updatedAt: target,
              isUploaded: const Value(true),
            ),
          );

      expect(await repo.markDirectionsPendingForDate(target), 1);
      expect((await repo.directionByUuid('d'))!.isUploaded, isFalse);
      // The inspection on the same date must be untouched.
      expect((await repo.inspectionByUuid('i'))!.isUploaded, isTrue);
    });
  });

  group('reference name lookups', () {
    test('resolves ticked ids and ignores ids that no longer exist', () async {
      await db.into(db.eggRestrictedParticulars).insert(
            EggRestrictedParticularsCompanion.insert(
              id: const Value(1),
              keyword: 'Free range',
            ),
          );

      expect(await repo.restrictedParticularNames('1,404'), ['Free range']);
      expect(await repo.restrictedParticularNames(''), isEmpty);
    });
  });

  group('coordinates are sent at the precision the server stores', () {
    // The server column is DECIMAL(9, 6). A raw GPS double serialises with
    // full binary-float precision — 26.234899999999996, twenty digits — which
    // the server rejects. Because a failed upload is retried forever, such an
    // inspection never leaves the handset. This is that regression.
    Future<Map<String, dynamic>> capturedBody({
      required double? lat,
      required double? lon,
    }) async {
      Map<String, dynamic>? body;
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 201);
        }),
      );
      final now = DateTime(2026, 8, 1, 9);
      await db.into(db.eggInspections).insert(
            EggInspectionsCompanion.insert(
              inspectorUsername: const Value('inspector1'),
              clientUuid: 'coord',
              inspectedAt: now,
              updatedAt: now,
              status: const Value('completed'),
              latitude: Value(lat),
              longitude: Value(lon),
            ),
          );
      await repo.upload((await repo.inspectionByUuid('coord'))!, token: 't');
      return body!;
    }

    test('float noise is rounded to six decimal places', () async {
      final body = await capturedBody(
        lat: -29.118299999999998,
        lon: 26.234899999999996,
      );

      expect(body['latitude'], -29.1183);
      expect(body['longitude'], 26.2349);
      expect('${body['latitude']}'.split('.').last.length,
          lessThanOrEqualTo(6));
      expect('${body['longitude']}'.split('.').last.length,
          lessThanOrEqualTo(6));
    });

    test('a genuinely precise reading keeps six decimals', () async {
      // ~11 cm — finer than any phone GPS, so nothing real is lost.
      final body = await capturedBody(lat: -29.1183127, lon: 26.2348956);

      expect(body['latitude'], -29.118313);
      expect(body['longitude'], 26.234896);
    });

    test('no location captured stays null rather than becoming zero',
        () async {
      // 0,0 is a real place in the Gulf of Guinea. Sending it for "unknown"
      // would put every unlocated inspection there.
      final body = await capturedBody(lat: null, lon: null);

      expect(body['latitude'], isNull);
      expect(body['longitude'], isNull);
    });
  });

  group('egg measurements are sent at the precision the server stores', () {
    // mass_g, albumen_height_mm and haugh_unit are all DECIMAL(6, 2). The
    // Haugh unit is *computed* — 100 * log10(...) — so it is essentially
    // always 76.61237244897959 rather than 76.61. The server rejected that,
    // and because a failed upload retries forever, every real inspection with
    // a Haugh reading would have been stranded on the handset permanently.
    Future<List<Map<String, dynamic>>> capturedSamples({
      double? mass,
      double? albumen,
      double? haugh,
    }) async {
      Map<String, dynamic>? body;
      final repo = EggsRepository(
        baseUrl: 'http://example.test',
        database: db,
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 201);
        }),
      );
      final now = DateTime(2026, 8, 1, 9);
      await repo.saveInspection(
        EggInspectionsCompanion.insert(
          inspectorUsername: const Value('inspector1'),
          clientUuid: 'measure',
          inspectedAt: now,
          updatedAt: now,
              status: const Value('completed'),
        ),
        [
          EggSamplesCompanion.insert(
            inspectionUuid: 'measure',
            eggNumber: 1,
            massG: Value(mass),
            albumenHeightMm: Value(albumen),
            haughUnit: Value(haugh),
          ),
        ],
      );
      await repo.upload((await repo.inspectionByUuid('measure'))!, token: 't');
      return (body!['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
    }

    test('a computed Haugh unit is rounded to two decimals', () async {
      final samples = await capturedSamples(
        mass: 58.4,
        albumen: 6.2,
        haugh: 76.61237244897959,
      );

      expect(samples.single['haugh_unit'], 76.61);
    });

    test('float noise on a typed reading is rounded away', () async {
      // 5.4 + 0.7 in binary floating point is 6.1000000000000005.
      final samples = await capturedSamples(albumen: 6.1000000000000005);

      expect(samples.single['albumen_height_mm'], 6.1);
    });

    test('mass is rounded too', () async {
      final samples = await capturedSamples(mass: 58.44999999999999);
      expect(samples.single['mass_g'], 58.45);
    });

    test('an unmeasured egg stays null rather than becoming zero', () async {
      // Zero is a reading; absent is not. Sending 0 would drag the mean Haugh
      // unit down and trip the additional-samples rule.
      final samples = await capturedSamples();

      expect(samples.single['mass_g'], isNull);
      expect(samples.single['albumen_height_mm'], isNull);
      expect(samples.single['haugh_unit'], isNull);
    });

    test('nothing sent exceeds two decimal places', () async {
      final samples = await capturedSamples(
        mass: 61.987654321,
        albumen: 7.123456789,
        haugh: 82.987654321,
      );

      for (final key in ['mass_g', 'albumen_height_mm', 'haugh_unit']) {
        final text = '${samples.single[key]}';
        final decimals = text.contains('.') ? text.split('.').last.length : 0;
        expect(decimals, lessThanOrEqualTo(2), reason: '$key was $text');
      }
    });
  });

  group('missing records', () {
    test('a record that is gone reads as null rather than throwing', () async {
      expect(await repo.inspectionByUuid('nope'), isNull);
      expect(await repo.directionByUuid('nope'), isNull);
    });
  });

  group('SessionUser', () {
    test('recognises the administrator role regardless of casing', () {
      const user =
          SessionUser(userName: 'Ethan', roleName: 'system administrator');
      expect(user.isSystemAdministrator, isTrue);
    });

    test('an inspector is not an administrator', () {
      const user = SessionUser(userName: 'Ethan', roleName: 'Inspector');
      expect(user.isSystemAdministrator, isFalse);
    });

    test('a blank role is not an administrator', () {
      // A sign-in that returned no role must not grant the bulk actions.
      const user = SessionUser(userName: 'Ethan', roleName: '');
      expect(user.isSystemAdministrator, isFalse);
    });
  });
}
