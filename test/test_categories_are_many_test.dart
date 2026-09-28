import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// A raw sample can go for more than one testing category (Ethan,
/// 2026-09-25); the office is told every test the categories cover.
void main() {
  late LocalDatabase db;
  late RawRmpRepository raw;
  final when = DateTime(2026, 9, 25, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    raw = RawRmpRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await raw.writeReferenceForTest(jsonDecode(
            await File('assets/reference/rawrmp_reference.json').readAsString())
        as Map<String, dynamic>);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
          completedAt: Value(when),
        ));
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> rawLine() async {
    late String body;
    final visits = VisitRepository(db, baseUrl: 'https://server.test',
        client: MockClient((request) async {
      body = request.body;
      return http.Response('{"id": 1}', 201);
    }));
    await visits.upload((await visits.pendingUploads()).single, token: 'jwt');
    final members = RegExp(r'name="members"\r\n\r\n(.*?)\r\n--', dotAll: true)
        .firstMatch(body)!
        .group(1)!;
    return (jsonDecode(members) as List).cast<Map<String, Object?>>().single;
  }

  test('categories A and C together ask for fat, protein and DNA', () async {
    final categories = await raw.sampleCategories();
    final a = categories.firstWhere((c) => c.name.startsWith('Category A')).id;
    final c = categories.firstWhere((c) => c.name.startsWith('Category C')).id;
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-1',
          visitUuid: const Value('visit-1'),
          inspectedAt: when,
          updatedAt: when,
          status: const Value('ready'),
          isSampled: const Value(true),
          sampleCategoryId: Value(a),
          sampleCategoryIds: Value('$a,$c'),
        ));
    final line = await rawLine();
    expect(line['fat'], isTrue);
    expect(line['protein'], isTrue);
    expect(line['dna'], isTrue);
  });

  test('a record from before the list still reads its one category', () async {
    final categories = await raw.sampleCategories();
    final d = categories.firstWhere((c) => c.name.startsWith('Category D')).id;
    await db
        .into(db.rawRmpInspections)
        .insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-1',
          visitUuid: const Value('visit-1'),
          inspectedAt: when,
          updatedAt: when,
          status: const Value('ready'),
          isSampled: const Value(true),
          sampleCategoryId: Value(d),
        ));
    final line = await rawLine();
    expect(line['fat'], isTrue);
    expect(line['protein'], isFalse);
    expect(line['dna'], isFalse);
  });
}
