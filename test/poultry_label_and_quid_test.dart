import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/domain/poultry_rules.dart';

/// The Label/Container and QUID screens, and directions.
void main() {
  late LocalDatabase db;
  late PoultryRepository repo;
  late PoultryCaptureRepository capture;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PoultryRepository(database: db, baseUrl: 'http://example.test');
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<void> loadAsset() async {
    final raw =
        await File('assets/reference/poultry_reference.json').readAsString();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  }

  List<PoultryChecklistItemRef> of(
    List<PoultryChecklistItemRef> items,
    PoultryChecklistKind kind,
  ) =>
      [for (final i in items) if (i.kind == kind) i];

  group('the Label/Container checklist', () {
    test('carries all five of its lists', () async {
      await loadAsset();
      final items = await repo.checklistItems();

      // Nine lettering requirements, asked once of the product label and again
      // of the outer container, then two on how the container is built.
      expect(of(items, PoultryChecklistKind.labelInner), hasLength(9));
      expect(of(items, PoultryChecklistKind.labelOuter), hasLength(9));
      expect(of(items, PoultryChecklistKind.container), hasLength(2));
      // Its own copies of the grading and portion lists.
      expect(of(items, PoultryChecklistKind.labelGrading), hasLength(13));
      expect(of(items, PoultryChecklistKind.labelPortion), hasLength(4));
    });

    test('lettering heights survive the round trip', () async {
      await loadAsset();
      final inner = of(
        await repo.checklistItems(),
        PoultryChecklistKind.labelInner,
      );

      final designation = inner.firstWhere(
        (i) => i.description.startsWith('Class or Other Designation'),
      );
      // The height is what the inspector measures against. Losing it would
      // leave the requirement stated but unmeasurable.
      expect(designation.minLetteringHeight, '4.0');

      // And a row that states no height keeps none, rather than gaining a 0
      // that would read as "at least nothing".
      final restricted =
          inner.firstWhere((i) => i.description == 'Restricted Particulars');
      expect(restricted.minLetteringHeight, isEmpty);
    });

    test('the label screen keeps its own spelling', () async {
      await loadAsset();
      final items = await repo.checklistItems();

      final onGrading = of(items, PoultryChecklistKind.grading)
          .map((i) => i.description);
      final onLabel = of(items, PoultryChecklistKind.labelGrading)
          .map((i) => i.description);

      // The original spells the same row differently on the two screens.
      // Reconciling them would make one screen disagree with the paper form
      // it is read beside.
      expect(onGrading, contains('Fleshiness: General'));
      expect(onLabel, contains('Freshiness: General'));
    });

    test('a saved checklist round-trips', () async {
      await loadAsset();
      await capture.saveLabelInspection(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'label-1',
          inspectedAt: DateTime(2026, 8, 18, 9),
          updatedAt: DateTime(2026, 8, 18, 9),
          inspectorUsername: const Value('inspector'),
          facilityName: const Value('Sunrise Poultry'),
          outerLabelsPresent: const Value(true),
          compliantItemIds: const Value('1,2,3'),
        ),
      );

      final saved = await capture.labelInspectionByUuid('label-1');
      expect(saved!.facilityName, 'Sunrise Poultry');
      expect(saved.outerLabelsPresent, isTrue);
      expect(saved.compliantItemIds, '1,2,3');
    });

    test('one inspector does not see another\'s work', () async {
      await capture.saveLabelInspection(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'mine',
          inspectedAt: DateTime(2026, 8, 18),
          updatedAt: DateTime(2026, 8, 18),
          inspectorUsername: const Value('ethan'),
        ),
      );
      await capture.saveLabelInspection(
        PoultryLabelInspectionsCompanion.insert(
          clientUuid: 'theirs',
          inspectedAt: DateTime(2026, 8, 18),
          updatedAt: DateTime(2026, 8, 18),
          inspectorUsername: const Value('someone-else'),
        ),
      );

      final mine = await capture.labelInspections('ethan');
      expect(mine.map((r) => r.clientUuid), ['mine']);
    });
  });

  group('QUID', () {
    test('set-up and continuation are one record', () async {
      await capture.saveQuidInspection(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: DateTime(2026, 8, 18, 8),
          updatedAt: DateTime(2026, 8, 18, 8),
          inspectorUsername: const Value('inspector'),
          facilityName: const Value('Coastal Abattoir'),
          injectorName: const Value('Injector 3'),
          setupComplete: const Value(true),
        ),
      );

      // The continuation writes back to the same uuid rather than creating a
      // second record, which is what keeps the two halves together.
      await capture.saveQuidInspection(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-1',
          inspectedAt: DateTime(2026, 8, 18, 8),
          updatedAt: DateTime(2026, 8, 18, 14),
          inspectorUsername: const Value('inspector'),
          facilityName: const Value('Coastal Abattoir'),
          injectorName: const Value('Injector 3'),
          setupComplete: const Value(true),
          quidPercent: const Value('7.50'),
          status: const Value('completed'),
        ),
      );

      final all = await capture.quidInspections('inspector');
      expect(all, hasLength(1));
      expect(all.single.quidPercent, '7.50');
      expect(all.single.injectorName, 'Injector 3',
          reason: 'the set-up half must survive the continuation');
    });

    test('samples are replaced wholesale, not merged', () async {
      await capture.saveQuidInspection(
        PoultryQuidInspectionsCompanion.insert(
          clientUuid: 'quid-2',
          inspectedAt: DateTime(2026, 8, 18),
          updatedAt: DateTime(2026, 8, 18),
        ),
      );

      await capture.replaceQuidSamples('quid-2', [
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: 'quid-2',
          carcassNumber: const Value('1'),
          initialMassG: const Value('1000'),
          afterMassG: const Value('1075'),
        ),
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: 'quid-2',
          carcassNumber: const Value('2'),
        ),
      ]);
      expect(await capture.quidSamples('quid-2'), hasLength(2));

      // Deleting one and saving must leave one, not three. Merging by index
      // would reassign the second carcass's masses to the first.
      await capture.replaceQuidSamples('quid-2', [
        PoultryQuidSamplesCompanion.insert(
          inspectionUuid: 'quid-2',
          carcassNumber: const Value('1'),
          initialMassG: const Value('1000'),
          afterMassG: const Value('1075'),
        ),
      ]);
      final samples = await capture.quidSamples('quid-2');
      expect(samples, hasLength(1));
      expect(samples.single.carcassNumber, '1');
    });
  });

  group('directions', () {
    test('are listed by the day they were issued', () async {
      for (final day in [16, 17, 18]) {
        await capture.saveDirection(
          PoultryDirectionsCompanion.insert(
            clientUuid: 'd$day',
            issuedAt: DateTime(2026, 8, day, 10),
            updatedAt: DateTime(2026, 8, day, 10),
            inspectorUsername: const Value('inspector'),
          ),
        );
      }

      final all = await capture.directions('inspector');
      final inRange = all
          .where((d) => PoultryCaptureRepository.withinDays(
                d.issuedAt,
                DateTime(2026, 8, 17),
                DateTime(2026, 8, 18),
              ))
          .toList();

      expect(inRange.map((d) => d.clientUuid), containsAll(['d17', 'd18']));
      expect(inRange.map((d) => d.clientUuid), isNot(contains('d16')));
    });

    test('a direction issued late on the closing day is inside the range', () {
      // 16:40 is after midnight on that day, so comparing instants rather
      // than calendar days would drop it.
      expect(
        PoultryCaptureRepository.withinDays(
          DateTime(2026, 8, 18, 16, 40),
          DateTime(2026, 8, 16),
          DateTime(2026, 8, 18),
        ),
        isTrue,
      );
    });
  });
}
