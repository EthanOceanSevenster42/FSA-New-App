import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/presentation/date_field.dart';
import 'package:fsa_app/features/eggs/presentation/required_label.dart';

void main() {
  DateTime? value;

  setUp(() => value = null);

  Future<void> pump(
    WidgetTester tester, {
    DateTime? initial,
    bool isRequired = false,
    String? errorText,
    String? helperText,
  }) async {
    value = initial;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DateField(
              label: 'Best before',
              value: value,
              onChanged: (d) => setState(() => value = d),
              firstDate: DateTime(2026, 8, 2),
              lastDate: DateTime(2029, 1, 1),
              isRequired: isRequired,
              errorText: errorText,
              helperText: helperText,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('reading the date', () {
    testWidgets('shows day-first with the weekday spelled out',
        (tester) async {
      await pump(tester, initial: DateTime(2026, 8, 15));

      // 15 August 2026 is a Saturday. Day-first matches the rest of the app,
      // and the weekday answers "is that a weekend?" without counting.
      expect(find.text('Sat, 15/08/2026'), findsOneWidget);
    });

    testWidgets('pads single-digit days and months', (tester) async {
      await pump(tester, initial: DateTime(2026, 9, 7));
      expect(find.text('Mon, 07/09/2026'), findsOneWidget);
    });

    testWidgets('an unset date prompts rather than reading as a value',
        (tester) async {
      await pump(tester);

      // "Not set" in bold looked like something had been entered.
      expect(find.text('Tap to choose a date'), findsOneWidget);
      expect(find.text('Not set'), findsNothing);
    });
  });

  group('as a form field', () {
    testWidgets('a required date is marked required', (tester) async {
      await pump(tester, isRequired: true);

      final label = tester.widget<RequiredLabel>(find.byType(RequiredLabel));
      expect(label.isRequired, isTrue);
      expect(label.label, 'Best before');
    });

    testWidgets('an optional date is a plain label', (tester) async {
      await pump(tester);

      final label = tester.widget<RequiredLabel>(find.byType(RequiredLabel));
      expect(label.isRequired, isFalse);
      expect(find.text('Best before'), findsOneWidget);
    });

    testWidgets('the rule is explained in place', (tester) async {
      await pump(tester, helperText: 'Printed on the pack.');
      expect(find.text('Printed on the pack.'), findsOneWidget);
    });

    testWidgets('an invalid date shows the reason', (tester) async {
      await pump(
        tester,
        initial: DateTime(2026, 8, 1),
        errorText: "Best before date cannot be set to today's date.",
      );
      expect(
        find.text("Best before date cannot be set to today's date."),
        findsOneWidget,
      );
    });
  });

  group('changing the date', () {
    testWidgets('tapping opens the picker', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('a set date can be cleared without opening the picker',
        (tester) async {
      await pump(tester, initial: DateTime(2026, 8, 15));
      expect(find.text('Sat, 15/08/2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear date'));
      await tester.pumpAndSettle();

      expect(value, isNull);
      expect(find.text('Tap to choose a date'), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('there is nothing to clear when no date is set',
        (tester) async {
      await pump(tester);
      expect(find.byTooltip('Clear date'), findsNothing);
    });

    testWidgets('a stored date outside the allowed window still opens',
        (tester) async {
      // A record captured elsewhere can carry a date the picker would now
      // refuse. Clamping keeps it openable instead of asserting.
      await pump(tester, initial: DateTime(2020, 1, 1));
      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('the required marker itself', () {
    testWidgets('announces "required" instead of reading the asterisk',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RequiredLabel(label: 'Batch number', isRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Batch number, required'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an optional label is announced as written', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RequiredLabel(label: 'Batch number', isRequired: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Batch number'), findsOneWidget);
      expect(find.bySemanticsLabel('Batch number, required'), findsNothing);
      semantics.dispose();
    });
  });
}
