import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_quid_setup_form.dart';

/// The QUID set-up, as the original's New Poultry Injector Inspection page
/// runs it: Water and Whole Carcass to start with, each injector held to
/// the regulated standard or a dispensation, and the set-up saved from its
/// "Complete" switch once it is checked and confirmed.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    final poultry =
        PoultryRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await poultry.writeReferenceForTest(
        jsonDecode(await File('assets/reference/poultry_reference.json')
            .readAsString()) as Map<String, dynamic>);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => PoultryQuidSetupForm(
                repository: PoultryRepository(
                    database: db, baseUrl: 'http://example.test'),
                captureRepository: capture,
                inspectorName: 'ethan',
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder labelled(String label) => find.byWidgetPredicate(
      (w) => w is RequiredLabel && w.label == label);

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final field = find.descendant(
      of: find.ancestor(of: labelled(label), matching: find.byType(LabelledField)),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> complete(WidgetTester tester) async {
    final yes = find.descendant(
      of: find.ancestor(
          of: find.text('Injector Inspection Set-Up Details Complete'),
          matching: find.byType(YesNoQuestion)),
      matching: find.text('YES'),
    );
    await tester.ensureVisible(yes);
    await tester.tap(yes);
    await tester.pumpAndSettle();
  }

  /// The injector list's row for [name], read as its three cells.
  List<String> rowFor(WidgetTester tester, String name) {
    final row = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .toList();
  }

  testWidgets('starts on Water and Whole Carcass, as the original does',
      (tester) async {
    await open(tester);
    final chosen = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((c) => c.selected)
        .map((c) => ((c.label as Text).data))
        .toList();
    expect(chosen, containsAll(['Water', 'Whole Carcass', 'Regulated Standard']));
  });

  testWidgets('a regulated injector is held to 10% on whole carcasses',
      (tester) async {
    await open(tester);
    await enter(tester, 'Injector Name/Identifier', 'Brine 1');
    await tap(tester, 'Add');
    expect(rowFor(tester, 'Brine 1'), ['1', 'Brine 1', '10']);
  });

  testWidgets('and to 15% on cuts', (tester) async {
    await open(tester);
    await tap(tester, 'Cuts');
    await enter(tester, 'Injector Name/Identifier', 'Brine 1');
    await tap(tester, 'Add');
    expect(rowFor(tester, 'Brine 1'), ['1', 'Brine 1', '15']);
  });

  testWidgets('a dispensation needs its percentage', (tester) async {
    await open(tester);
    await enter(tester, 'Injector Name/Identifier', 'Brine 2');
    await tap(tester, 'Dispensation');
    await tap(tester, 'Add');
    expect(
        find.text('Dispensation QUID option selected, but no Dispensation '
            'Value has been entered.'),
        findsOneWidget);
    await tap(tester, 'Ok');

    await enter(tester, 'Dispensation QUID %', '12');
    await tap(tester, 'Add');
    expect(rowFor(tester, 'Brine 2'), ['1', 'Brine 2', '12']);
  });

  testWidgets('the Complete switch needs an injector on the list',
      (tester) async {
    await open(tester);
    await enter(tester, 'Inspection Facility Name', 'Rainbow Chickens');
    await complete(tester);
    expect(find.text('No Injector details has been added. Please address.'),
        findsOneWidget);
    expect(await db.select(db.poultryQuidInspections).get(), isEmpty);
  });

  testWidgets('then confirms and saves, each injector with its percentage',
      (tester) async {
    await open(tester);
    await enter(tester, 'Inspection Facility Name', 'Rainbow Chickens');
    await enter(tester, 'Injector Name/Identifier', 'Brine 1');
    await tap(tester, 'Add');
    await enter(tester, 'Injector Name/Identifier', 'Brine 2');
    await tap(tester, 'Dispensation');
    await enter(tester, 'Dispensation QUID %', '12');
    await tap(tester, 'Add');

    await complete(tester);
    expect(find.text('Confirm Setup Data'), findsOneWidget);
    await tap(tester, 'Save');
    await tap(tester, 'OK');

    final row = (await db.select(db.poultryQuidInspections).get()).single;
    expect(row.setupComplete, isTrue);
    expect(row.isWaterChilled, isTrue);
    expect(row.isWholeCarcass, isTrue);
    final injectors = await capture.quidInjectors(row.clientUuid);
    expect([for (final i in injectors) (i.name, i.quidPercent)],
        [('Brine 1', '10'), ('Brine 2', '12')]);
  });
}
