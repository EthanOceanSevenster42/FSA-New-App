import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

/// Total Meat Content is worked out from the checklist (Ethan, 2026-10-02):
/// the meat — row 1 alone; mechanically recovered meat (row 5) is one of
/// the other ingredients — over the whole product, rows 1 to 6 added up,
/// × 100. Row 7 has no box of its own.
void main() {
  /// Rows the test does not name are zero, not blank: a blank is "not
  /// weighed yet", which makes the whole sum null on purpose. The checklist
  /// gained a "Food stuff" row on 2026-10-04 and these cases name only the
  /// first few amounts, so the unnamed ones have to be a number for the sum
  /// to be worked out at all.
  List<CompositionAnswer> rows(List<String> grams, String meat) => [
        for (var i = 0; i < CompositionChecklist.items.length; i++)
          CompositionAnswer(
            contributionGrams: i < grams.length ? grams[i] : '0',
            meatGrams: i == CompositionChecklist.totalMeatIndex ? meat : '',
          ),
      ];

  group('the sum', () {
    test('meat is row 1; the rest, MDM included, is the rows under it', () {
      final a = rows(['60', '10', '10', '10', '20', '10'], '');
      expect(CompositionChecklist.meatOf(a), 60);
      expect(CompositionChecklist.otherOf(a), 60);
      expect(CompositionChecklist.percentText(
              CompositionChecklist.totalMeatPercent(a)!),
          '50.0%');
    });

    test('works to one decimal place and takes a comma', () {
      final a = rows(['12,5', '0', '0', '0', '0', '25'], '');
      expect(CompositionChecklist.percentText(
              CompositionChecklist.totalMeatPercent(a)!),
          '33.3%');
    });

    test('is nothing until every amount is a number with something to divide',
        () {
      expect(CompositionChecklist.totalMeatPercent(
              rows(['', '0', '0', '0', '0', '10'], '')),
          isNull);
      expect(CompositionChecklist.totalMeatPercent(
              rows(['10', '0', '0', '0', '', '10'], '')),
          isNull);
      // All meat and nothing else is 100%; nothing at all is nothing.
      expect(CompositionChecklist.totalMeatPercent(
              rows(['80', '0', '0', '0', '0', '0'], '')),
          100);
      expect(CompositionChecklist.totalMeatPercent(
              rows(['0', '0', '0', '0', '0', '0'], '')),
          isNull);
      expect(CompositionChecklist.totalMeatPercent(
              rows(['-5', '0', '0', '0', '0', '10'], '')),
          isNull);
    });
  });

  test('the Meat box is kept on the record', () {
    final answers = CompositionChecklist.blank();
    answers[CompositionChecklist.totalMeatIndex] =
        const CompositionAnswer(meatGrams: '80', contributionGrams: '80.0%');
    final back = CompositionChecklist.decode(
        CompositionChecklist.encode(answers))[CompositionChecklist.totalMeatIndex];
    expect(back.meatGrams, '80');
    expect(CompositionChecklist.isAnswered(answers), isTrue);
  });

  testWidgets('the form works it out as the amounts are typed',
      (tester) async {
    // Tall enough that the whole form is built at once.
    tester.view.physicalSize = const Size(1080, 14000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = LocalDatabase(NativeDatabase.memory());
    final raw = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await raw.writeReferenceForTest(
        jsonDecode(File('assets/reference/rawrmp_reference.json')
            .readAsStringSync()) as Map<String, dynamic>);
    await tester.pumpWidget(MaterialApp(
      home: RawRmpInspectionForm(
        repository: raw,
        captureRepository:
            PoultryCaptureRepository(database: db, baseUrl: 'http://example.test'),
        inspectorName: 'ethan',
        recordKind: RawRecordKind.composition,
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> typeInto(Finder label, String text) async {
      await tester.enterText(
          find.descendant(
            of: find.ancestor(of: label, matching: find.byType(Column)).first,
            matching: find.byType(TextFormField),
          ),
          text);
      await tester.pumpAndSettle();
    }

    final grams = find.textContaining('Contribution (kg)', findRichText: true);
    // One amount per contribution box — the checklist gained a "Food stuff"
    // row on 2026-10-04 and an MDM row on 2026-10-19, and a box left blank
    // is "not weighed yet", which holds the whole sum back. Meat 60
    // against 60 of everything else, MDM among the others.
    const amounts = ['60', '10', '10', '10', '20', '10', '0', '0'];
    for (var n = 0; n < amounts.length; n++) {
      await typeInto(grams.at(n), amounts[n]);
    }
    // Total Meat Content has no box of its own: it is only the result.
    expect(find.textContaining('Meat (kg)', findRichText: true), findsNothing);
    expect(find.text('Total meat content'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
