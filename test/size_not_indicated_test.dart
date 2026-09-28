import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';

/// "Not indicated" on the size picker, as the grade picker already offers.
///
/// A pack that declares no size could not be captured at all: the size is
/// required, and there was nothing to choose that meant "the pack does not
/// say". The answer is the handset's own, not a row in the office's list,
/// so it must never travel as one — sent as a foreign key the office has
/// never heard of, it takes the whole inspection down with it.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, dynamic>> uploadWith({
    int? declaredSize,
    int? declaredGrade,
  }) async {
    const uuid = 'egg-1';
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: uuid,
          inspectedAt: DateTime(2026, 9, 23, 9),
          updatedAt: DateTime(2026, 9, 23, 9),
          status: const Value('completed'),
          facilityName: const Value('Nulaid - Eikenhof'),
          declaredSizeId: Value(declaredSize),
          declaredGradeId: Value(declaredGrade),
        ));
    late Map<String, dynamic> body;
    final repository = EggsRepository(
      database: db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"client_uuid": "$uuid"}', 201);
      }),
    );
    await repository.upload(
        (await repository.inspectionByUuid(uuid))!, token: 'jwt');
    return body;
  }

  test('a real band and grade travel as themselves', () async {
    final body = await uploadWith(declaredSize: 9, declaredGrade: 4);
    expect(body['declared_size'], 9);
    expect(body['declared_grade'], 4);
  });

  test('"Not indicated" travels as no claim, not as an unknown row',
      () async {
    final body = await uploadWith(declaredSize: -1, declaredGrade: -1);
    expect(body['declared_size'], isNull,
        reason: 'id -1 is the handset\'s own answer, not an EggSize');
    expect(body['declared_grade'], isNull);
  });
}
