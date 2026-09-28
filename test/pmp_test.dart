import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/domain/pmp_rules.dart';

/// The PMP module: its bundled rules, its gated tick-list, and the courier
/// leg that makes it different from the other commodities.
void main() {
  late LocalDatabase db;
  late PmpRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PmpRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<void> loadAsset() async {
    final raw =
        File('assets/reference/pmp_reference.json').readAsStringSync();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  }

  group('the bundled rules', () {
    test('carry every collection the form needs', () async {
      await loadAsset();

      expect(await repo.reasons(), hasLength(2));
      expect(await repo.locations(), hasLength(4));
      expect(await repo.storageTypes(), hasLength(4));
      expect(await repo.subClassProducts(), hasLength(3));
      expect(await repo.ingredients(), hasLength(7));
      expect(await repo.laboratories(), hasLength(4));
      expect(await repo.restrictedParticulars(), hasLength(18));
      expect(await repo.directionRemarks(), hasLength(4));
    });

    test('the tick-list arrives sectioned as the screen shows it', () async {
      await loadAsset();
      final items = await repo.checklistItems();

      List<PmpChecklistItemRef> of(PmpSection s) =>
          [for (final i in items) if (i.section == s) i];

      // 7 marking, 7 scale, 6 container, 1 fridge, 1 notice — the XAML's own
      // layout, with the commented-out rows (8, 12, 23) absent.
      expect(of(PmpSection.marking), hasLength(7));
      expect(of(PmpSection.scale), hasLength(7));
      expect(of(PmpSection.container), hasLength(6));
      expect(of(PmpSection.fridge), hasLength(1));
      expect(of(PmpSection.notice), hasLength(1));
    });

    test('lettering heights and regulations survive the round trip', () async {
      await loadAsset();
      final items = await repo.checklistItems();

      final productName = items.firstWhere(
        (i) =>
            i.section == PmpSection.marking && i.description == 'Product Name',
      );
      expect(productName.minLetteringHeight, '3');
      expect(productName.regulationReference, contains('Reg. 8(1)(a)'));
    });
  });

  group('the gated tick-list', () {
    PmpChecklistItemRef item(int id, PmpSection section) =>
        PmpChecklistItemRef(
          id: id,
          section: section,
          originalId: id,
          description: 'Item $id',
          regulationReference: '',
        );

    final items = [
      item(1, PmpSection.marking),
      item(2, PmpSection.marking),
      item(3, PmpSection.fridge),
    ];

    test('an absent section contributes nothing', () {
      // No fridge on the premises means the fridge rule does not arise —
      // which is a different thing from failing it.
      final findings = PmpRules.findings(
        items: items,
        present: {PmpSection.marking},
        compliantItemIds: {1},
      );

      expect(findings.map((f) => f.id), [2]);
    });

    test('a present section with no ticks is all findings', () {
      final findings = PmpRules.findings(
        items: items,
        present: {PmpSection.marking, PmpSection.fridge},
        compliantItemIds: const {},
      );

      expect(findings, hasLength(3));
    });
  });

  group('the courier leg', () {
    Future<void> seed({
      required String uuid,
      bool sampled = true,
      bool couriered = true,
      String waybill = '',
    }) =>
        repo.saveInspection(
          PmpInspectionsCompanion.insert(
            clientUuid: uuid,
            inspectedAt: DateTime(2026, 8, 18, 9),
            updatedAt: DateTime(2026, 8, 18, 9),
            inspectorUsername: const Value('Ethan'),
            status: const Value('completed'),
            isSampled: Value(sampled),
            isCouriered: Value(couriered),
            waybill: Value(waybill),
            isUploaded: const Value(true),
          ),
        );

    test('pending courier lists exactly the samples missing a waybill',
        () async {
      await seed(uuid: 'needs-waybill');
      await seed(uuid: 'has-waybill', waybill: 'WB-1');
      await seed(uuid: 'hand-delivered', couriered: false);
      await seed(uuid: 'not-sampled', sampled: false);

      final pending = await repo.pendingCourier('Ethan');

      expect(pending.map((i) => i.clientUuid), ['needs-waybill']);
    });

    test('capturing the waybill queues the record for upload again', () async {
      await seed(uuid: 'w-1');

      await repo.setWaybill('w-1', 'WB-778899');

      final saved = await repo.inspectionByUuid('w-1');
      expect(saved!.waybill, 'WB-778899');
      // The record changed after it was sent, so the register's copy is now
      // behind — it must go again.
      expect(saved.isUploaded, isFalse);
      expect(await repo.pendingCourier('Ethan'), isEmpty);
    });
  });
}
