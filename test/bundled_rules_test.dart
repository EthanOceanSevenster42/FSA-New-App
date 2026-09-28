import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The inspection rules ship inside the app, so a handset that has never had
/// signal can still capture an inspection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late EggsRepository repo;
  var networkCalls = 0;

  setUp(() {
    networkCalls = 0;
    db = LocalDatabase(NativeDatabase.memory());
    repo = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      // Any network use during seeding is a failure of the whole point.
      client: MockClient((_) async {
        networkCalls++;
        return http.Response('{}', 500);
      }),
    );
  });

  tearDown(() async => db.close());

  test('the bundled asset is present and parses', () async {
    final raw = await rootBundle.loadString(EggsRepository.bundledRulesAsset);
    final body = jsonDecode(raw) as Map<String, dynamic>;

    expect(body['data'], isA<Map<String, dynamic>>());
  });

  test('a fresh device gets its rules without touching the network', () async {
    expect(await repo.hasReferenceData, isFalse);

    final written = await repo.seedRulesFromBundle();

    expect(written, greaterThan(0));
    expect(networkCalls, 0, reason: 'seeding must work with no signal at all');
    expect(await repo.hasReferenceData, isTrue);
  });

  test('every rule set the capture form needs is populated', () async {
    await repo.seedRulesFromBundle();

    // Without any one of these the form cannot size, grade or validate an egg.
    expect(await repo.sizeBands(), isNotEmpty, reason: 'sizes');
    expect(await repo.gradeRefs(), isNotEmpty, reason: 'grades');
    expect(await repo.deviationRefs(), isNotEmpty, reason: 'deviations');
    expect(await repo.deviationCategories(), isNotEmpty, reason: 'categories');
    expect(await repo.traySizes(), isNotEmpty, reason: 'tray sizes');
    expect(await repo.facilityTypes(), isNotEmpty, reason: 'facility types');
    expect(await repo.reasons(), isNotEmpty, reason: 'inspection reasons');
    expect(await repo.restrictedParticulars(), isNotEmpty,
        reason: 'restricted particulars');
    expect(await repo.requirements('label_pack'), isNotEmpty,
        reason: 'labelling requirements');
    expect(await repo.directionRemarks('quality'), isNotEmpty,
        reason: 'quality direction remarks');
  });

  test('sizes carry real mass bands, not placeholders', () async {
    await repo.seedRulesFromBundle();
    final bands = await repo.sizeBands();

    for (final band in bands) {
      expect(band.name, isNotEmpty);
      expect(band.minMassG, greaterThan(0),
          reason: '${band.name} has no lower bound');
    }

    // The ladder is the mass bands only. "Mixed Size" is declared on the pack
    // and carries no ceiling, so counting it here would look like a second
    // open top.
    final ladder = bands.where((b) => b.isMassBand).toList();
    expect(ladder, hasLength(6));
    // Exactly one open-topped band at the heavy end; anything else means the
    // ladder has a hole an egg could fall through.
    expect(ladder.where((b) => b.maxMassG == null).length, 1);
    // And the declaration is present but out of the ladder.
    // "Mixed Sizes" — plural at the FSA's request (2026-08-21); the
    // original's own picker says "Mixed Size".
    expect(
      bands.where((b) => !b.isMassBand).map((b) => b.name),
      ['Mixed Sizes'],
    );
  });

  test('clients and facilities are NOT bundled', () async {
    await repo.seedRulesFromBundle();

    // Thousands of rows that change weekly would be stale before the build
    // shipped, so those stay on the sync path.
    expect(await repo.clients(), isEmpty);
    expect(await repo.facilities(), isEmpty);
  });

  test('seeding twice does not run again', () async {
    final first = await repo.seedRulesFromBundle();
    final second = await repo.seedRulesFromBundle();

    expect(first, greaterThan(0));
    expect(second, 0, reason: 'every launch after the first must be a no-op');
  });

  test('seeding does not advance the sync cursor', () async {
    // One cursor governs every collection. If the bundle set it to the build
    // time, the first delta would ask only for rows changed after the build —
    // and every client and facility created before it would be skipped and
    // never arrive. Re-fetching the rules once is the cheaper mistake.
    await repo.seedRulesFromBundle();

    expect(await db.readSyncState(EggsRepository.cursorKey), isNull);
  });

  test('a network sync still advances the cursor', () async {
    // The bundle is the exception, not a change to how syncing works.
    final synced = EggsRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'cursor': '2026-08-01T12:00:00Z',
              'data': <String, dynamic>{},
            }),
            200,
          )),
    );

    await synced.syncReference();

    expect(
      await db.readSyncState(EggsRepository.cursorKey),
      '2026-08-01T12:00:00Z',
    );
  });
}
