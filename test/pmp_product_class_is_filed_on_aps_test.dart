import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/picker_menu_field.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/domain/pmp_product_classes.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The processed meat inspection carries the product's class as APS files
/// it (Ethan, 2026-10-04): a dropdown of the office's own twenty-three PMP
/// classes, kept on the record and sent to APS as the product's class, as
/// the raw form does.
void main() {
  late LocalDatabase db;
  final when = DateTime(2026, 10, 4, 10, 0);

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedPmp({String productClass = ''}) async {
    await db.into(db.pmpInspections).insert(PmpInspectionsCompanion.insert(
          clientUuid: 'pmp-1',
          inspectedAt: when,
          updatedAt: when,
          visitUuid: const Value('visit-1'),
          productClass: Value(productClass),
        ));
  }

  testWidgets('the form offers APS\'s PMP classes and keeps the one picked',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 14000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = PmpRepository(
      baseUrl: 'http://example.test',
      database: db,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await repo.loadBundledRulesIfEmpty();
    await seedPmp();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: PmpInspectionForm(
        repository: repo,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'Cinga',
        existingUuid: 'pmp-1',
      ),
    ));
    await tester.pumpAndSettle();

    final picker = find.byWidgetPredicate(
        (w) => w is PickerMenuField<String> && w.label == 'Product Class');
    expect(picker, findsOneWidget);
    expect(
        (tester.widget(picker) as PickerMenuField<String>)
            .options
            .map((o) => o.value),
        pmpProductClasses,
        reason: 'the office\'s list, word for word');

    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole muscle, cured, heat treated products').last);
    await tester.pumpAndSettle();

    final saved = (await db.select(db.pmpInspections).get()).single;
    expect(saved.productClass, 'Whole muscle, cured, heat treated products');
  });

  test('the class picked is what the visit sends APS as the product class',
      () async {
    await seedPmp(productClass: 'Comminuted, cured and heat treated products');
    final visits = VisitRepository(db);
    final member = (await visits.members('visit-1')).single;
    expect(await visits.productClassFor(member),
        'Comminuted, cured and heat treated products');
  });

  test('a record with no class still sends the sentence it always did',
      () async {
    await seedPmp();
    final visits = VisitRepository(db);
    final member = (await visits.members('visit-1')).single;
    expect(await visits.productClassFor(member),
        'Marking and labelling checked on site.');
  });
}
