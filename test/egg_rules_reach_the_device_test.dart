import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// The rules an egg inspection cannot open without.
///
/// They ship inside the app so a handset that has never had signal can still
/// capture. The seed used to be gated on whether there were any egg *sizes*,
/// one table standing for twelve: a device holding sizes but no inspection
/// reasons or facility types was treated as seeded, the bundle was never
/// written, and the inspector was left with pickers reading "Not yet".
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<Map<String, dynamic>> bundle() async =>
      jsonDecode(await File('assets/reference/eggs_reference.json')
          .readAsString()) as Map<String, dynamic>;

  test('a device with nothing on it is not treated as seeded', () async {
    expect(await eggs.hasReferenceData, isFalse);
  });

  test('anything on the device keeps the bundle out', () async {
    // The bundle's ids must never land on top of the server's, so a device
    // that holds reference rows is left alone. The state that stranded the
    // inspector — some tables filled and others not — is a bug in whatever
    // emptied them, and is fixed there rather than papered over here.
    await db.into(db.eggSizes).insert(
        EggSizesCompanion.insert(
            id: const Value(1), name: 'Large', minMassG: 59));

    expect(await eggs.hasReferenceData, isTrue);
    expect(await eggs.seedRulesFromBundle(), 0);
  });

  test('the whole set counts as seeded', () async {
    await eggs.writeReferenceForTest(await bundle());
    expect(await eggs.hasReferenceData, isTrue);
  });

  test('the bundle fills the pickers an inspection opens with', () async {
    await eggs.writeReferenceForTest(await bundle());

    expect(await eggs.reasons(), isNotEmpty);
    expect(await eggs.facilityTypes(), isNotEmpty);
    expect(await eggs.sizeBands(), isNotEmpty);
  });

  test('clients and facilities are not in the bundle and need a sync', () async {
    await eggs.writeReferenceForTest(await bundle());

    // Stated rather than assumed: the directories are server-side only, so an
    // inspector on a device that has never synced sees an empty list and the
    // "add new" offer, not a bug.
    expect(await eggs.clients(), isEmpty);
    expect(await eggs.facilities(), isEmpty);
  });
}
