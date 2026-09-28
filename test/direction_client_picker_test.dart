import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/widgets/search_picker.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_direction_form.dart';

/// A direction names its client the way every other screen does: one client
/// picker, carried over from the inspection it was raised from.
///
/// It used to be a "Select client" sheet sliding up from the bottom plus a
/// separate Client box under it — two inputs for one fact, and a different
/// control from the client picker on the inspection forms.
void main() {
  late LocalDatabase db;
  late EggsRepository repository;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repository = EggsRepository(baseUrl: 'http://example.test', database: db);
    // The inspector as the server knows them — the number carries their id.
    await db.into(db.syncedUsers).insert(SyncedUsersCompanion.insert(
          id: const Value(7),
          username: 'Ethan',
        ));
    for (final (id, name, address) in const [
      (1, 'SHOPRITE - Bridge City Mall', '14 Bhejane Road, Inanda'),
      (2, 'Shoprite Polokwane', 'Grobler Street, Polokwane'),
      (3, 'Acacia Country Farm', 'R101, Bela-Bela'),
    ]) {
      await db.into(db.eggClients).insert(EggClientsCompanion.insert(
            id: Value(id),
            name: name,
            physicalAddress: Value(address),
          ));
    }
  });
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester,
      {String? clientName, String? producer}) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(),
      home: EggDirectionForm(
        repository: repository,
        inspectorName: 'Ethan',
        clientName: clientName,
        producerSupplier: producer,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The text box showing [value], and whether it can be typed into.
  bool editable(WidgetTester tester, String value) => !tester
      .widget<TextField>(find.ancestor(
          of: find.text(value), matching: find.byType(TextField)))
      .readOnly;

  testWidgets('the client from the inspection is shown, not asked again',
      (tester) async {
    // Ethan, 2026-09-24: the rejection is against the inspection's client;
    // it is there to read, not to change.
    await pump(tester, clientName: 'SHOPRITE - Bridge City Mall');
    expect(find.byType(SearchPickerField<EggClient>), findsNothing);
    expect(find.text('SHOPRITE - Bridge City Mall'), findsOneWidget);
    expect(editable(tester, 'SHOPRITE - Bridge City Mall'), isFalse);
    expect(find.text('Select client'), findsNothing);
  });

  testWidgets('the producer/supplier from the inspection cannot be changed',
      (tester) async {
    await pump(tester,
        clientName: 'SHOPRITE - Bridge City Mall', producer: 'Nulaid');
    expect(find.text('Nulaid'), findsOneWidget);
    expect(editable(tester, 'Nulaid'), isFalse);
  });

  testWidgets('says nothing about what the rejection covers', (tester) async {
    await pump(tester, clientName: 'SHOPRITE - Bridge City Mall');
    expect(find.textContaining('COVERS'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('a client is picked from the same list as everywhere else',
      (tester) async {
    await pump(tester);
    final picker = find.byType(SearchPickerField<EggClient>);
    final input = find.descendant(of: picker, matching: find.byType(TextField));
    await tester.tap(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'polok');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Shoprite Polokwane'), findsWidgets);
    expect(find.text('Grobler Street, Polokwane'), findsOneWidget,
        reason: 'the address tells look-alike clients apart');
    await tester.tap(find.text('Shoprite Polokwane').last);
    await tester.pumpAndSettle();

    final field = tester.widget<SearchPickerField<EggClient>>(picker);
    expect(field.controller.text, 'Shoprite Polokwane');
  });

  testWidgets('the rejection number is generated, not typed', (tester) async {
    await pump(tester, clientName: 'SHOPRITE - Bridge City Mall');
    final now = DateTime.now();
    final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    // Client 1, inspector 7, today, first of the day.
    final expected = '1-7-$date-001';
    expect(find.text(expected), findsOneWidget,
        reason: 'shown on the form so the inspector can quote it');
    expect(find.text('Select client'), findsNothing);

    // It cannot be edited into something else.
    final numberField = find.ancestor(
        of: find.text(expected), matching: find.byType(TextField));
    expect(tester.widget<TextField>(numberField).readOnly, isTrue);
  });

  testWidgets('a second rejection the same day takes the next sequence',
      (tester) async {
    await db.writeSyncState(EggsRepository.sessionUserKey, 'Ethan');
    final now = DateTime.now();
    await db.into(db.eggDirections).insert(EggDirectionsCompanion.insert(
          clientUuid: 'earlier-today',
          inspectorUsername: const Value('Ethan'),
          issuedAt: now,
          updatedAt: now,
          status: const Value('completed'),
          directionNumber: const Value('2-7-x-001'),
          clientName: const Value('Shoprite Polokwane'),
        ));
    await pump(tester, clientName: 'SHOPRITE - Bridge City Mall');
    final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    expect(find.text('1-7-$date-002'), findsOneWidget);
  });
}
