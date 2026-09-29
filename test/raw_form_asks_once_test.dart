import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// What the raw form asks for inside a grouped inspection.
///
/// Anything settled at the door belongs to the visit, not to a product: the
/// facility and its contacts, and the kilometres for the journey. Asking
/// again lets one record disagree with the visit it belongs to, and gives
/// the inspector the same question two or three times a store.
void main() {
  late LocalDatabase db;
  late RawRmpRepository repo;
  const visitUuid = 'visit-1';
  final when = DateTime(2026, 9, 1, 8);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    final raw =
        await File('assets/reference/rawrmp_reference.json').readAsString();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: visitUuid,
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
          facilityAddress: const Value('12 Bridge Road'),
          contactPerson: const Value('T. Dlamini'),
          distanceTravelledKm: const Value(42.5),
        ));
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester, {bool inVisit = true}) async {
    final visit = (await db.select(db.storeVisits).get()).single;
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: repo,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://x.test'),
        inspectorName: 'ethan',
        visit: inVisit ? VisitRepository(db).prefillOf(visit) : null,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('it does not ask for the facility again', (tester) async {
    await open(tester);
    expect(find.text('Facility Address'), findsNothing);
    expect(find.text('Trading Name'), findsNothing);
    expect(find.text('Representative Name / Person in Charge'), findsNothing);
  });

  testWidgets('it does not ask for the distance again', (tester) async {
    await open(tester);
    await scrollTo(tester, find.text('NEXT'));

    // One journey to one facility, asked at the door.
    expect(find.text('Travel'), findsNothing);
    expect(find.text('Distance Travelled (km)'), findsNothing);
  });

  testWidgets('a standalone raw inspection still asks for both',
      (tester) async {
    await open(tester, inVisit: false);
    // Nothing was settled at a door, so the form has to ask. Below the
    // product photographs, which open the page.
    await scrollTo(tester, find.text('Trading Name'));
    expect(find.text('Trading Name'), findsOneWidget);
    await scrollTo(tester, find.text('Facility Address'));
    expect(find.text('Facility Address'), findsOneWidget);

    await scrollTo(tester, find.text('Distance Travelled (km)'));
    expect(find.text('Distance Travelled (km)'), findsOneWidget);
  });
}
