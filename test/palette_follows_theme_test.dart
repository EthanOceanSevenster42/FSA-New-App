import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';

/// A heading built with `const` reads its colour once. When the handset went
/// from dark mode to light at sunrise, "AT A GLANCE" and "START AN INSPECTION"
/// on the home page kept the dark theme's near-white ink on a white page and
/// could not be read. Colours read through the theme follow the switch.
class _ConstHeading extends StatelessWidget {
  const _ConstHeading();

  @override
  Widget build(BuildContext context) => Text(
        'AT A GLANCE',
        style: TextStyle(color: AppColors.of(context).ink),
      );
}

void main() {
  Widget app(Brightness b) {
    AppColors.use(b);
    return MaterialApp(
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: const Scaffold(body: _ConstHeading()),
    );
  }

  Color inkOf(WidgetTester tester) =>
      tester.widget<Text>(find.text('AT A GLANCE')).style!.color!;

  testWidgets('a const heading follows the theme from dark back to light',
      (tester) async {
    await tester.pumpWidget(app(Brightness.dark));
    await tester.pumpAndSettle();
    expect(inkOf(tester), AppPalette.dark.ink);

    // Sunrise: the system switches to light. The heading is the same const
    // instance, so only a theme dependency can bring it back.
    await tester.pumpWidget(app(Brightness.light));
    await tester.pumpAndSettle();
    expect(inkOf(tester), AppPalette.light.ink,
        reason: 'the heading must not keep the dark palette on a light page');
  });

  testWidgets('the theme carries the palette it was built from', (tester) async {
    expect(AppTheme.build(Brightness.light).extension<AppPalette>(),
        same(AppPalette.light));
    expect(AppTheme.build(Brightness.dark).extension<AppPalette>(),
        same(AppPalette.dark));
  });

  testWidgets('outside any theme the palette in force is used', (tester) async {
    AppColors.use(Brightness.dark);
    late AppPalette seen;
    await tester.pumpWidget(Builder(builder: (context) {
      seen = AppColors.of(context);
      return const SizedBox();
    }));
    expect(seen, same(AppPalette.dark));
    AppColors.use(Brightness.light);
  });
}
