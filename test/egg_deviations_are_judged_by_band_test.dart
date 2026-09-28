import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The office is told about a weighing deviation the way the handset judges
/// it: a count across the sample, against the band the Agency allows for the
/// declared size and grade.
///
/// Every ticked deviation used to arrive as a finding, so a consignment the
/// handset had passed — two cracked shells where four are allowed — reached
/// the office marked non-compliant, while a deviation the handset had
/// flagged red carried no count to say by how much.
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;
  late List<DeviationTolerance> tolerances;
  const visitUuid = 'visit-1';
  // Large, Grade 1 — a pairing the Agency's table has rows for.
  late int sizeId;
  late int gradeId;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    tolerances = await eggs.deviationTolerances();
    sizeId = (await eggs.sizeBands()).firstWhere((b) => b.name == 'Large').id;
    gradeId =
        (await eggs.gradeRefs()).firstWhere((g) => g.name == 'Grade 1').id;
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          startedAt: DateTime(2026, 9, 23, 8),
          facilityName: const Value('Nulaid - Eikenhof'),
          completedAt: Value(DateTime(2026, 9, 23, 11)),
        ));
  });
  tearDown(() async => db.close());

  /// A deviation whose band at this size and grade allows [atLeast] eggs.
  int deviationAllowing(int atLeast) => tolerances
      .firstWhere((t) =>
          t.sizeId == sizeId &&
          t.gradeId == gradeId &&
          t.minimum == 0 &&
          t.maximum >= atLeast &&
          t.maximum < 60)
      .deviationId;

  Future<void> seedEggs(Map<int, int> eggsPerDeviation) async {
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-1',
          visitUuid: const Value(visitUuid),
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          status: const Value('ready'),
          declaredSizeId: Value(sizeId),
          declaredGradeId: Value(gradeId),
          sampleSize: const Value(60),
        ));
    var n = 1;
    for (final entry in eggsPerDeviation.entries) {
      for (var i = 0; i < entry.value; i++) {
        await db.into(db.eggSamples).insert(EggSamplesCompanion.insert(
              inspectionUuid: 'egg-1',
              eggNumber: n++,
              massG: const Value(58),
              deviationIds: Value('${entry.key}'),
            ));
      }
    }
    // Clean eggs make up the rest of the sample.
    while (n <= 60) {
      await db.into(db.eggSamples).insert(EggSamplesCompanion.insert(
            inspectionUuid: 'egg-1',
            eggNumber: n++,
            massG: const Value(58),
          ));
    }
  }

  Future<Map<String, Object?>> eggLine() async {
    late Map<String, String> fields;
    final visits = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        fields = _fieldsOf(request);
        return http.Response('{"id": 1}', 201);
      }),
    );
    await visits.upload((await visits.pendingUploads()).single, token: 'jwt');
    final members = (jsonDecode(fields['members']!) as List<Object?>)
        .cast<Map<String, Object?>>();
    return members.firstWhere((m) => m['kind'] == 'egg');
  }

  test('a deviation inside its band is not a finding, and the record passes',
      () async {
    final id = deviationAllowing(4);
    await seedEggs({id: 2});

    final line = await eggLine();
    expect(line['is_compliant'], isTrue,
        reason: 'two eggs where the band allows four is within tolerance');
    expect(line['findings'], isEmpty);
  });

  test('a deviation beyond its band is a finding, with the count on it',
      () async {
    final id = deviationAllowing(4);
    final band = EggRules.toleranceFor(
        deviationId: id, sizeId: sizeId, gradeId: gradeId,
        tolerances: tolerances)!;
    await seedEggs({id: band.maximum + 1});

    final line = await eggLine();
    expect(line['is_compliant'], isFalse);
    final description =
        (await eggs.deviationRefs()).firstWhere((d) => d.id == id).description;
    expect(line['findings'], contains(description));
    expect(line['findings'], contains('${band.maximum + 1} of 60 eggs'));
  });

  test('the handset and the office agree', () async {
    // The same rule decides both, so the two cannot drift apart.
    final id = deviationAllowing(4);
    final band = EggRules.toleranceFor(
        deviationId: id, sizeId: sizeId, gradeId: gradeId,
        tolerances: tolerances)!;
    expect(
      EggRules.isDeviationPermissible(
          deviationId: id, count: band.maximum, sizeId: sizeId,
          gradeId: gradeId, tolerances: tolerances),
      isTrue,
    );
    expect(
      EggRules.isDeviationPermissible(
          deviationId: id, count: band.maximum + 1, sizeId: sizeId,
          gradeId: gradeId, tolerances: tolerances),
      isFalse,
    );
  });
}

Map<String, String> _fieldsOf(http.Request request) {
  final body = request.body;
  final fields = <String, String>{};
  final pattern = RegExp(
    r'name="([^"]+)"\r\n\r\n(.*?)\r\n--',
    dotAll: true,
  );
  for (final match in pattern.allMatches(body)) {
    fields[match.group(1)!] = match.group(2)!;
  }
  return fields;
}
