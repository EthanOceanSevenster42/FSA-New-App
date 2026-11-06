import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/required_label.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_repository.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_label_checklist_form.dart';

/// The photographs a poultry label checklist cannot be finished without.
///
/// The original counts to `[n / 2]` and only then enables
/// `switchIsLabelandPackListComplete`. The label is what the whole checklist
/// is read against, so a finished record without it evidences nothing.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository capture;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    capture =
        PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    final repo = PoultryRepository(database: db, baseUrl: 'http://example.test');
    final raw =
        await File('assets/reference/poultry_reference.json').readAsString();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PoultryLabelChecklistForm(
        repository:
            PoultryRepository(database: db, baseUrl: 'http://example.test'),
        captureRepository: capture,
        inspectorName: 'ethan',
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('asks for two and allows a third', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(
        find.textContaining('the first 2 are required'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(
      find.textContaining('0 of 3 taken — the first 2 are required'),
      findsOneWidget,
    );
  });

  testWidgets('refuses to complete until both are taken', (tester) async {
    await open(tester);
    // The Product Name is checked before the photographs are, so without it
    // the form stops there and the photograph gate is never reached. It sits
    // well down a long list, so it has to be scrolled to before it is built.
    final productLabel = find.byWidgetPredicate(
        (w) => w is RequiredLabel && w.label == 'Product Name');
    await tester.scrollUntilVisible(productLabel, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.ancestor(of: productLabel, matching: find.byType(LabelledField)),
        matching: find.byType(TextField),
      ),
      'Whole frozen chicken',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Complete'), 200,
        scrollable: find.byType(Scrollable).first);
    // scrollUntilVisible stops at the first partly-visible pixel; the button
    // has to be wholly on screen or the tap lands outside it.
    await tester.ensureVisible(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0 of 2 taken'), findsOneWidget);
    // Typing starts a draft — the forms autosave so an install cannot lose
    // one — so what matters is that nothing was COMPLETED, not that nothing
    // was written at all.
    final saved = await db.select(db.poultryLabelInspections).get();
    expect(
      saved.where((r) => r.status == 'completed' || r.status == 'ready'),
      isEmpty,
      reason: 'the checklist must not complete without both photographs',
    );
  });
}
