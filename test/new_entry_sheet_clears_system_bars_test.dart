import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/eggs/presentation/new_directory_entry_sheet.dart';

/// The "add new" sheet has to clear the phone's own furniture.
///
/// On a gesture-navigation handset the sheet used to end flush with the bottom
/// of the screen, which put Cancel underneath the navigation bar — visible but
/// only half tappable.
void main() {
  const navBar = 96.0;
  const screen = Size(360, 800);

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    // What a gesture bar looks like to Flutter: viewPadding, not viewInsets.
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showNewDirectoryEntrySheet(
                  context,
                  title: 'New premises',
                  subtitle: 'Registered on the server.',
                  saveLabel: 'Add premises',
                  fields: [
                    const DirectoryField(
                      label: 'Name',
                      key: 'name',
                      initial: 'MOC Test Depot',
                      isRequired: true,
                    ),
                    const DirectoryField(label: 'Telephone', key: 'telephone'),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Cancel sits above the navigation bar, not behind it',
      (tester) async {
    await openSheet(tester);

    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancel.bottom, lessThanOrEqualTo(screen.height - navBar));
  });

  testWidgets('so does the save button', (tester) async {
    await openSheet(tester);

    final save = tester.getRect(
      find.widgetWithText(ElevatedButton, 'Add premises'),
    );
    expect(save.bottom, lessThanOrEqualTo(screen.height - navBar));
  });
}
