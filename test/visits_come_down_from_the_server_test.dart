import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/services/photo_storage.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/invoicing/data/invoice_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/inspection_management_pages.dart';

/// Inspection Management shows what the server holds, not only what this
/// tablet captured (Ethan, 2026-09-29): a seizure created on the server
/// comes down with its visit and shows as one.
Map<String, Object?> _serverVisit({String uuid = 'srv-1'}) => {
      'visit_uuid': uuid,
      'facility_name': 'Checkers Blueberry Square',
      'facility_address': 'Cnr Beyers Naude & Blueberry St, Roodepoort',
      'facility_phone': '011 251 2755',
      'contact_person': 'Manel',
      'facility_type': 'Butchery',
      'is_occurrence_report': false,
      'started_at': '2026-09-07T11:30:00Z',
      'completed_at': '2026-09-07T11:52:00Z',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'approved': false,
      'approved_at': null,
      'members': [
        {
          'kind': 'rawrmp',
          'client_uuid': 'srv-raw-1',
          'product_name': 'Venison Boerewors',
        },
      ],
      'seizures': [
        {
          'client_uuid': 'srv-seizure-1',
          'record_uuid': 'srv-raw-1',
          'record_kind': 'rawrmp',
          'issued_at': '2026-09-07T11:52:00Z',
          'client_name': 'Checkers Blueberry Square',
          'product_name': 'Venison Boerewors',
          'quantity': '5 packs (2.106 kg)',
          'receiver_name': 'Manel',
          'receiver_designation': 'Butchery Manager',
        },
      ],
    };

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  late LocalDatabase db;
  late Directory store;

  setUp(() {
    store = Directory.systemTemp.createTempSync('fsa_pull_');
    PhotoStorage.overrideForTesting(store);
    db = LocalDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    PhotoStorage.resetForTesting();
    if (store.existsSync()) store.deleteSync(recursive: true);
  });

  VisitRepository repositoryAnswering(List<Map<String, Object?>> visits,
          {void Function(http.Request)? seen}) =>
      VisitRepository(
        db,
        baseUrl: 'https://inspector-app.example',
        client: MockClient((request) async {
          seen?.call(request);
          return http.Response(jsonEncode({'visits': visits}), 200);
        }),
      );

  test('a server visit comes down with its member and its seizure', () async {
    Uri? asked;
    final repository =
        repositoryAnswering([_serverVisit()], seen: (r) => asked = r.url);
    expect(await repository.pullFromServer(token: 'jwt'), 1);
    expect(asked!.queryParameters['detail'], '1');
    expect(asked!.queryParameters['days'], '3');

    final visit = (await db.select(db.storeVisits).get()).single;
    expect(visit.facilityName, 'Checkers Blueberry Square');
    expect(visit.isUploaded, isTrue);
    expect(visit.completedAt, isNotNull);
    expect(await repository.isFromServer('srv-1'), isTrue);

    final members = await repository.members('srv-1');
    expect(members.single.kind, 'rawrmp');
    final seizure = (await db.select(db.seizures).get()).single;
    expect(seizure.recordUuid, 'srv-raw-1');
    expect(seizure.quantity, '5 packs (2.106 kg)');
    expect(seizure.isUploaded, isTrue);
  });

  test('pulling again does not duplicate anything', () async {
    final repository = repositoryAnswering([_serverVisit()]);
    await repository.pullFromServer(token: 'jwt');
    expect(await repository.pullFromServer(token: 'jwt'), 0);
    expect(await db.select(db.storeVisits).get(), hasLength(1));
    expect(await db.select(db.rawRmpInspections).get(), hasLength(1));
    expect(await db.select(db.seizures).get(), hasLength(1));
  });

  test('a visit captured on this tablet is never overwritten', () async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'srv-1',
          startedAt: DateTime(2026, 9, 7),
          facilityName: const Value('Captured here'),
          completedAt: Value(DateTime(2026, 9, 7)),
          isUploaded: const Value(true),
        ));
    final repository = repositoryAnswering([_serverVisit()]);
    expect(await repository.pullFromServer(token: 'jwt'), 0);
    expect((await db.select(db.storeVisits).get()).single.facilityName,
        'Captured here');
    expect(await db.select(db.seizures).get(), isEmpty);
  });

  test('a seizure captured here goes up with its visit', () async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: DateTime(2026, 9, 29, 8),
          facilityName: const Value('Checkers Blueberry Square'),
          completedAt: Value(DateTime(2026, 9, 29, 9)),
        ));
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: DateTime(2026, 9, 29, 8),
          updatedAt: DateTime(2026, 9, 29, 8),
          visitUuid: const Value('visit-1'),
          status: const Value('completed'),
        ));
    await db.into(db.seizures).insert(SeizuresCompanion.insert(
          clientUuid: 'seizure-1',
          recordUuid: 'pmp-1',
          recordKind: 'pmp',
          issuedAt: DateTime(2026, 9, 29, 8, 30),
          updatedAt: DateTime(2026, 9, 29, 8, 30),
          quantity: const Value('40 packs'),
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
    expect(body, contains('name="seizures"'));
    expect(body, contains('40 packs'));
  });

  testWidgets('the pulled seizure shows in Inspection Management, read-only',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = repositoryAnswering([_serverVisit()]);
    await tester.runAsync(() => repository.pullFromServer(token: 'jwt'));
    await tester.pumpWidget(MaterialApp(
      home: InspectionManagementPage(
        visits: repository,
        eggs: EggsRepository(database: db, baseUrl: ''),
        invoices: InvoiceRepository(db, repository),
        database: db,
      ),
    ));
    await settle(tester);
    expect(find.text('Checkers Blueberry Square'), findsOneWidget);
    expect(find.text('Seizure served'), findsOneWidget);
    expect(find.text('From the server'), findsOneWidget);

    await tester.tap(find.text('Checkers Blueberry Square'));
    await settle(tester);
    expect(find.text('SEIZURE SERVED'), findsOneWidget);
    expect(find.textContaining('Brought down from the server'), findsOneWidget);
    expect(find.text('EDIT VISIT DETAILS'), findsNothing);
  });
}
