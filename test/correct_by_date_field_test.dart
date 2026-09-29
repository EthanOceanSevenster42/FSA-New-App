import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/widgets/correct_by_date_field.dart';

void main() {
  final today = DateUtils.dateOnly(DateTime.now());

  test('only a day after today counts as a future correction date', () {
    expect(CorrectByDateField.isFuture(null), isFalse);
    expect(CorrectByDateField.isFuture(today), isFalse);
    expect(
        CorrectByDateField.isFuture(today.subtract(const Duration(days: 1))),
        isFalse);
    expect(CorrectByDateField.isFuture(today.add(const Duration(days: 1))),
        isTrue);
  });

  Future<List<DateTime?>> pump(WidgetTester tester, DateTime? sop) async {
    final changes = <DateTime?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CorrectByDateField(
          value: sop,
          sopDate: sop,
          onChanged: changes.add,
        ),
      ),
    ));
    return changes;
  }

  bool locked(WidgetTester tester) => tester
      .widgetList<IgnorePointer>(find.ancestor(
          of: find.textContaining('Correct by/on Date'),
          matching: find.byType(IgnorePointer)))
      .any((w) => w.ignoring);

  testWidgets('an immediate correction is shown but cannot be moved',
      (tester) async {
    await pump(tester, today);
    expect(locked(tester), isTrue);
  });

  testWidgets('a period can be moved, and clearing puts the annexure back',
      (tester) async {
    final sop = today.add(const Duration(days: 30));
    final changes = await pump(tester, sop);
    expect(locked(tester), isFalse);

    await tester.tap(find.byTooltip('Clear date'));
    expect(changes, [sop]);
  });
}
