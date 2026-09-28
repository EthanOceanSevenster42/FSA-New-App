import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';

/// Drafts saved before outer labelling started Compliant are put right once.
///
/// The old egg form failed every outer row the moment the block was opened;
/// the old poultry label form left every outer row unticked. Both are fixed,
/// but a draft saved by the older build still holds those answers and
/// reopens looking exactly as it did — which is what "outer labelling by
/// default must be compliant" was still being said about.
void main() {
  late LocalDatabase db;
  late Set<int> eggOuter;
  late Set<int> eggInner;
  late Set<int> poultryOuter;
  late Set<int> poultryInner;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    final eggs = EggsRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await eggs.writeReferenceForTest(
        jsonDecode(await File('assets/reference/eggs_reference.json')
            .readAsString()) as Map<String, dynamic>);
    eggOuter = {for (final r in await eggs.requirements('label_outer')) r.id};
    eggInner = {for (final r in await eggs.requirements('label_pack')) r.id};

    final poultry = PoultryRepository(database: db, baseUrl: '');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(
        jsonDecode(await File('assets/reference/poultry_reference.json')
            .readAsString()) as Map<String, dynamic>);
    final items = await poultry.checklistItems();
    poultryOuter = {
      for (final i in items)
        if (i.kind == PoultryChecklistKind.labelOuter) i.id
    };
    poultryInner = {
      for (final i in items)
        if (i.kind == PoultryChecklistKind.labelInner) i.id
    };
    expect(eggOuter, isNotEmpty);
    expect(poultryOuter, isNotEmpty);
  });
  tearDown(() async => db.close());

  Future<void> eggDraft(String uuid,
      {required String status,
      required bool outerOn,
      required Set<int> failed}) =>
      db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
            clientUuid: uuid,
            inspectedAt: DateTime(2026, 9, 22, 9),
            updatedAt: DateTime(2026, 9, 22, 9),
            status: Value(status),
            outerLabellingAvailable: Value(outerOn),
            failedRequirementIds: Value(failed.join(',')),
          ));

  Future<Set<int>> eggFailed(String uuid) async {
    final row = await (db.select(db.eggInspections)
          ..where((t) => t.clientUuid.equals(uuid)))
        .getSingle();
    return row.failedRequirementIds
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  group('eggs', () {
    test('an old draft with every outer row failed comes back Compliant, '
        'keeping its real inner deviations', () async {
      final innerDeviation = eggInner.first;
      await eggDraft('old', status: 'draft', outerOn: true,
          failed: {...eggOuter, innerDeviation});

      expect(await db.repairLegacyOuterDrafts(), 1);
      expect(await eggFailed('old'), {innerDeviation});
    });

    test('a draft where the inspector failed only some outer rows is theirs',
        () async {
      final some = {eggOuter.first};
      await eggDraft('partial', status: 'draft', outerOn: true, failed: some);

      expect(await db.repairLegacyOuterDrafts(), 0);
      expect(await eggFailed('partial'), some);
    });

    test('a finished record is never touched, whatever it holds', () async {
      await eggDraft('ready', status: 'ready', outerOn: true, failed: eggOuter);
      await eggDraft('done', status: 'completed', outerOn: true, failed: eggOuter);

      expect(await db.repairLegacyOuterDrafts(), 0);
      expect(await eggFailed('ready'), eggOuter);
      expect(await eggFailed('done'), eggOuter);
    });

    test('a draft with the outer block switched off is left alone', () async {
      await eggDraft('off', status: 'draft', outerOn: false, failed: eggOuter);
      expect(await db.repairLegacyOuterDrafts(), 0);
    });

    test('running it twice changes nothing more', () async {
      await eggDraft('old', status: 'draft', outerOn: true, failed: eggOuter);
      expect(await db.repairLegacyOuterDrafts(), 1);
      expect(await db.repairLegacyOuterDrafts(), 0);
      expect(await eggFailed('old'), isEmpty);
    });
  });

  group('poultry label', () {
    Future<void> labelDraft(String uuid,
        {required String status,
        required bool outerOn,
        required Set<int> compliant}) =>
        db
            .into(db.poultryLabelInspections)
            .insert(PoultryLabelInspectionsCompanion.insert(
              clientUuid: uuid,
              inspectedAt: DateTime(2026, 9, 22, 9),
              updatedAt: DateTime(2026, 9, 22, 9),
              status: Value(status),
              outerLabelsPresent: Value(outerOn),
              compliantItemIds: Value(compliant.join(',')),
            ));

    Future<Set<int>> compliantOf(String uuid) async {
      final row = await (db.select(db.poultryLabelInspections)
            ..where((t) => t.clientUuid.equals(uuid)))
          .getSingle();
      return row.compliantItemIds
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toSet();
    }

    test('an old draft with the block on and no outer row compliant gets '
        'them all back', () async {
      await labelDraft('old', status: 'draft', outerOn: true,
          compliant: poultryInner);

      expect(await db.repairLegacyOuterDrafts(), 1);
      expect(await compliantOf('old'), {...poultryInner, ...poultryOuter});
    });

    test('a draft where the inspector has answered any outer row is theirs',
        () async {
      final answered = {...poultryInner, poultryOuter.first};
      await labelDraft('partial', status: 'draft', outerOn: true,
          compliant: answered);

      expect(await db.repairLegacyOuterDrafts(), 0);
      expect(await compliantOf('partial'), answered);
    });

    test('a finished record is never touched', () async {
      await labelDraft('done', status: 'completed', outerOn: true,
          compliant: poultryInner);
      expect(await db.repairLegacyOuterDrafts(), 0);
      expect(await compliantOf('done'), poultryInner);
    });
  });
}
