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

/// An egg inspection is a weighing unless the inspector says otherwise.
///
/// The form used to demand six Haugh readings on every record and offered
/// the way out only at a retailer, so an inspector anywhere else could not
/// sign a record off without breaking eggs open — Gladys's ticket, "App
/// forces me to do egg quality in a retail...". The question is now put in
/// the inspection details, answered No by default, and the Haugh boxes
/// appear only when it is answered Yes (Ethan, 2026-10-20).
const _question = 'Are you going to be doing Haugh values?';

void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    final large = (await db.select(db.eggSizes).get())
        .firstWhere((s) => s.name == 'Large');
    final grade1 = (await db.select(db.eggGrades).get())
        .firstWhere((g) => g.name == 'Grade 1');
    final tray = (await db.select(db.eggTraySizes).get())
        .firstWhere((t) => t.name == '12-Pack');
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: 'egg-haugh',
          inspectedAt: DateTime(2026, 10, 20, 9),
          updatedAt: DateTime(2026, 10, 20, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: Value(large.id),
          declaredGradeId: Value(grade1.id),
          traySizeId: Value(tray.id),
          // What a record carries when nobody has answered the question:
          // the stored default, which is "not taken".
          haughNotRequired: const Value(true),
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
          scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        resumeUuid: 'egg-haugh',
        visit: const VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Kroon Foods',
          facilityAddress: '',
          facilityPhone: '',
          contactPerson: '',
          contactEmail: '',
          representative: '',
          managerName: '',
          managerEmail: '',
          // Not a retailer: the question used to be offered only there.
          facilityType: 'Packhouse',
          inspectionReason: 'Inspection',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the question is asked on any premises, not only a retailer',
      (tester) async {
    await open(tester);
    expect(await onPage(tester, find.text(_question)), isTrue);
    // Answered No until the inspector says otherwise.
    expect(
        tester.widget<YesNoQuestion>(find.ancestor(
            of: find.text(_question), matching: find.byType(YesNoQuestion))).value,
        isFalse);
  });

  testWidgets('answered No, only the weight is asked for', (tester) async {
    await open(tester);
    expect(await onPage(tester, find.text('Egg Weight (g)')), isTrue);
    expect(find.text('Haugh Meter Value (mm)'), findsNothing);
    expect(find.text('Haugh Unit Value '), findsNothing);
  });

  testWidgets('answered Yes, the reading is asked for', (tester) async {
    await open(tester);
    expect(await onPage(tester, find.text(_question)), isTrue);
    tester
        .widget<YesNoQuestion>(find.ancestor(
            of: find.text(_question), matching: find.byType(YesNoQuestion)))
        .onChanged!(true);
    await tester.pumpAndSettle();

    // Which eggs carry the reading is the app's choice now, so what the
    // page owes the inspector here is the list of them. The boxes
    // themselves sit on those eggs - see
    // haugh_is_asked_on_the_drawn_eggs_test.dart.
    expect(await onPage(tester, find.textContaining('Haugh reading on egg')),
        isTrue);

    // And it is kept on the record, so resuming asks the same thing again.
    final saved = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-haugh')))
        .getSingle();
    expect(saved.haughNotRequired, isFalse);
    expect(saved.haughSampleNumbers.split(',').length, 6,
        reason: 'the draw is kept with the answer');
  });
}
