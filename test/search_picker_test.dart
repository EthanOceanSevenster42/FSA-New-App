import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/presentation/search_picker.dart';

/// A record with a name and an address, so we can prove the address is not
/// searched.
class _Place {
  const _Place(this.name, this.address);
  final String name;
  final String address;
}

const _places = <_Place>[
  _Place('Alpha Packers', '1 Market Street, Bloemfontein'),
  _Place('Amanzi Poultry', '2 Long Street, Durban'),
  _Place('Cape Egg Packers', '80 Voortrekker Street, Paarl'),
  _Place('Mangaung Municipal Market', '19 Mandela Drive, Bloemfontein'),
  _Place('Yolk Valley Farm', '5 Station Road, Tzaneen'),
  _Place('Zululand Yolks', '7 Church Street, Vryheid'),
  _Place('Sunny Yard Eggs', '9 Main Road, Paarl'),
];

void main() {
  late TextEditingController controller;
  _Place? chosen;

  setUp(() {
    controller = TextEditingController();
    chosen = null;
  });
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<_Place> options = _places,
    int minQueryLength = 2,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SearchPickerField<_Place>(
              label: 'Inspection facility name',
              controller: controller,
              options: options,
              optionLabel: (p) => p.name,
              optionSubtitle: (p) => p.address,
              onSelected: (p) => chosen = p,
              minQueryLength: minQueryLength,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    // Matching is debounced so a fast typist triggers one pass, not one per
    // letter. pumpAndSettle waits for frames, not timers, so the clock has to
    // be advanced past the debounce explicitly.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  group('nothing is listed until you actually search', () {
    testWidgets('focusing the empty field lists no records', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      for (final place in _places) {
        expect(find.text(place.name), findsNothing);
      }
      expect(find.textContaining('Type at least 2 letters'), findsOneWidget);
    });

    testWidgets('one letter is not a search', (tester) async {
      await pump(tester);
      await search(tester, 'y');

      // A single letter would list most of the directory; that is the
      // behaviour being prevented.
      expect(find.text('Alpha Packers'), findsNothing);
      expect(find.text('Yolk Valley Farm'), findsNothing);
      expect(find.textContaining('Type at least 2 letters'), findsOneWidget);
    });
  });

  group('matching', () {
    testWidgets('searching "yo" never offers a name without it',
        (tester) async {
      await pump(tester);
      await search(tester, 'yo');

      expect(find.text('Yolk Valley Farm'), findsOneWidget);
      expect(find.text('Zululand Yolks'), findsOneWidget);
      // The complaint that started this: unrelated A-names appearing.
      expect(find.text('Alpha Packers'), findsNothing);
      expect(find.text('Amanzi Poultry'), findsNothing);
      expect(find.text('Cape Egg Packers'), findsNothing);
    });

    testWidgets('the address is not searched', (tester) async {
      await pump(tester);
      await search(tester, 'bloem');

      // Both Bloemfontein addresses must stay hidden: neither name contains
      // "bloem", so offering them looks like the search is broken.
      expect(find.text('Mangaung Municipal Market'), findsNothing);
      expect(find.text('Alpha Packers'), findsNothing);
      expect(find.textContaining('No name contains "bloem"'), findsOneWidget);
    });

    testWidgets('every match is offered, not a truncated head',
        (tester) async {
      // 40 matches — more than any fixed cap would have shown.
      final many = [
        for (var i = 0; i < 40; i++)
          _Place('Yolk Farm ${i.toString().padLeft(2, '0')}', 'Somewhere'),
        const _Place('Alpha Packers', 'Elsewhere'),
      ];
      await pump(tester, options: many);
      await search(tester, 'yolk');

      expect(find.textContaining('40 matches'), findsOneWidget);
    });

    testWidgets('names starting with the query come first', (tester) async {
      await pump(tester);
      await search(tester, 'yol');

      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.contains('Yolk') || s.contains('Yolks'))
          .toList();

      // "Yolk Valley Farm" starts with the query; "Zululand Yolks" merely
      // contains it.
      expect(names.first, 'Yolk Valley Farm');
    });

    testWidgets('search is case-insensitive', (tester) async {
      await pump(tester);
      await search(tester, 'CAPE');

      expect(find.text('Cape Egg Packers'), findsOneWidget);
    });

    testWidgets('a match count is always shown', (tester) async {
      await pump(tester);
      await search(tester, 'yo');

      expect(find.textContaining('2 matches'), findsOneWidget);
    });

    testWidgets('one match reads singular', (tester) async {
      await pump(tester);
      await search(tester, 'cape');

      expect(find.textContaining('1 match'), findsOneWidget);
      expect(find.textContaining('1 matches'), findsNothing);
    });
  });

  group('typing stays responsive', () {
    testWidgets('a fast typist runs one search, not one per letter',
        (tester) async {
      // Counting how often the label is read is a proxy for how much work a
      // keystroke costs: it is called once per record per matching pass.
      var labelReads = 0;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SearchPickerField<_Place>(
                label: 'Facility',
                controller: controller,
                options: _places,
                optionLabel: (p) {
                  labelReads++;
                  return p.name;
                },
                onSelected: (p) => chosen = p,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      labelReads = 0;

      // Six keystrokes in quick succession, faster than the debounce.
      for (final query in ['y', 'yo', 'yol', 'yolk', 'yolk ', 'yolk v']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pump(const Duration(milliseconds: 20));
      }
      final duringTyping = labelReads;

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // Nothing scanned the directory while the keys were still coming.
      expect(duringTyping, 0,
          reason: 'the directory was scanned mid-typing');
      expect(find.text('Yolk Valley Farm'), findsOneWidget);
    });

    testWidgets('the stale list is not shown while a search is pending',
        (tester) async {
      await pump(tester);
      await search(tester, 'yolk');
      expect(find.text('Yolk Valley Farm'), findsOneWidget);

      // Type something that matches nothing, but do not wait for the debounce.
      await tester.enterText(find.byType(TextField), 'cape');
      await tester.pump(const Duration(milliseconds: 20));

      // Showing the old "Yolk" result under the query "cape" would be a lie.
      expect(find.text('Yolk Valley Farm'), findsNothing);
      expect(find.text('Searching…'), findsOneWidget);
    });

    testWidgets('clearing the field is immediate, not debounced',
        (tester) async {
      await pump(tester);
      await search(tester, 'yolk');
      expect(find.text('Yolk Valley Farm'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Yolk Valley Farm'), findsNothing);
      expect(find.textContaining('Type at least 2 letters'), findsOneWidget);
    });
  });

  group('selection', () {
    testWidgets('tapping a result fills the field and reports it',
        (tester) async {
      await pump(tester);
      await search(tester, 'yolk');
      await tester.tap(find.text('Yolk Valley Farm'));
      await tester.pumpAndSettle();

      expect(chosen?.name, 'Yolk Valley Farm');
    });

    testWidgets('free text is preserved for a premises not on the list',
        (tester) async {
      await pump(tester);
      await search(tester, 'Brand New Packhouse');

      // The name stays in the field — an inspector standing at premises the
      // directory has never carried must still be able to record the visit.
      expect(controller.text, 'Brand New Packhouse');
      expect(find.textContaining('No name contains'), findsOneWidget);
    });

    testWidgets('a name not on the list can be registered', (tester) async {
      String? asked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPickerField<_Place>(
              label: 'Inspection facility name',
              controller: controller,
              options: _places,
              optionLabel: (p) => p.name,
              onSelected: (_) {},
              addNewLabel: 'Add as new premises',
              onAddNew: (typed) async => asked = typed,
            ),
          ),
        ),
      );
      await search(tester, 'Brand New Packhouse');

      final button = find.textContaining('Add as new premises');
      expect(button, findsOneWidget,
          reason: 'the inspector must be able to register it, not just type '
              'a name nobody else will ever see');

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(asked, 'Brand New Packhouse',
          reason: 'the sheet opens pre-filled with what was typed');
      expect(chosen, isNull);
    });
  });

  testWidgets('an empty directory says so rather than showing no matches',
      (tester) async {
    await pump(tester, options: const []);
    await search(tester, 'yolk');

    // "Nothing matched" would be misleading when nothing was ever downloaded.
    expect(find.textContaining('No records on this device'), findsOneWidget);
  });
}
