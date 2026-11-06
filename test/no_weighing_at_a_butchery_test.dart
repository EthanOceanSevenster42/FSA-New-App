import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// Where the eggs may not be broken open, weighing is the inspector's call.
///
/// The switch was offered only where the chosen facility type literally
/// contained "retailer". A butchery follows the same rule (Neo, confirmed
/// 2026-10-21) and eggs' own list has no butchery row at all, so the answer
/// given once at the door is read as well. Gladys's ticket: "The egg
/// inspection is forcing me to do eggs quality in a Butchery".
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  String? retailer;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    // The live retailer row; "Retail outlet" is seeded inactive.
    retailer = (await eggs.facilityTypes())
        .firstWhere((t) => t.name.toLowerCase().startsWith('retail'))
        .name;
    final large = (await db.select(db.eggSizes).get())
        .firstWhere((s) => s.name == 'Large');
    final grade1 = (await db.select(db.eggGrades).get())
        .firstWhere((g) => g.name == 'Grade 1');
    final tray = (await db.select(db.eggTraySizes).get())
        .firstWhere((t) => t.name == '12-Pack');
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-premises',
          inspectedAt: DateTime(2026, 10, 21, 9),
          updatedAt: DateTime(2026, 10, 21, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: Value(large.id),
          declaredGradeId: Value(grade1.id),
          traySizeId: Value(tray.id),
        ));
  });
  tearDown(() async => db.close());

  Future<bool> onPage(WidgetTester tester, Finder target) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    try {
      await tester.scrollUntilVisible(target, 400,
          scrollable: find.byType(Scrollable).first, maxScrolls: 80);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> open(WidgetTester tester, String doorType) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        resumeUuid: 'egg-premises',
        visit: VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Kroon Foods',
          facilityAddress: '',
          facilityPhone: '',
          contactPerson: '',
          contactEmail: '',
          representative: '',
          managerName: '',
          managerEmail: '',
          facilityType: doorType,
          inspectionReason: 'Inspection',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a butchery is offered the no-weighing switch', (tester) async {
    await open(tester, 'Butchery');
    expect(
        await onPage(
            tester, find.text('No egg weighing inspection at this butchery')),
        isTrue);
  });

  testWidgets('a retailer keeps the switch it always had', (tester) async {
    await open(tester, retailer!);
    expect(
        await onPage(
            tester, find.text('No egg weighing inspection at this retailer')),
        isTrue);
  });

  testWidgets('a packhouse is still held to the weighing', (tester) async {
    await open(tester, 'Pack House');
    expect(
        await onPage(tester,
            find.textContaining('No egg weighing inspection at this')),
        isFalse);
  });

  testWidgets('answering it at a butchery takes the sampling block off',
      (tester) async {
    await open(tester, 'Butchery');
    const label = 'No egg weighing inspection at this butchery';
    expect(await onPage(tester, find.text(label)), isTrue);
    tester
        .widget<YesNoQuestion>(find.ancestor(
            of: find.text(label), matching: find.byType(YesNoQuestion)))
        .onChanged!(true);
    await tester.pumpAndSettle();
    // The confirmation names the butchery, not a retailer.
    expect(
        find.textContaining('Egg Weighing operation at this butchery'),
        findsOneWidget);
    await tester.tap(find.text('Confirm-No Inspection'));
    await tester.pumpAndSettle();

    expect(find.text('Egg Weight (g)'), findsNothing);
    final saved = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-premises')))
        .getSingle();
    expect(saved.weighingNotRequired, isTrue);
  });
}
