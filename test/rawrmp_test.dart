import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/rawrmp_rules.dart';

/// The RawRMP module: its bundled rules, its gated tick-list, and the courier
/// leg it shares with PMP.
void main() {
  late LocalDatabase db;
  late RawRmpRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = RawRmpRepository(database: db, baseUrl: 'http://example.test');
  });
  tearDown(() async => db.close());

  Future<void> loadAsset() async {
    final raw =
        File('assets/reference/rawrmp_reference.json').readAsStringSync();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  }

  group('the bundled rules', () {
    test('carry every collection the form needs', () async {
      await loadAsset();

      expect(await repo.reasons(), hasLength(2));
      expect(await repo.locations(), hasLength(5));
      // The original's five "products" were placeholders and photo subjects
      // ("Display Fridge", "Notice Board"); they travel switched off, so the
      // picker offers nothing until a sync brings the FSA's directory down.
      expect(await repo.products(), isEmpty);
      // "New Producer" was the original's placeholder, not a producer; it
      // travels switched off for the same reason the products do.
      expect(await repo.producers(), isEmpty);
      // The original's five, plus the Food Safety Laboratory the FSA asked
      // to have added.
      expect(await repo.laboratories(), hasLength(6));
      // Category A/B/C from the original, plus Category D added at the
      // FSA's request (2026-08-20).
      expect(await repo.sampleCategories(), hasLength(4));
      expect(await repo.restrictedParticulars(), hasLength(1));
      expect(await repo.directionRemarks(), hasLength(4));
    });

    test('the storage picker hides what the original seeds inactive',
        () async {
      await loadAsset();
      final names = [for (final s in await repo.storageTypes()) s.name];

      // Four rows travel, but "Shelf" is IsActive=false in the original and
      // its picker filters on the flag — three reach the screen.
      expect(names, ['Frozen', 'Chilled', 'Not Applicable']);
    });

    test('the tick-list arrives sectioned as the screen shows it', () async {
      await loadAsset();
      final items = await repo.checklistItems();

      List<RawRmpChecklistItemRef> of(RawRmpSection s) =>
          [for (final i in items) if (i.section == s) i];

      // 7 marking, 7 scale, 6 container, 1 fridge, 1 notice — the XAML's own
      // layout, with the commented-out rows (8, 16, 23) absent.
      expect(of(RawRmpSection.marking), hasLength(7));
      expect(of(RawRmpSection.scale), hasLength(7));
      expect(of(RawRmpSection.container), hasLength(6));
      expect(of(RawRmpSection.fridge), hasLength(1));
      expect(of(RawRmpSection.notice), hasLength(1));
    });

    test('the scale section keeps the original quirks', () async {
      await loadAsset();
      final items = await repo.checklistItems();
      final scale = [
        for (final i in items)
          if (i.section == RawRmpSection.scale) i,
      ];

      // The original writes "Product Appropriate Name" on the scale label —
      // reversed from the marking section's "Appropriate Product Name" — and
      // its first row's regulation reads "[Reg. 7(2)] & (a)", bracket quirk
      // and all. Both are the screen's own text and both are kept.
      expect(
        [for (final i in scale) i.description],
        contains('Product Appropriate Name'),
      );
      expect(
        [for (final i in scale) i.regulationReference],
        contains('[Reg. 7(2)] & (a)'),
      );
    });
  });

  group('the product photographs', () {
    test('two are required before a record can be finished', () {
      expect(RawRmpRules.requiredProductPhotos, 2);
      expect(RawRmpRules.photographsOutstanding(0), isTrue);
      expect(RawRmpRules.photographsOutstanding(1), isTrue);
      expect(RawRmpRules.photographsOutstanding(2), isFalse);
    });

    test('a third is welcome, not owed', () {
      expect(RawRmpRules.photographsOutstanding(3), isFalse);
    });
  });

  group('the gated tick-list', () {
    RawRmpChecklistItemRef item(int id, RawRmpSection section) =>
        RawRmpChecklistItemRef(
          id: id,
          section: section,
          originalId: id,
          description: 'Item $id',
          regulationReference: '',
        );

    final items = [
      item(1, RawRmpSection.marking),
      item(2, RawRmpSection.marking),
      item(3, RawRmpSection.fridge),
    ];

    test('an absent section contributes nothing', () {
      final findings = RawRmpRules.findings(
        items: items,
        present: {RawRmpSection.marking},
        compliantItemIds: {1},
      );

      expect(findings.map((f) => f.id), [2]);
    });

    test('a present section with no ticks is all findings', () {
      final findings = RawRmpRules.findings(
        items: items,
        present: {RawRmpSection.marking, RawRmpSection.fridge},
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
          RawRmpInspectionsCompanion.insert(
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
      expect(saved.isUploaded, isFalse);
      expect(await repo.pendingCourier('Ethan'), isEmpty);
    });
  });

  group('directions raised from inspections', () {
    test('are found again by their source inspection', () async {
      await repo.saveDirection(
        RawRmpDirectionsCompanion.insert(
          clientUuid: 'd-1',
          issuedAt: DateTime(2026, 8, 19),
          updatedAt: DateTime(2026, 8, 19),
          inspectorUsername: const Value('Ethan'),
          status: const Value('completed'),
          sourceInspectionUuid: const Value('i-1'),
          producerName: const Value('Karoo Meats CC'),
          batchNumber: const Value('B42'),
          nonConformanceIds: const Value('1,3'),
        ),
      );

      final found = await repo.directionForInspection('i-1');
      expect(found, isNotNull);
      expect(found!.clientUuid, 'd-1');
      expect(found.producerName, 'Karoo Meats CC');
      expect(found.batchNumber, 'B42');
      expect(await repo.directionForInspection('i-2'), isNull);
    });

    test('resolve their numbered deviations against the flat list', () async {
      await loadAsset();
      final info = await repo.labelNonConformances();
      expect(info, isNotEmpty);
      // Position 1 must resolve — the summary looks descriptions up by id.
      expect(info.any((r) => r.id == 1), isTrue);
    });
  });

  group('seizure rules (FSA request, 2026-08-20)', () {
    const marking = RawRmpChecklistItemRef(
        id: 1,
        section: RawRmpSection.marking,
        originalId: 2,
        description: 'Appropriate Product Name',
        regulationReference: '');
    const scaleName = RawRmpChecklistItemRef(
        id: 2,
        section: RawRmpSection.scale,
        originalId: 10,
        description: 'Product Appropriate Name',
        regulationReference: '');
    const additions = RawRmpChecklistItemRef(
        id: 3,
        section: RawRmpSection.marking,
        originalId: 3,
        description: 'Additions to Appropriate Product Name',
        regulationReference: '');
    const batch = RawRmpChecklistItemRef(
        id: 4,
        section: RawRmpSection.scale,
        originalId: 13,
        description: 'Date Marking/Batch Code/Batch Number',
        regulationReference: '');
    const other = RawRmpChecklistItemRef(
        id: 5,
        section: RawRmpSection.marking,
        originalId: 4,
        description: 'Name and Address',
        regulationReference: '');
    const items = [marking, scaleName, additions, batch, other];
    const present = {RawRmpSection.marking, RawRmpSection.scale};

    bool seize(Set<int> compliant, {required bool absent}) =>
        RawRmpRules.seizureRequired(
          items: items,
          present: present,
          compliantItemIds: compliant,
          productNameAbsent: absent,
        );

    test('both product-name wordings are recognised', () {
      expect(RawRmpRules.isProductNameRow(marking), isTrue);
      expect(RawRmpRules.isProductNameRow(scaleName), isTrue);
    });

    test('"Additions to..." is not the product name row', () {
      expect(RawRmpRules.isProductNameRow(additions), isFalse);
    });

    test('a missing batch code always seizes', () {
      expect(seize({1, 2, 3, 5}, absent: false), isTrue);
    });

    test('a product name shown but deficient does not seize', () {
      expect(seize({2, 3, 4, 5}, absent: false), isFalse);
    });

    test('a product name not indicated at all seizes', () {
      expect(seize({2, 3, 4, 5}, absent: true), isTrue);
    });

    test('other deviations alone never seize', () {
      expect(seize({1, 2, 3, 4}, absent: true), isFalse);
    });

    test('a fully compliant checklist never seizes', () {
      expect(seize({1, 2, 3, 4, 5}, absent: true), isFalse);
    });

    test('rows in an absent section cannot seize', () {
      expect(
        RawRmpRules.seizureRequired(
          items: items,
          present: const {RawRmpSection.marking},
          compliantItemIds: const {1, 3, 5},
          productNameAbsent: true,
        ),
        isFalse,
      );
    });
  });
}
