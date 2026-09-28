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

/// Total Meat Content is worked out, the way an inspector who filled the
/// form in by hand described it (Ethan, 2026-09-24): meat over the meat and
/// all the other ingredients, × 100.
void main() {
  group('the sum', () {
    test('80 g of meat and 20 g of everything else is 80%', () {
      expect(CompositionChecklist.totalMeatPercent('80', '20'), 80);
      expect(CompositionChecklist.percentText(80), '80.0%');
    });

    test('works to one decimal place', () {
      final p = CompositionChecklist.totalMeatPercent('62.5', '37.8')!;
      expect(CompositionChecklist.percentText(p), '62.3%');
    });

    test('takes a comma as the decimal mark', () {
      expect(CompositionChecklist.totalMeatPercent('50,0', '50'), 50);
    });

    test('is nothing until both are numbers with something to divide', () {
      expect(CompositionChecklist.totalMeatPercent('', '20'), isNull);
      expect(CompositionChecklist.totalMeatPercent('80', ''), isNull);
      expect(CompositionChecklist.totalMeatPercent('eighty', '20'), isNull);
      expect(CompositionChecklist.totalMeatPercent('0', '0'), isNull);
      expect(CompositionChecklist.totalMeatPercent('-5', '20'), isNull);
    });

    test('all meat is 100%, no meat is 0%', () {
      expect(CompositionChecklist.totalMeatPercent('100', '0'), 100);
      expect(CompositionChecklist.totalMeatPercent('0', '100'), 0);
    });
  });

  test('the two amounts are kept on the record', () {
    final answers = CompositionChecklist.blank();
    answers[CompositionChecklist.totalMeatIndex] = const CompositionAnswer(
      meatGrams: '80',
      otherGrams: '20',
      contributionGrams: '80.0%',
    );
    final back = CompositionChecklist.decode(
        CompositionChecklist.encode(answers))[CompositionChecklist.totalMeatIndex];
    expect(back.meatGrams, '80');
    expect(back.otherGrams, '20');
    expect(back.totalMeatPercent, 80);
    expect(CompositionChecklist.isAnswered(answers), isTrue);
  });

  testWidgets('the form works it out as the amounts are typed',
      (tester) async {
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

    Finder boxFor(String label) => find.descendant(
          of: find.ancestor(
              of: find.text(label), matching: find.byType(Column)).first,
          matching: find.byType(TextFormField),
        );

    await tester.scrollUntilVisible(find.text('Meat (g)'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter both amounts'), findsOneWidget);

    await tester.enterText(boxFor('Meat (g)'), '80');
    await tester.enterText(boxFor('All other ingredients (g)'), '20');
    await tester.pumpAndSettle();

    expect(find.text('Total meat content: 80.0%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
