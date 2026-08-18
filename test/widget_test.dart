import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/config/app_config.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/core/services/device_service.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:fsa_app/features/auth/presentation/login_page.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity({this.online = true});

  final bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onStatusChanged => Stream<bool>.value(online);
}

/// Records what the page passed down, so we can assert on whitespace stripping.
class _RecordingAuthService implements AuthService {
  String? username;
  String? password;
  AuthOutcome outcome = AuthOutcome.success;
  int syncCalls = 0;

  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    this.username = username;
    this.password = password;
    return AuthResult(outcome, userId: username);
  }

  @override
  Future<int> syncUsers() async {
    syncCalls++;
    return 3;
  }

  @override
  Future<int> localUserCount() async => 3;
}

/// Reference viewport: 360x800dp — the small-phone baseline the field devices
/// sit on (Samsung A06, Redmi 9C). Testing at 800x600 hid the sign-in button
/// below the fold and silently dropped taps.
void _useSmallPhoneViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Widget _wrap({
  required AuthService auth,
  ConnectivityService? connectivity,
}) =>
    MaterialApp(
      // Use the real theme: button sizing, fonts and colours all live there,
      // so a bare MaterialApp would test a different widget than ships.
      theme: AppTheme.build(),
      home: LoginPage(
        config: AppConfig.fromEnvironment(),
        appVersion: '1.0.1.85',
        authService: auth,
        loadHomeSummary: () async => const HomeSummary.empty(),
        openFeature: (_, __) => null,
        onSignedIn: () {},
        connectivityService: connectivity ?? _FakeConnectivity(),
      ),
    );

Future<void> _signIn(
  WidgetTester tester, {
  required String username,
  required String password,
}) async {
  await tester.enterText(find.byType(TextField).first, username);
  await tester.enterText(find.byType(TextField).last, password);
  // The heading reads "Sign in"; the button reads "SIGN IN".
  await tester.ensureVisible(find.text('SIGN IN'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('SIGN IN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders branding, both fields and both actions', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(auth: _RecordingAuthService()));
    await tester.pumpAndSettle();

    // The agency name lives inside the logo, so it is not repeated as text.
    expect(find.bySemanticsLabel('Food Safety Agency'), findsOneWidget);
    expect(find.text('INSPECTOR'), findsOneWidget);
    expect(find.text('Login Name'), findsWidgets);
    expect(find.text('Password'), findsWidgets);
    expect(find.text('Sign in'), findsOneWidget); // heading
    expect(find.text('SIGN IN'), findsOneWidget); // button
    expect(find.text('Sync users'), findsOneWidget);
    // The handset identifier is kept on the device and sent with each
    // sign-in, but is never put on screen for the inspector to read.
    expect(find.textContaining('Device ID'), findsNothing);
    expect(find.textContaining('Version 1.0.1.85'), findsOneWidget);
  });

  testWidgets('primary action meets the 56dp touch target for gloved use',
      (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(auth: _RecordingAuthService()));
    await tester.pumpAndSettle();

    final button = tester.getSize(find.byType(ElevatedButton));
    expect(button.height, greaterThanOrEqualTo(56.0));
  });

  testWidgets('strips whitespace from credentials',
      (tester) async {
    _useSmallPhoneViewport(tester);
    final auth = _RecordingAuthService();
    await tester.pumpWidget(_wrap(auth: auth));
    await tester.pumpAndSettle();

    await _signIn(tester, username: '  john smith ', password: ' pa ss ');

    expect(auth.username, 'johnsmith');
    expect(auth.password, 'pass');
  });

  testWidgets('says nothing about connectivity when offline', (tester) async {
    // Working without signal is the normal state for a field inspector and
    // sign-in works either way, so the screen does not comment on it. A notice
    // here reads as a problem the inspector has to deal with before they can
    // start, which it is not.
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(
      auth: _RecordingAuthService(),
      connectivity: _FakeConnectivity(online: false),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No internet connection'), findsNothing);
    expect(find.textContaining('work offline'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
  });

  testWidgets('signing in still works with no route', (tester) async {
    _useSmallPhoneViewport(tester);
    final auth = _RecordingAuthService();
    await tester.pumpWidget(_wrap(
      auth: auth,
      connectivity: _FakeConnectivity(online: false),
    ));
    await tester.pumpAndSettle();

    await _signIn(tester, username: 'user', password: 'pw');

    // Removing the notice must not have gated sign-in behind connectivity.
    expect(auth.username, 'user');
  });

  testWidgets('surfaces the suspended-account message', (tester) async {
    // An earlier design could never reach this branch: its guard conditions
    // were inverted, so suspended users fell through to the generic error.
    _useSmallPhoneViewport(tester);
    final auth = _RecordingAuthService()
      ..outcome = AuthOutcome.accountSuspended;

    await tester.pumpWidget(_wrap(auth: auth));
    await tester.pumpAndSettle();

    await _signIn(tester, username: 'user', password: 'pw');

    expect(
      find.text('User or your Organisation account has been suspended!'),
      findsOneWidget,
    );
  });

  testWidgets('password is obscured until the eye toggle is tapped',
      (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(auth: _RecordingAuthService()));
    await tester.pumpAndSettle();

    TextField passwordField() =>
        tester.widgetList<TextField>(find.byType(TextField)).last;

    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('background image does not move when the keyboard opens',
      (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(auth: _RecordingAuthService()));
    await tester.pumpAndSettle();

    Rect backgroundRect() {
      final image = find.byKey(const ValueKey('login-background'));
      expect(image, findsOneWidget);
      return tester.getRect(image);
    }

    final before = backgroundRect();

    // Simulate the soft keyboard claiming the bottom of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    // Scaffold.resizeToAvoidBottomInset is false, so the photo must be
    // untouched — a changed rect is the visible "jump" users reported.
    expect(backgroundRect(), before);
  });

  test('device id masking is length-safe', () {
    // A fixed-offset substring would throw on short identifiers.
    expect(DeviceService.maskIdentifier('short'), 'short');
    expect(DeviceService.maskIdentifier('ABCDEFGH1234'), 'ABCDEFGHXXXX');
    expect(DeviceService.maskIdentifier(''), '');
  });
}
