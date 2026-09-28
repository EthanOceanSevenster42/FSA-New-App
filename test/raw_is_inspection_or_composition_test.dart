import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';
import 'package:fsa_app/features/visits/presentation/store_visit_pages.dart';

/// Raw is asked the way poultry is: the raw inspection, or the
/// compositional checklist on its own (Ethan, 2026-09-24). The form then
/// shows only the part that was chosen.
void main() {
  late LocalDatabase db;
  late RawRmpRepository raw;
  late PoultryCaptureRepository capture;
  final when = DateTime(2026, 9, 24, 9, 30);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    raw = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await raw.writeReferenceForTest(
        jsonDecode(await File('assets/reference/rawrmp_reference.json')
            .readAsString()) as Map<String, dynamic>);
  });
  tearDown(() => db.close());

  Future<void> openForm(WidgetTester tester, RawRecordKind kind,
      {String? existingUuid}) async {
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: raw,
        captureRepository: capture,
        inspectorName: 'ethan',
        recordKind: kind,
        existingUuid: existingUuid,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Whether [text] is anywhere down the form, scrolling to look.
  Future<bool> onForm(WidgetTester tester, String text) async {
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, 20000));
    await tester.pumpAndSettle();
    for (var i = 0; i < 80; i++) {
      if (find.text(text).evaluate().isNotEmpty) return true;
      await tester.drag(list, const Offset(0, -300));
      await tester.pump();
    }
    return find.text(text).evaluate().isNotEmpty;
  }

  testWidgets('the visit asks which, when raw is started', (tester) async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          inspectorUsername: const Value('ethan'),
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
          facilityAddress: const Value('1 Main Road'),
          contactEmail: const Value('k@kroon.test'),
          facilityType: const Value('Retailer'),
          inspectionReason: const Value('Inspection'),
          distanceTravelledKm: const Value(12),
          // Required at the door once raw is on the plan.
          producerName: const Value('Nulaid Meats'),
          plannedRaw: const Value(1),
        ));
    await tester.pumpWidget(MaterialApp(
      home: StoreVisitPage(
        visitUuid: 'visit-1',
        visits: VisitRepository(db),
        eggs: EggsRepository(database: db, baseUrl: ''),
        eggsSync: null,
        poultry: PoultryRepository(database: db, baseUrl: ''),
        poultryCapture: capture,
        rawRmp: raw,
        pmp: PmpRepository(database: db, baseUrl: ''),
        inspectorName: 'ethan',
        canRemoveRecords: false,
      ),
    ));
    await tester.pumpAndSettle();

    const start = 'START CERTAIN RAW PROCESSED MEAT PRODUCT INSPECTION';
    await tester.scrollUntilVisible(find.text(start), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(start));
    await tester.pumpAndSettle();
    await tester.tap(find.text(start));
    await tester.pumpAndSettle();

    expect(find.text('Which raw inspection?'), findsOneWidget);
    expect(find.text('Raw inspection'), findsOneWidget);
    expect(find.text('Compositional checklist'), findsOneWidget);
    // Drawn like the poultry chooser: the same opening line and an arrow on
    // every choice.
    expect(find.text('Raw is inspected in two ways. Pick the one you are '
        'doing now — the other can be done after it.'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byIcon(Icons.chevron_right)),
        findsNWidgets(2));

    await tester.tap(find.text('Compositional checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Compositional Checklist'), findsOneWidget,
        reason: 'the form opens as the compositional checklist');
  });

  testWidgets('the compositional checklist shows no labelling or sampling',
      (tester) async {
    await openForm(tester, RawRecordKind.composition);
    expect(await onForm(tester, 'COMPOSITIONAL REQUIREMENTS CHECKLIST'),
        isTrue);
    expect(await onForm(tester, 'MARK/LABEL CHECKLIST'), isFalse);
    expect(await onForm(tester, 'SAMPLE DETAILS'), isFalse);
  });

  testWidgets('the raw inspection shows no compositional checklist',
      (tester) async {
    await openForm(tester, RawRecordKind.inspection);
    expect(await onForm(tester, 'MARK/LABEL CHECKLIST'), isTrue);
    expect(await onForm(tester, 'SAMPLE DETAILS'), isTrue);
    expect(await onForm(tester, 'COMPOSITIONAL REQUIREMENTS CHECKLIST'),
        isFalse);
  });

  testWidgets('a record from before the question still shows both',
      (tester) async {
    await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'old',
          inspectedAt: when,
          updatedAt: when,
        ));
    await openForm(tester, RawRecordKind.both, existingUuid: 'old');
    expect(await onForm(tester, 'MARK/LABEL CHECKLIST'), isTrue);
    expect(await onForm(tester, 'COMPOSITIONAL REQUIREMENTS CHECKLIST'),
        isTrue);
  });

  testWidgets('a resumed compositional checklist stays one', (tester) async {
    await db.into(db.rawRmpInspections).insert(RawRmpInspectionsCompanion.insert(
          clientUuid: 'comp',
          inspectedAt: when,
          updatedAt: when,
          recordKind: Value(RawRecordKind.composition.stored),
        ));
    // Opened with no kind given, as Inspection Management opens it.
    await openForm(tester, RawRecordKind.both, existingUuid: 'comp');
    expect(find.text('Compositional Checklist'), findsOneWidget);
    expect(await onForm(tester, 'MARK/LABEL CHECKLIST'), isFalse);
  });

  test('a compositional checklist is named for what it is in the visit',
      () async {
    await db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
          uuid: 'visit-1',
          startedAt: when,
          facilityName: const Value('Kroon Foods'),
        ));
    for (final (uuid, kind) in [
      ('a', RawRecordKind.composition),
      ('b', RawRecordKind.inspection),
    ]) {
      await db
          .into(db.rawRmpInspections)
          .insert(RawRmpInspectionsCompanion.insert(
            clientUuid: uuid,
            visitUuid: const Value('visit-1'),
            inspectedAt: when,
            updatedAt: when,
            recordKind: Value(kind.stored),
          ));
    }
    final labels = {
      for (final m in await VisitRepository(db).members('visit-1'))
        m.uuid: m.label,
    };
    expect(labels['a'], 'Compositional checklist');
    expect(labels['b'], 'Certain Raw Processed Meat Product inspection');
  });

  test('the kind survives the round trip through storage', () {
    for (final k in RawRecordKind.values) {
      expect(RawRecordKind.of(k.stored), k);
    }
    expect(RawRecordKind.of('anything else'), RawRecordKind.both);
  });

  testWidgets('inside a visit it does not ask again what the door asked',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: raw,
        captureRepository: capture,
        inspectorName: 'ethan',
        recordKind: RawRecordKind.inspection,
        // A type and reason the raw lists have nothing like: the form used
        // to fall back to asking them itself.
        visit: const VisitPrefill(
          uuid: 'visit-1',
          facilityName: 'Kroon Foods',
          facilityAddress: '1 Main Road',
          facilityPhone: '',
          contactPerson: 'K. Kroon',
          contactEmail: 'k@kroon.test',
          representative: 'K. Kroon',
          managerName: '',
          managerEmail: '',
          facilityType: 'Nothing like it',
          inspectionReason: 'Nothing like it',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (final asked in [
      'Reason for Inspection',
      'Inspection Facility Type',
      'Follow Up Rejection Particulars',
    ]) {
      expect(await onForm(tester, asked), isFalse, reason: asked);
    }
  });

  testWidgets('on its own it still asks the reason and facility type, but '
      'not the follow-up particulars', (tester) async {
    await openForm(tester, RawRecordKind.inspection);
    expect(await onForm(tester, 'Reason for Inspection'), isTrue);
    expect(await onForm(tester, 'Inspection Facility Type'), isTrue);
    expect(await onForm(tester, 'Follow Up Rejection Particulars'), isFalse);
  });
}
