import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/data/restricted_particulars_catalogue.dart';
import 'package:fsa_app/core/widgets/restricted_particulars_picker.dart';

/// Every form offers the same restricted particulars: the office's lists
/// for every commodity, merged, and then the typing entry (Ethan,
/// 2026-09-25: "make sure they all use the same one"). A pick from the
/// form's own list keeps its id; one from another list is kept as text on
/// the record, the way a typed-in one is, so no form sends another
/// commodity's id to the server.
void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    await db.into(db.eggRestrictedParticulars).insert(
        EggRestrictedParticularsCompanion.insert(
            id: const Value(1), keyword: 'Free Range', sortOrder: const Value(2)));
    await db.into(db.eggRestrictedParticulars).insert(
        EggRestrictedParticularsCompanion.insert(
            id: const Value(2), keyword: 'Grain Fed', sortOrder: const Value(1)));
    await db.into(db.eggRestrictedParticulars).insert(
        EggRestrictedParticularsCompanion.insert(
            id: const Value(3), keyword: 'Retired', isActive: const Value(false)));
    await db.into(db.poultryRestrictedParticulars).insert(
        PoultryRestrictedParticularsCompanion.insert(
            id: const Value(1), description: 'Free Range/Vryloop'));
    await db.into(db.poultryRestrictedParticulars).insert(
        PoultryRestrictedParticularsCompanion.insert(
            id: const Value(4), description: 'Other'));
    await db.into(db.rawRmpRestrictedParticulars).insert(
        RawRmpRestrictedParticularsCompanion.insert(
            id: const Value(1), description: 'Other'));
    await db.into(db.pmpRestrictedParticulars).insert(
        PmpRestrictedParticularsCompanion.insert(
            id: const Value(1), description: 'grain fed'));
    await db.into(db.pmpRestrictedParticulars).insert(
        PmpRestrictedParticularsCompanion.insert(
            id: const Value(2), description: 'Organic'));
  });
  tearDown(() => db.close());

  test('the catalogue is every list once, in office order, Other last',
      () async {
    expect(await RestrictedParticularsCatalogue.names(db), [
      'Grain Fed',
      'Free Range',
      'Free Range/Vryloop',
      'Organic',
      'Other',
    ]);
  });

  test('merging keeps the first spelling and drops blanks', () {
    expect(
        RestrictedParticularsCatalogue.merge(
            ['Other', 'Free Range', ' ', 'free range', 'Extra', 'OTHER']),
        ['Free Range', 'Extra', 'Other']);
  });

  group('the picker', () {
    final selected = <int>{};
    final typed = <String>{};
    var changes = 0;

    setUp(() {
      selected.clear();
      typed.clear();
      changes = 0;
    });

    Future<void> pump(WidgetTester tester, {Set<String>? typedSet}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                RestrictedParticularsPicker<({int id, String name})>(
              // A raw form: its own list is "Other" alone.
              options: const [(id: 1, name: 'Other')],
              optionId: (o) => o.id,
              optionLabel: (o) => o.name,
              selected: selected,
              typed: typedSet,
              shared: const ['Free Range', 'Other', 'free range'],
              onChanged: () => setState(() => changes++),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('Add restricted particular'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers its own list, then the shared names once, then '
        'the typing entry', (tester) async {
      await pump(tester, typedSet: typed);
      await openMenu(tester);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Free Range'), findsOneWidget);
      expect(find.text('free range'), findsNothing);
      expect(find.text(RestrictedParticularsPicker.typeItInLabel),
          findsOneWidget);
    });

    testWidgets('a shared name off another list is kept as text, without '
        'the pencil', (tester) async {
      await pump(tester, typedSet: typed);
      await openMenu(tester);
      await tester.tap(find.text('Free Range'));
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(typed, {'Free Range'});
      expect(changes, 1);
      // Shown as a chip like any pick, not as something written in.
      final chip = tester.widget<InputChip>(find.ancestor(
          of: find.text('Free Range'), matching: find.byType(InputChip)));
      expect(chip.avatar, isNull);
    });

    testWidgets('a shared name the form lists itself is that option',
        (tester) async {
      await pump(tester, typedSet: typed);
      await openMenu(tester);
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(selected, {1});
      expect(typed, isEmpty);
    });

    testWidgets('with nowhere to keep text, only its own list is offered',
        (tester) async {
      await pump(tester, typedSet: null);
      await openMenu(tester);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Free Range'), findsNothing);
      expect(find.text(RestrictedParticularsPicker.typeItInLabel),
          findsNothing);
    });
  });

  test('every form hands the picker the shared list', () {
    for (final path in [
      'lib/features/eggs/presentation/egg_inspection_form.dart',
      'lib/features/rawrmp/presentation/rawrmp_inspection_form.dart',
      'lib/features/pmp/presentation/pmp_inspection_form.dart',
      'lib/features/poultry/presentation/poultry_label_checklist_form.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('RestrictedParticularsCatalogue.names('), isTrue,
          reason: '$path must load the shared list');
      expect(source.contains(RegExp(r'shared: (_sharedParticulars|reference\.shared),')),
          isTrue,
          reason: '$path must hand the picker the shared list');
    }
  });
}
