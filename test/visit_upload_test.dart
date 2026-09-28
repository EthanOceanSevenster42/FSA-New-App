import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/seizures/data/seizure_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/widgets.dart' as pw;

/// What the office's record is made of.
///
/// The group upload is multipart, because the Request for Invoice travels
/// with it, and multipart has no nested lists — so the members go up as one
/// JSON string. That shape is a contract with the server: when it was sent
/// any other way the server read no members at all and refused the visit
/// with a 400 the inspector never saw. These tests hold the shape.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedVisit() async {
    await db.into(db.storeVisits).insert(
          StoreVisitsCompanion.insert(
            uuid: 'visit-1',
            startedAt: DateTime.utc(2026, 8, 23, 8),
            facilityName: const Value('Kroon Foods'),
            completedAt: Value(DateTime.utc(2026, 8, 23, 11)),
          ),
        );
  }

  test('the group carries its members, its distance and its hours', () async {
    await seedVisit();
    late http.BaseRequest sent;
    late Map<String, String> fields;

    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        sent = request;
        fields = _fieldsOf(request);
        return http.Response('{"id": 1}', 201);
      }),
    );

    final sentOk = await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
      kilometres: 42.5,
      hours: 3,
    );

    expect(sentOk, isTrue);
    expect(sent.headers['Authorization'], 'Bearer jwt');
    expect(fields['facility_name'], 'Kroon Foods');
    expect(double.parse(fields['kilometres']!), 42.5);
    expect(double.parse(fields['hours']!), 3);
    // The list is one JSON string, not form-style members[0] keys.
    expect(jsonDecode(fields['members']!), isA<List<Object?>>());
  });

  test('the occurrence-report answer travels with the group', () async {
    await db.into(db.storeVisits).insert(
          StoreVisitsCompanion.insert(
            uuid: 'visit-occ',
            startedAt: DateTime.utc(2026, 8, 27, 9, 55),
            facilityName: const Value('SHOPRITE - Bridge City Mall'),
            completedAt: Value(DateTime.utc(2026, 8, 27, 11)),
            isOccurrenceReport: const Value(true),
          ),
        );
    late Map<String, String> fields;
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        fields = _fieldsOf(request);
        return http.Response('{"id": 2}', 201);
      }),
    );
    await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
      kilometres: 0,
      hours: 1,
    );
    expect(fields['is_occurrence_report'], 'true');
  });

  test('a visit that was not flagged says so, and the answer is kept locally',
      () async {
    await seedVisit();
    expect((await db.select(db.storeVisits).get()).single.isOccurrenceReport,
        isFalse, reason: 'No is the default');
    late Map<String, String> fields;
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        fields = _fieldsOf(request);
        return http.Response('{"id": 3}', 201);
      }),
    );
    // The door question, answered Yes later on the visit page.
    await repository.updateDetails(
        'visit-1', const StoreVisitsCompanion(isOccurrenceReport: Value(true)));
    expect((await repository.byUuid('visit-1'))!.isOccurrenceReport, isTrue);
    await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
      kilometres: 0,
      hours: 1,
    );
    expect(fields['is_occurrence_report'], 'true');
  });

  test('the Request for Invoice goes up with it', () async {
    await seedVisit();
    final pdf = File('${Directory.systemTemp.createTempSync().path}/rfi.pdf')
      ..writeAsBytesSync([37, 80, 68, 70]);
    var body = '';

    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        body = utf8.decode(request.bodyBytes, allowMalformed: true);
        return http.Response('{"id": 1}', 201);
      }),
    );

    await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
      invoicePdf: pdf,
    );

    expect(body, contains('name="rfi"'));
    expect(body, contains('request-for-invoice.pdf'));
  });

  test('a seizure served on a member goes up with the group', () async {
    await seedVisit();
    await db
        .into(db.poultryQuidInspections)
        .insert(PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: DateTime.utc(2026, 8, 23, 9),
          updatedAt: DateTime.utc(2026, 8, 23, 9),
          visitUuid: const Value('visit-1'),
          status: const Value('completed'),
          facilityName: const Value('Kroon Foods'),
          isWholeCarcass: const Value(true),
        ));
    await SeizureRepository(database: db).record(SeizuresCompanion.insert(
      clientUuid: 'seizure-1',
      recordUuid: 'quid-1',
      recordKind: 'quid',
      issuedAt: DateTime.utc(2026, 8, 23, 10),
      updatedAt: DateTime.utc(2026, 8, 23, 10),
      visitUuid: const Value('visit-1'),
      clientName: const Value('Kroon Foods'),
      productName: const Value('Chicken portions'),
      quantity: const Value('40 packs'),
    ));
    // The sheet is drawn on the way up, so the document layer needs its
    // fonts and logo handed to it here.
    FsaForm.useAssets(FsaFormAssets(
      regular: pw.Font.ttf(
          (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
              .buffer
              .asByteData()),
      bold: pw.Font.ttf(
          (await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
              .buffer
              .asByteData()),
      logo: pw.MemoryImage(
          await File('assets/images/FSA_Logo.png').readAsBytes()),
    ));
    var body = '';
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((request) async {
        body = utf8.decode(request.bodyBytes, allowMalformed: true);
        return http.Response('{"id": 1}', 201);
      }),
    );

    await repository.upload((await repository.pendingUploads()).single,
        token: 'jwt');

    expect(body, contains('"document_type":"seizure"'));
    expect(body, contains('FSA-Kroon-Foods-Seizure-quid-1.pdf'));
  });

  group('a QUID member reports what it found', () {
    /// Seeds a determination whose one injector ran [percentages], with the
    /// injector set to 8 %.
    Future<void> seedQuid(List<String> percentages) async {
      await seedVisit();
      await db
          .into(db.poultryQuidInspections)
          .insert(PoultryQuidInspectionsCompanion.insert(
            clientUuid: 'quid-1',
            inspectedAt: DateTime.utc(2026, 8, 23, 9),
            updatedAt: DateTime.utc(2026, 8, 23, 9),
            visitUuid: const Value('visit-1'),
            status: const Value('completed'),
            facilityName: const Value('Kroon Foods'),
            isWholeCarcass: const Value(true),
          ));
      await db
          .into(db.poultryQuidInjectors)
          .insert(PoultryQuidInjectorsCompanion.insert(
            inspectionUuid: 'quid-1',
            position: 1,
            name: const Value('Brine 1'),
            quidPercent: const Value('8.0'),
          ));
      for (final p in percentages) {
        await db
            .into(db.poultryQuidSamples)
            .insert(PoultryQuidSamplesCompanion.insert(
              inspectionUuid: 'quid-1',
              quidPercent: Value(p),
              assignedInjector: const Value('1'),
            ));
      }
    }

    Future<Map<String, Object?>> lineFor() async {
      late Map<String, String> fields;
      final repository = VisitRepository(
        db,
        baseUrl: 'https://inspector-app.example',
        client: MockClient((request) async {
          fields = _fieldsOf(request);
          return http.Response('{"id": 1}', 201);
        }),
      );
      await repository.upload((await repository.pendingUploads()).single,
          token: 'jwt');
      final members =
          (jsonDecode(fields['members']!) as List<Object?>).cast<Map<String, Object?>>();
      return members
          .firstWhere((m) => m['kind'] == 'quid')
          .cast<String, Object?>();
    }

    test('an injector over its setting fails the member', () async {
      // Five carcasses averaging 12.1 % against a limit of 8 + 1.
      await seedQuid(const ['12.1', '12.1', '12.1', '12.1', '12.1']);
      final line = await lineFor();

      // The member used to fall through and send no compliance line at all.
      expect(line['is_compliant'], isFalse);
      expect(line['findings'], contains('Brine 1'));
      expect(line['findings'], contains('12.100'));
      expect(line['findings'], contains('9.000'));
    });

    test('an injector inside its setting passes', () async {
      await seedQuid(const ['7.5', '7.5', '7.5', '7.5', '7.5']);
      final line = await lineFor();
      expect(line['is_compliant'], isTrue);
      expect(line['findings'], '');
    });

    test('a rejection the weighing ended in is reported as raised, and the '
        'product line says what was weighed', () async {
      await seedQuid(const ['12.1', '12.1', '12.1', '12.1', '12.1']);
      await (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(const PoultryQuidInspectionsCompanion(
              isWaterChilled: Value(true),
              quidDeterminationComplete: Value(true),
              directionRequired: Value(true),
              directionReason: Value('Brine 1 over.')));
      final line = await lineFor();
      // Used to be sent as not raised, whatever the determination ended in.
      expect(line['direction_raised'], isTrue);
      expect(line['product_name'], 'Poultry QUID');
      // Used to be the label checklist's wording.
      expect(
          line['product_class'],
          'QUID verified on water-chilled whole carcasses over 1 injector; '
          'rejection issued.');
    });

    test('a determination within its limit says so on its product line',
        () async {
      await seedQuid(const ['7.5', '7.5', '7.5', '7.5', '7.5']);
      await (db.update(db.poultryQuidInspections)
            ..where((t) => t.clientUuid.equals('quid-1')))
          .write(const PoultryQuidInspectionsCompanion(
              quidDeterminationComplete: Value(true)));
      final line = await lineFor();
      expect(line['direction_raised'], isFalse);
      expect(line['product_class'], contains('within the permitted limit'));
    });

    test('too few carcasses is not a pass and not a fail', () async {
      // Four, and well over the limit. The original will not judge a plant
      // on fewer than five, so neither does the office's record.
      await seedQuid(const ['20', '20', '20', '20']);
      final line = await lineFor();
      // Nothing was judged, so no compliance line is sent at all — the same
      // way an untouched checklist on any other commodity is left unstated
      // rather than filed as a pass.
      expect(line.containsKey('is_compliant'), isFalse);
      expect(line.containsKey('findings'), isFalse);
    });
  });

  test('a visit the server refused stays pending', () async {
    await seedVisit();
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((_) async => http.Response('{"members": []}', 400)),
    );

    final visit = (await repository.pendingUploads()).single;
    expect(await repository.upload(visit, token: 'jwt'), isFalse);
    // Still waiting, so the next pass tries again rather than losing it.
    expect(await repository.pendingUploads(), hasLength(1));
  });

  test('an accepted visit stops being pending', () async {
    await seedVisit();
    final repository = VisitRepository(
      db,
      baseUrl: 'https://inspector-app.example',
      client: MockClient((_) async => http.Response('{"id": 1}', 201)),
    );

    await repository.upload(
      (await repository.pendingUploads()).single,
      token: 'jwt',
    );
    expect(await repository.pendingUploads(), isEmpty);
  });
}

/// Reads the plain fields back out of a multipart body.
Map<String, String> _fieldsOf(http.Request request) {
  final body = utf8.decode(request.bodyBytes, allowMalformed: true);
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
