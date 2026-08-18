import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tapping a tile must never throw the inspector back to the sign-in page.
///
/// The home screen closed its drawer with `Navigator.pop()` guarded by
/// `canPop()`. But a drawer is not a route, and `canPop()` is always true here
/// because home sits on top of the sign-in page — so every tile tap popped
/// home itself. A "coming soon" tile landed on sign-in, and a working one
/// opened the feature with home already gone from the stack, so backing out of
/// it landed there too.
///
/// A drawer is closed through its Scaffold. The Navigator is not involved.
class _Harness extends StatefulWidget {
  const _Harness({required this.closeWithNavigator});

  /// The old behaviour, kept so the failure mode stays pinned.
  final bool closeWithNavigator;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openFeature(BuildContext context, {required bool built}) {
    if (widget.closeWithNavigator) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } else {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
    }

    if (!built) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('not built yet')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('FEATURE'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Builder(
          builder: (loginContext) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(loginContext).push(
                  MaterialPageRoute<void>(
                    builder: (homeContext) => Scaffold(
                      key: _scaffoldKey,
                      drawer: const Drawer(child: Text('drawer')),
                      appBar: AppBar(title: const Text('HOME')),
                      body: Column(
                        children: [
                          ElevatedButton(
                            onPressed: () =>
                                _openFeature(homeContext, built: false),
                            child: const Text('Coming soon tile'),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                _openFeature(homeContext, built: true),
                            child: const Text('Eggs tile'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('sign in'),
              ),
            ),
          ),
        ),
      );
}

Future<void> signIn(WidgetTester tester) async {
  await tester.tap(find.text('sign in'));
  await tester.pumpAndSettle();
  expect(find.text('HOME'), findsOneWidget);
}

void main() {
  testWidgets('a coming-soon tile leaves you on the home screen',
      (tester) async {
    await tester.pumpWidget(const _Harness(closeWithNavigator: false));
    await signIn(tester);

    await tester.tap(find.text('Coming soon tile'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget,
        reason: 'a tile that does nothing must not sign you out');
    expect(find.text('not built yet'), findsOneWidget);
  });

  testWidgets('a working tile keeps home underneath it', (tester) async {
    await tester.pumpWidget(const _Harness(closeWithNavigator: false));
    await signIn(tester);

    await tester.tap(find.text('Eggs tile'));
    await tester.pumpAndSettle();
    expect(find.text('FEATURE'), findsOneWidget);

    // Backing out of the feature returns to home, not to sign-in.
    Navigator.of(tester.element(find.text('FEATURE'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the old navigator-pop behaviour drops you off home',
      (tester) async {
    // Pins the bug so nobody reintroduces it.
    await tester.pumpWidget(const _Harness(closeWithNavigator: true));
    await signIn(tester);

    await tester.tap(find.text('Coming soon tile'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsNothing,
        reason: 'this is exactly what was wrong');
    expect(find.text('sign in'), findsOneWidget);
  });
}
