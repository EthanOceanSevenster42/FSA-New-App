import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/widgets/missing_fields.dart';
import 'package:fsa_app/features/poultry/presentation/poultry_form_widgets.dart';

void main() {
  late MissingFields missing;
  late TextEditingController top;
  late BuildContext pageContext;

  setUp(() {
    missing = MissingFields();
    top = TextEditingController();
  });

  Widget form() => MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            pageContext = context;
            return ListView(
              children: [
                MissingFieldAnchor(
                  fields: missing,
                  id: 'top',
                  framed: false,
                  listenable: top,
                  child: poultryField(top, 'Top field', required: true),
                ),
                // Far enough that the list never builds what follows until it
                // is scrolled to.
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 80, child: Text('filler $i')),
                MissingFieldAnchor(
                  fields: missing,
                  id: 'photos',
                  child: const SizedBox(height: 120, child: Text('Photos')),
                ),
              ],
            );
          }),
        ),
      );

  testWidgets('scrolls to a field the lazy list has never built',
      (tester) async {
    await tester.pumpWidget(form());
    expect(find.text('Photos'), findsNothing);

    final done = missing.flag(pageContext, ['photos']);
    await tester.pumpAndSettle();
    await done;

    expect(find.text('Photos'), findsOneWidget);
    // Outlined, with its caption.
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('scrolls back up to a field scrolled off the top, and marks it',
      (tester) async {
    await tester.pumpWidget(form());
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('Top field'), findsNothing);

    final done = missing.flag(
      pageContext,
      ['top'],
      stillMissing: (_) => top.text.trim().isEmpty,
    );
    await tester.pumpAndSettle();
    await done;

    expect(find.textContaining('Top field'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, 'Required');

    // Answering it takes the red away without another save.
    await tester.enterText(find.byType(TextField), 'filled');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.errorText,
      isNull,
    );
  });
}
