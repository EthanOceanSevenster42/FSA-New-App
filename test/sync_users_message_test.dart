import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/config/app_config.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:fsa_app/features/auth/presentation/login_page.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

/// What "Sync users" reports afterwards.
///
/// One number, and only one: how many accounts were new to this device.
/// `syncUsers()` re-fetches every user, so a count of rows *written* is always
/// the whole organisation — which announced "Added 5 new users" on every press,
/// with no five new users anyone could point at.
///
/// The dialog used to add what the device held in total ("13 users on this
/// device can now sign in without a signal"). That is deliberately gone: it
/// answered a question nobody had asked and stated it as a guarantee about
/// offline sign-in. [_Auth] still reports a non-zero total below, so a
/// regression that puts the sentence back fails these tests rather than
/// passing them quietly.
class _Auth implements AuthService {
  _Auth({required this.delta});

  final int delta;

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async =>
      AuthResult(AuthOutcome.success, userId: username);

  @override
  Future<int> syncUsers() async => delta;

  @override
  Future<int> localUserCount() async => 12;
}

class _Online implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onStatusChanged => Stream<bool>.value(true);
}

Widget _wrap(AuthService auth) => MaterialApp(
      theme: AppTheme.build(),
      home: LoginPage(
        config: AppConfig.fromEnvironment(),
        appVersion: '1.0.1.85',
        authService: auth,
        loadHomeSummary: () async => const HomeSummary.empty(),
        openFeature: (_, __) => null,
        onSignedIn: () {},
        connectivityService: _Online(),
      ),
    );

Future<void> _tapSync(WidgetTester tester, AuthService auth) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(auth));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sync users'));
  await tester.pumpAndSettle();

  // The button first explains itself ("Application will do quick sync…") and
  // waits for acknowledgement. Dismiss that to reach the result dialog.
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// The device total never appears, whatever the outcome.
///
/// Matched on the sentence rather than the bare words "on this device": the
/// page itself carries a "First time on this device?" label, so a looser
/// matcher would pass no matter what the dialog said.
void _expectNoDeviceTotal() {
  expect(find.textContaining('can now sign in without a signal'), findsNothing);
  expect(find.textContaining('12 user'), findsNothing);
}

void main() {
  testWidgets('one new account is reported as one added', (tester) async {
    await _tapSync(tester, _Auth(delta: 1));

    expect(find.textContaining('Added 1 new user'), findsOneWidget);
    _expectNoDeviceTotal();
  });

  testWidgets('plural agreement on the number added', (tester) async {
    await _tapSync(tester, _Auth(delta: 3));

    expect(find.textContaining('Added 3 new users'), findsOneWidget);
    _expectNoDeviceTotal();
  });

  testWidgets('an up-to-date sync says so rather than inventing arrivals',
      (tester) async {
    await _tapSync(tester, _Auth(delta: 0));

    expect(find.textContaining('Already up to date'), findsOneWidget);
    // The bug this replaced: a full re-fetch reported every user as new, so
    // this dialog claimed arrivals on every single press.
    expect(find.textContaining('Added'), findsNothing);
    _expectNoDeviceTotal();
  });
}
