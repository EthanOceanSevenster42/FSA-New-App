import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/search_picker.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// One visit, products from different producers (Cinga, 2026-10-26).
///
/// The producer is named once at the door and every raw, processed meat
/// and egg inspection under the visit starts with it filled in. It was
/// also HIDDEN on those forms, so the one producer was stamped on every
/// commodity with no way to say otherwise: at Maders Slaghuis the egg
/// producer Buffelsdrift Boerdery went onto the beef mince, the
/// boerewors, the patties and the chicken patties, and the office could
/// not approve the visit (group 4152).
///
/// The visit screen has always told the inspector that "a product from a
/// different producer can still be changed on its own form". These hold
/// the forms to that: prefilled, visible, and editable per product.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 10, 6, 9);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Maders Slaghuis'),
          // The egg producer, named at the door.
          producerName: const Value('Buffelsdrift Boerdery'),
        ));
  });
  tearDown(() => db.close());

  /// The visit as a form receives it: the producer named at the door.
  const visit = VisitPrefill(
    uuid: 'visit-1',
    facilityName: 'Maders Slaghuis',
    facilityAddress: '',
    facilityPhone: '',
    contactPerson: '',
    contactEmail: '',
    representative: '',
    managerName: '',
    managerEmail: '',
    producer: 'Buffelsdrift Boerdery',
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Backing out of a form is what writes the draft (PopScope ->
  /// _previous), so the test leaves the way an inspector does.
  Future<void> leave(WidgetTester tester) async {
    final state = tester.state<NavigatorState>(find.byType(Navigator));
    state.maybePop();
    await settle(tester);
  }

  /// The producer field as the inspector sees it, whatever its type.
  Finder producerField(String label) => find.byWidgetPredicate(
      (w) => w is SearchPickerField && w.label == label);

  String producerText(WidgetTester tester, String label) =>
      (tester.widget(producerField(label)) as SearchPickerField)
          .controller
          .text;

  group('the raw form', () {
    late RawRmpRepository repo;

    setUp(() async {
      repo = RawRmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repo.writeReferenceForTest(jsonDecode(
              File('assets/reference/rawrmp_reference.json')
                  .readAsStringSync())
          as Map<String, dynamic>);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 12000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: RawRmpInspectionForm(
          repository: repo,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'Cinga Ngongo',
          visit: visit,
        ),
      ));
      await settle(tester);
    }

    testWidgets('shows the visit producer rather than hiding it',
        (tester) async {
      await open(tester);
      expect(producerField('Producer'), findsOneWidget,
          reason: 'hidden, the visit producer could not be corrected');
      expect(producerText(tester, 'Producer'), 'Buffelsdrift Boerdery',
          reason: 'prefilled, so it is never typed twice');
      expect(
          find.textContaining('Change it here if this product came from a '
              'different producer'),
          findsOneWidget);
    });

    testWidgets('a different producer typed here is kept on this record',
        (tester) async {
      await open(tester);
      await tester.ensureVisible(producerField('Producer'));
      await tester.enterText(
          find.descendant(
              of: producerField('Producer'), matching: find.byType(TextField)),
          'Maders Slaghuis');
      await settle(tester);
      expect(producerText(tester, 'Producer'), 'Maders Slaghuis');
      await leave(tester);

      final saved = (await db.select(db.rawRmpInspections).get()).single;
      expect(saved.producerName, 'Maders Slaghuis');
      // And the visit itself is untouched: the eggs still come from
      // Buffelsdrift.
      final visit = (await db.select(db.storeVisits).get()).single;
      expect(visit.producerName, 'Buffelsdrift Boerdery');
    });
  });

  group('the processed meat form', () {
    late PmpRepository repo;

    setUp(() async {
      repo = PmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repo.writeReferenceForTest(jsonDecode(
              File('assets/reference/pmp_reference.json').readAsStringSync())
          as Map<String, dynamic>);
    });

    testWidgets('shows the visit producer, prefilled and editable',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 12000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        home: PmpInspectionForm(
          repository: repo,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'Cinga Ngongo',
          visit: visit,
        ),
      ));
      await settle(tester);

      expect(producerField('Producer'), findsOneWidget);
      expect(producerText(tester, 'Producer'), 'Buffelsdrift Boerdery');

      await tester.ensureVisible(producerField('Producer'));
      await tester.enterText(
          find.descendant(
              of: producerField('Producer'), matching: find.byType(TextField)),
          'Maders Slaghuis');
      await settle(tester);
      expect(producerText(tester, 'Producer'), 'Maders Slaghuis');
      await leave(tester);

      final saved = (await db.select(db.pmpInspections).get()).single;
      expect(saved.producerName, 'Maders Slaghuis');
    });
  });
}
