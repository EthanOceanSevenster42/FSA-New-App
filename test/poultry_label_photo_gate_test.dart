import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
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
    await tester.scrollUntilVisible(find.text('Complete'), 200,
        scrollable: find.byType(Scrollable).first);
    // scrollUntilVisible stops at the first partly-visible pixel; the button
    // has to be wholly on screen or the tap lands outside it.
    await tester.ensureVisible(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0 of 2 taken'), findsOneWidget);
    expect(await db.select(db.poultryLabelInspections).get(), isEmpty);
  });
}
