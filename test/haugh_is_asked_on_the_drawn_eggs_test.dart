import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// The six Haugh readings are taken on the eggs the app drew.
///
/// Six chosen at the bench are the easy six — the front of the tray, or six
/// that look sound — and six readings off those is not a sample of the
/// consignment. The app draws one egg from each tenth of the set, keeps the
/// draw on the record so a reopened inspection asks for the same eggs, and
/// shows the Haugh boxes only there (Ethan, 2026-10-23).
void main() {
  late LocalDatabase db;
  late EggsRepository eggs;

  /// A record with the draw already settled, so what the form does with it
  /// is tested rather than what the dice did.
  Future<void> record(String uuid, {String drawn = '', bool haugh = true}) async {
    final large = (await db.select(db.eggSizes).get())
        .firstWhere((s) => s.name == 'Large');
    final grade1 = (await db.select(db.eggGrades).get())
        .firstWhere((g) => g.name == 'Grade 1');
    final tray = (await db.select(db.eggTraySizes).get())
        .firstWhere((t) => t.name == '12-Pack');
    await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
          clientUuid: uuid,
          inspectedAt: DateTime(2026, 10, 23, 9),
          updatedAt: DateTime(2026, 10, 23, 9),
          visitUuid: const Value('visit-1'),
          inspectorUsername: const Value('ethan'),
          producerSupplier: Value((await eggs.suppliers()).first.name),
          declaredSizeId: Value(large.id),
          declaredGradeId: Value(grade1.id),
          traySizeId: Value(tray.id),
          haughNotRequired: Value(!haugh),
          haughSampleNumbers: Value(drawn),
        ));
  }

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    eggs = EggsRepository(database: db, baseUrl: '');
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
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

  Future<void> open(WidgetTester tester, String uuid) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: EggInspectionForm(
        repository: eggs,
        inspectorName: 'ethan',
        resumeUuid: uuid,
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
          facilityType: 'Packhouse',
          inspectionReason: 'Inspection',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the boxes are on an egg that was drawn', (tester) async {
    // The form opens on egg 1, and egg 1 is in this draw.
    await record('egg-drawn-one', drawn: '1,12,23,34,45,56');
    await open(tester, 'egg-drawn-one');
    expect(await onPage(tester, find.text('Haugh Meter Value (mm)')), isTrue);
    expect(find.text('Haugh Unit Value '), findsOneWidget);
  });

  testWidgets('and not on an egg that was not', (tester) async {
    // Same record, same answer, one egg along: egg 1 is not in this draw.
    await record('egg-drawn-two', drawn: '2,12,23,34,45,56');
    await open(tester, 'egg-drawn-two');
    expect(await onPage(tester, find.text('Egg Weight (g)')), isTrue);
    expect(find.text('Haugh Meter Value (mm)'), findsNothing);
    expect(find.text('Haugh Unit Value '), findsNothing);
  });

  testWidgets('the inspector is told which eggs to break open',
      (tester) async {
    await record('egg-drawn-told', drawn: '3,14,25,36,47,58');
    await open(tester, 'egg-drawn-told');
    // Named in tray order and in plain words, because an inspector reading
    // "3, 14, 25, 36, 47 and 58" has to be able to walk the tray by it.
    expect(
        await onPage(
            tester,
            find.textContaining(
                'Haugh reading on egg 3, 14, 25, 36, 47 and 58')),
        isTrue);
    expect(find.textContaining('still to do: 3, 14, 25, 36, 47 and 58'),
        findsOneWidget);
  });

  testWidgets('nothing is drawn, and nothing is asked, on a weighing',
      (tester) async {
    await record('egg-no-haugh', drawn: '', haugh: false);
    await open(tester, 'egg-no-haugh');
    expect(await onPage(tester, find.text('Egg Weight (g)')), isTrue);
    expect(find.text('Haugh Meter Value (mm)'), findsNothing);
    expect(find.textContaining('Haugh reading on egg'), findsNothing);
  });

  testWidgets('answering Yes draws the eggs and keeps them on the record',
      (tester) async {
    await record('egg-draw-now', drawn: '', haugh: false);
    await open(tester, 'egg-draw-now');
    const question = 'Are you going to be doing Haugh values?';
    expect(await onPage(tester, find.text(question)), isTrue);
    tester
        .widget<YesNoQuestion>(find.ancestor(
            of: find.text(question), matching: find.byType(YesNoQuestion)))
        .onChanged!(true);
    await tester.pumpAndSettle();

    final saved = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-draw-now')))
        .getSingle();
    final drawn = [
      for (final part in saved.haughSampleNumbers.split(','))
        if (part.trim().isNotEmpty) int.parse(part.trim()),
    ];
    expect(drawn, hasLength(6));
    expect(drawn.toSet(), hasLength(6), reason: 'no egg twice');
    expect(drawn.every((e) => e >= 1 && e <= 60), isTrue);
    expect(drawn, [...drawn]..sort(), reason: 'tray order');
  });

  testWidgets('a record part-captured before the draw keeps its readings',
      (tester) async {
    // Answered Yes on an older build, three readings already taken on the
    // eggs the inspector chose, and no draw on the record. Those three
    // eggs have been broken open: the draw has to include them rather
    // than name three more.
    await record('egg-part-done', drawn: '');
    for (final egg in [2, 5, 9]) {
      await db.into(db.eggSamples).insert(EggSamplesCompanion.insert(
            inspectionUuid: 'egg-part-done',
            eggNumber: egg,
            massG: const Value(58),
            albumenHeightMm: const Value(6.2),
          ));
    }
    await open(tester, 'egg-part-done');
    expect(await onPage(tester, find.textContaining('Haugh reading on egg')),
        isTrue);
    final notice = tester
        .widgetList<Text>(find.textContaining('Haugh reading on egg'))
        .first
        .data!;
    for (final egg in [2, 5, 9]) {
      expect(notice.contains('$egg'), isTrue,
          reason: 'egg $egg was already read: $notice');
    }
    // Still six in all - three kept, three drawn to make up the number.
    expect(
        RegExp(r'[0-9]+').allMatches(notice.split('—').first).length,
        EggRules.haughReadingsRequired);
  });

  testWidgets('a draw already kept is not thrown away on reopening',
      (tester) async {
    await record('egg-keep-draw', drawn: '4,15,26,37,48,59');
    await open(tester, 'egg-keep-draw');
    expect(
        await onPage(tester,
            find.textContaining('Haugh reading on egg 4, 15, 26, 37, 48 and 59')),
        isTrue);

    final saved = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals('egg-keep-draw')))
        .getSingle();
    expect(saved.haughSampleNumbers, '4,15,26,37,48,59');
  });
}
