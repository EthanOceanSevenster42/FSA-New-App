import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:flutter/material.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// The producer / supplier is named once, on the grouped inspection, and
/// every raw and processed meat inspection under it starts with it filled
/// in (Ethan, 2026-09-24). It reaches the office on the visit too.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 9, 24, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
          producerName: const Value('Nulaid Meats'),
          completedAt: Value(when),
        ));
  });
  tearDown(() => db.close());

  test('no form under a visit asks for the producer again', () {
    for (final path in [
      'lib/features/rawrmp/presentation/rawrmp_inspection_form.dart',
      'lib/features/pmp/presentation/pmp_inspection_form.dart',
      'lib/features/eggs/presentation/egg_inspection_form.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('if (!_producerFromVisit)'), isTrue,
          reason: '$path must hide its producer when the visit named one');
    }
  });

  test('every form under a visit starts with the producer filled in', () {
    // Pinned at the source: each form's visit prefill takes the producer
    // the way it takes the facility, so a form cannot quietly stop. The
    // forms cannot be pumped tall enough to reach the field in a test —
    // their lower sections never settle.
    for (final path in [
      'lib/features/rawrmp/presentation/rawrmp_inspection_form.dart',
      'lib/features/pmp/presentation/pmp_inspection_form.dart',
      'lib/features/eggs/presentation/egg_inspection_form.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains(', visit.producer);'), isTrue,
          reason: '$path must fill its producer from the visit');
    }
  });

  test('the visit carries the producer to the office', () async {
    late String body;
    final visits = VisitRepository(db, baseUrl: 'https://server.test',
        client: MockClient((request) async {
      body = request.body;
      return http.Response('{"id": 1}', 201);
    }));
    await visits.upload((await visits.pendingUploads()).single, token: 'jwt');
    expect(body, contains('name="producer_name"\r\n\r\nNulaid Meats'));
  });

  group('the visit asks for it only where a commodity has one', () {
    Future<void> openDoor(WidgetTester tester,
        {int poultry = 0, int raw = 0, int eggs = 0}) async {
      await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: 'visit-2',
            startedAt: when,
            facilityName: const Value('Kroon Foods'),
            plannedPoultry: Value(poultry),
            plannedRaw: Value(raw),
            plannedEggs: Value(eggs),
          ));
      await tester.pumpWidget(MaterialApp(
        home: StoreVisitPage(
          visitUuid: 'visit-2',
          visits: VisitRepository(db),
          eggs: EggsRepository(database: db, baseUrl: ''),
          eggsSync: null,
          poultry: PoultryRepository(database: db, baseUrl: ''),
          poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
          rawRmp: RawRmpRepository(database: db, baseUrl: ''),
          pmp: PmpRepository(database: db, baseUrl: ''),
          inspectorName: 'ethan',
          canRemoveRecords: false,
        ),
      ));
      await tester.pumpAndSettle();
    }

    // Drawn with the required star, so found by its label, not its text.
    Finder producerField() => find.byWidgetPredicate(
        (w) => w is RequiredLabel && w.label == 'Producer / supplier');

    testWidgets('not for a poultry-only visit', (tester) async {
      await openDoor(tester, poultry: 1);
      expect(producerField(), findsNothing);
    });

    testWidgets('asked once raw is on the plan', (tester) async {
      await openDoor(tester, raw: 1);
      await tester.scrollUntilVisible(producerField(), 250,
          scrollable: find.byType(Scrollable).first);
      expect(producerField(), findsOneWidget);
    });

    testWidgets('and required there before an inspection starts',
        (tester) async {
      await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: 'visit-3',
            inspectorUsername: const Value('ethan'),
            startedAt: when,
            facilityName: const Value('Kroon Foods'),
            facilityType: const Value('Retailer'),
            inspectionReason: const Value('Inspection'),
            facilityAddress: const Value('1 Main Road'),
            contactEmail: const Value('k@kroon.test'),
            distanceTravelledKm: const Value(12),
            plannedRaw: const Value(1),
          ));
      await tester.pumpWidget(MaterialApp(
        home: StoreVisitPage(
          visitUuid: 'visit-3',
          visits: VisitRepository(db),
          eggs: EggsRepository(database: db, baseUrl: ''),
          eggsSync: null,
          poultry: PoultryRepository(database: db, baseUrl: ''),
          poultryCapture: PoultryCaptureRepository(database: db, baseUrl: ''),
          rawRmp: RawRmpRepository(database: db, baseUrl: ''),
          pmp: PmpRepository(database: db, baseUrl: ''),
          inspectorName: 'ethan',
          canRemoveRecords: false,
        ),
      ));
      await tester.pumpAndSettle();
      const start = 'START CERTAIN RAW PROCESSED MEAT PRODUCT INSPECTION';
      await tester.scrollUntilVisible(find.text(start), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(start));
      await tester.pumpAndSettle();
      await tester.tap(find.text(start));
      await tester.pumpAndSettle();
      expect(
          find.text('Fill in the producer / supplier before starting an '
              'inspection.'),
          findsOneWidget);
    });

    testWidgets('and for eggs', (tester) async {
      await openDoor(tester, eggs: 1);
      await tester.scrollUntilVisible(producerField(), 250,
          scrollable: find.byType(Scrollable).first);
      expect(producerField(), findsOneWidget);
    });
  });
}
