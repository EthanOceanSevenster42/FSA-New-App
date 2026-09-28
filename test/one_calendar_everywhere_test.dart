import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/date_field.dart';
import 'package:fsa_app/core/widgets/restricted_particulars_picker.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

/// One calendar, one window, on every date an inspector enters.
///
/// The forms had three: eggs and QUID used [DateField], raw picked into a
/// text box through its own helper, and PMP's packed date had no calendar at
/// all. Their windows differed too — tomorrow onwards here, two years back
/// there — and each was a way a form could refuse the date written on a
/// pack. Now every date field is the same control, opening five years
/// either side of today unless a caller says otherwise (Ethan, 2026-09-23).
void main() {
  group('the calendar window', () {
    test('opens five years back and five years ahead by default', () {
      final field = DateField(label: 'Any date', value: null, onChanged: (_) {});
      final now = DateTime.now();
      expect(field.firstDate.year, now.year - 5);
      expect(field.lastDate.year, now.year + 5);
      expect(field.firstDate.isBefore(now), isTrue);
      expect(field.lastDate.isAfter(now), isTrue);
    });

    test('a caller may still narrow it', () {
      final field = DateField(
        label: 'Filter',
        value: null,
        onChanged: (_) {},
        firstDate: DateTime(2024),
        lastDate: DateTime(2025),
      );
      expect(field.firstDate, DateTime(2024));
      expect(field.lastDate, DateTime(2025));
    });

    test('is drawn bigger on a tablet, as it is on a phone', () {
      // Ethan, 2026-09-25: the fixed-size calendar was small on the tablet.
      expect(DateField.calendarScale(400), 1);
      expect(DateField.calendarScale(720), 1);
      expect(DateField.calendarScale(1280), 1.5);
    });

    test('reads and writes the dd/MM/yyyy the meat forms store', () {
      expect(DateField.dmy(DateTime(2026, 9, 3)), '03/09/2026');
      expect(DateField.parseDmy('03/09/2026'), DateTime(2026, 9, 3));
      expect(DateField.parseDmy(' 3/9/2026 '), DateTime(2026, 9, 3));
      // Anything that is not a date stays as it was typed, not lost.
      expect(DateField.parseDmy('Sept 2026'), isNull);
      expect(DateField.parseDmy('31/02/2026'), isNull);
      expect(DateField.parseDmy(''), isNull);
    });
  });

  group('the meat forms use it', () {
    late LocalDatabase db;
    late Map<String, Map<String, dynamic>> bundles;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      bundles = {
        for (final name in ['rawrmp_reference.json', 'pmp_reference.json'])
          name: jsonDecode(
                  await File('assets/reference/$name').readAsString())
              as Map<String, dynamic>,
      };
    });
    tearDown(() async => db.close());

    Future<void> scrollTo(WidgetTester tester, String text) async {
      await tester.scrollUntilVisible(find.text(text), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('raw: Manufactured/Packed Date is the shared calendar',
        (tester) async {
      final repository =
          RawRmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundles['rawrmp_reference.json']!);
      await tester.pumpWidget(MaterialApp(
        home: RawRmpInspectionForm(
          repository: repository,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'ethan',
        ),
      ));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Manufactured/Packed Date');
      final field = tester.widget<DateField>(find.ancestor(
        of: find.text('Manufactured/Packed Date'),
        matching: find.byType(DateField),
      ));
      expect(field.firstDate.year, DateTime.now().year - 5);
      // Made or packed already: the calendar stops at today.
      expect(field.lastDate.isAfter(DateTime.now()), isFalse);
    });

    testWidgets('PMP: Manufactured/Packed Date has a calendar now, the same one',
        (tester) async {
      final repository =
          PmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundles['pmp_reference.json']!);
      await tester.pumpWidget(MaterialApp(
        home: PmpInspectionForm(
          repository: repository,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'ethan',
        ),
      ));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Manufactured/Packed Date');
      final field = tester.widget<DateField>(find.ancestor(
        of: find.text('Manufactured/Packed Date'),
        matching: find.byType(DateField),
      ));
      expect(field.firstDate.year, DateTime.now().year - 5);
      // Made or packed already: the calendar stops at today.
      expect(field.lastDate.isAfter(DateTime.now()), isFalse);
    });
  });

  test('restricted particulars are one picker on every form', () {
    // Eggs builds RestrictedParticularsPicker directly; raw, PMP and the
    // poultry label form reach the same widget through
    // poultryRestrictedParticulars. Pinned here so a form cannot quietly
    // grow its own list of checkboxes again.
    final forms = [
      'lib/features/eggs/presentation/egg_inspection_form.dart',
      'lib/features/rawrmp/presentation/rawrmp_inspection_form.dart',
      'lib/features/pmp/presentation/pmp_inspection_form.dart',
      'lib/features/poultry/presentation/poultry_label_checklist_form.dart',
    ];
    for (final path in forms) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('RestrictedParticularsPicker<') ||
            source.contains('poultryRestrictedParticulars('),
        isTrue,
        reason: '$path must use the shared restricted particulars picker',
      );
    }
    // And the shared widget itself is what the poultry wrapper builds.
    final wrapper = File(
            'lib/features/poultry/presentation/poultry_form_widgets.dart')
        .readAsStringSync();
    expect(wrapper.contains('RestrictedParticularsPicker<'), isTrue);
    expect(RestrictedParticularsPicker, isNotNull);
  });
}
