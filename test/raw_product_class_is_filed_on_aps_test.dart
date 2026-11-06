import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/picker_menu_field.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_product_classes.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The raw inspection carries the product's class as APS files it (Ethan,
/// 2026-10-04): a dropdown of the office's own twenty Raw classes, kept on
/// the record and sent to APS as the product's class. Before, APS was sent
/// a stock sentence, which is not one of its classes and so showed as no
/// class chosen on every raw record the handset filed.
void main() {
  late LocalDatabase db;
  late Map<String, dynamic> bundle;
  final when = DateTime(2026, 10, 4, 10, 0);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    bundle = jsonDecode(await File('assets/reference/rawrmp_reference.json')
        .readAsString()) as Map<String, dynamic>;
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> seedRaw({String productClass = ''}) async {
    await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'raw-1',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: const Value('visit-1'),
          recordKind: Value(RawRecordKind.both.stored),
          productClass: Value(productClass),
        ));
  }

  testWidgets('the form offers APS\'s Raw classes and keeps the one picked',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository =
        RawRmpRepository(database: db, baseUrl: 'http://example.test');
    final capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await repository.writeReferenceForTest(bundle);
    await seedRaw();
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: repository,
        captureRepository: capture,
        inspectorName: 'ethan',
        existingUuid: 'raw-1',
      ),
    ));
    await settle(tester);

    final picker = find.byWidgetPredicate(
        (w) => w is PickerMenuField<String> && w.label == 'Product Class');
    expect(picker, findsOneWidget);
    expect(
        (tester.widget(picker) as PickerMenuField<String>)
            .options
            .map((o) => o.value),
        rawProductClasses,
        reason: 'the office\'s list, word for word');

    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await settle(tester);
    await tester.tap(find.text('Raw Boerewors').last);
    await settle(tester);

    final saved = (await db.select(db.rawRmpInspections).get()).single;
    expect(saved.productClass, 'Raw Boerewors');
  });

  test('the class picked is what the visit sends APS as the product class',
      () async {
    await seedRaw(productClass: 'Raw species sausage / wors');
    final visits = VisitRepository(db);
    final member = (await visits.members('visit-1')).single;
    expect(await visits.productClassFor(member), 'Raw species sausage / wors');
  });

  test('a record with no class still sends the sentence it always did',
      () async {
    await seedRaw();
    final visits = VisitRepository(db);
    final member = (await visits.members('visit-1')).single;
    expect(await visits.productClassFor(member),
        'Marking and labelling checked on site.');
  });
}
