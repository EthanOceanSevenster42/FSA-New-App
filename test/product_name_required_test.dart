import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';

/// A raw or processed-meat inspection must name the product it looked at
/// (Ethan, 2026-10-14). Some records reached APS with a blank "Product Name
/// Inspected" because the field was left empty at capture; now a save is
/// refused until a product is chosen, or the product name is marked as not
/// shown on the label.
void main() {
  const kMsg = 'Product Name is required';

  Future<void> reveal(WidgetTester tester, Finder target) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 100);
    await tester.pumpAndSettle();
  }

  Future<void> typeUnder(
      WidgetTester tester, String label, String value) async {
    final caption = find.textContaining(label, findRichText: true).first;
    await reveal(tester, caption);
    final box = find
        .descendant(
          of: find
              .ancestor(
                of: caption,
                matching: find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == 'LabelledField'),
              )
              .first,
          matching: find.byType(TextFormField),
        )
        .first;
    await tester.enterText(box, value);
    await tester.pumpAndSettle();
  }

  /// The product field is a SearchPickerField (a plain TextField bound to the
  /// product controller), not a LabelledField, so it is typed into directly.
  Future<void> typePicker(
      WidgetTester tester, String label, String value) async {
    final caption = find.textContaining(label, findRichText: true).first;
    await reveal(tester, caption);
    final box = find
        .descendant(
          of: find
              .ancestor(
                of: caption,
                matching: find.byWidgetPredicate((w) =>
                    w.runtimeType.toString().startsWith('SearchPickerField')),
              )
              .first,
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(box, value);
    await tester.pumpAndSettle();
  }

  group('raw', () {
    late LocalDatabase db;
    late RawRmpRepository raw;
    late PoultryCaptureRepository capture;

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

    Future<void> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: RawRmpInspectionForm(
          repository: raw,
          captureRepository: capture,
          inspectorName: 'ethan',
          recordKind: RawRecordKind.inspection,
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await reveal(tester, find.text('NEXT'));
      await tester.tap(find.text('NEXT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a blank product blocks finishing', (tester) async {
      await open(tester);
      await typeUnder(tester, 'Batch Number', '12345');
      await next(tester);

      expect(find.textContaining(kMsg), findsOneWidget);
      final saved = await db.select(db.rawRmpInspections).get();
      expect(saved.where((r) => r.status == 'completed'), isEmpty,
          reason: 'nothing finishes without a product name');
    });

    testWidgets('naming the product clears the requirement', (tester) async {
      await open(tester);
      await typeUnder(tester, 'Batch Number', '12345');
      await typePicker(
          tester, 'Certain Raw Processed Meat Product Name', 'Beef Boerewors');
      await next(tester);

      expect(find.textContaining(kMsg), findsNothing);
    });
  });

  group('pmp', () {
    late LocalDatabase db;
    late PmpRepository pmp;
    late PoultryCaptureRepository capture;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      pmp = PmpRepository(database: db, baseUrl: 'http://example.test');
      capture =
          PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await pmp.writeReferenceForTest(
          jsonDecode(await File('assets/reference/pmp_reference.json')
              .readAsString()) as Map<String, dynamic>);
    });
    tearDown(() => db.close());

    testWidgets('a blank product blocks finishing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: PmpInspectionForm(
          repository: pmp,
          captureRepository: capture,
          inspectorName: 'ethan',
        ),
      ));
      await tester.pumpAndSettle();

      await typeUnder(tester, 'Batch Number', '12345');
      await reveal(tester, find.text('Complete'));
      await tester.tap(find.text('Complete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining(kMsg), findsOneWidget);
    });
  });
}
