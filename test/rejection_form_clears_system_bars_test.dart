import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/presentation/egg_direction_form.dart';

/// The rejection form's save button has to clear the phone's gesture bar.
///
/// On the handset the list ended flush with the screen, so SAVE REJECTION sat
/// under the navigation bar: every tap went to Android instead of the button,
/// and the "rejection number is required" notice was hidden under it too.
void main() {
  const navBar = 96.0;
  const screen = Size(360, 800);

  late LocalDatabase db;
  late EggsRepository repository;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repository = EggsRepository(baseUrl: 'http://example.test', database: db);
  });
  tearDown(() async => db.close());

  testWidgets('SAVE REJECTION sits above the navigation bar', (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: EggDirectionForm(
          repository: repository,
          inspectorName: 'Ethan',
          clientName: 'SHOPRITE - Bridge City Mall',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to the very end, as an inspector does to reach the button.
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 20; i++) {
      await tester.drag(list, const Offset(0, -700));
      await tester.pumpAndSettle();
    }

    final save = find.text('SAVE REJECTION');
    expect(save, findsOneWidget);
    expect(
      tester.getRect(save).bottom,
      lessThanOrEqualTo(screen.height - navBar),
      reason: 'the button must not end under the gesture bar',
    );
  });
}
