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

/// The Compositional Checklist on its own: every field is required, the
/// other ingredients included (Ethan, 2026-09-29).
void main() {
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

  /// Scrolls from the top until [target] is built.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 300,
        scrollable: find.byType(Scrollable).first, maxScrolls: 80);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, RawRecordKind kind) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: raw,
        captureRepository: capture,
        inspectorName: 'ethan',
        recordKind: kind,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The text box under the field labelled [label].
  Future<void> type(WidgetTester tester, String label, String value) async {
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

  /// A SearchPickerField holds a plain TextField, not a TextFormField, so
  /// it needs its own reach.
  Future<void> pick(WidgetTester tester, String label, String value) async {
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

  Future<void> pressNext(WidgetTester tester) async {
    await reveal(tester, find.text('NEXT'));
    await tester.tap(find.text('NEXT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('finishing refuses until the checklist is filled in',
      (tester) async {
    await open(tester, RawRecordKind.composition);
    await type(tester, 'Batch Number', '12345');
    await type(tester, 'Primary Sample Size (g)', '500');
    // Required since build 2221, and asked before the checklist: without
    // it the refusal is about the product name and the rows are never
    // reached, which is what this test is actually about.
    await pick(tester, 'Certain Raw Processed Meat Product Name',
        'Beef Boerewors');

    await pressNext(tester);
    expect(
        find.textContaining('Row 1: Contribution (kg) is required'),
        findsOneWidget);
    await tester.pumpAndSettle();

    final saved = await db.select(db.rawRmpInspections).get();
    expect(saved.where((r) => r.status == 'completed'), isEmpty,
        reason: 'nothing finishes with the checklist half done');
  });

  testWidgets('the fields read as required on the checklist', (tester) async {
    await open(tester, RawRecordKind.composition);
    await reveal(tester, find.textContaining('Every field is required'));
    expect(find.textContaining('Every field is required'), findsOneWidget);
  });
}
