import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signing out must actually take the inspector back to the sign-in page.
///
/// The tap comes from the drawer, and a single `Navigator.pop()` merely closes
/// the drawer — the session was cleared but the screen never changed. That
/// reads as a dead button, and is worse than dead: the next launch quietly
/// asks for a password, because the sign-out did happen.
void main() {
  Widget app({required VoidCallback Function(BuildContext) signOut}) {
    return MaterialApp(
      home: Builder(
        builder: (loginContext) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('SIGN IN PAGE'),
                ElevatedButton(
                  onPressed: () => Navigator.of(loginContext).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        // A drawer, exactly as the home screen has.
                        drawer: Drawer(
                          child: ListTile(
                            title: const Text('Sign out'),
                            onTap: signOut(loginContext),
                          ),
                        ),
                        appBar: AppBar(title: const Text('HOME')),
                      ),
                    ),
                  ),
                  child: const Text('sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openHomeAndDrawer(WidgetTester tester) async {
    await tester.tap(find.text('sign in'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);

    // Open the drawer the way an inspector does.
    tester.state<ScaffoldState>(find.byType(Scaffold).last).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
  }

  testWidgets('popUntil returns to the sign-in page from the drawer',
      (tester) async {
    await tester.pumpWidget(
      app(
        signOut: (ctx) =>
            () => Navigator.of(ctx).popUntil((route) => route.isFirst),
      ),
    );
    await openHomeAndDrawer(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('SIGN IN PAGE'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('a single pop only closes the drawer — the old bug',
      (tester) async {
    // Pins the failure mode so nobody simplifies this back to one pop.
    await tester.pumpWidget(
      app(signOut: (ctx) => () => Navigator.of(ctx).pop()),
    );
    await openHomeAndDrawer(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget,
        reason: 'one pop closes the drawer and leaves the inspector on home');
    expect(find.text('SIGN IN PAGE'), findsNothing);
  });
}
