import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/config/app_config.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/core/session/session_user.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:fsa_app/features/auth/presentation/login_page.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

/// The back button on the home screen must not show the sign-in page.
///
/// The sign-in page is the app's first route and stays underneath the home
/// screen for the whole session, so popping home lands on it. An inspector who
/// presses back after saving an inspection is then looking at a login screen —
/// which reads as having been signed out mid-job, even though the session is
/// still perfectly valid. Back should leave the app instead, as it does
/// everywhere else on Android.
class _FakeConnectivity implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onStatusChanged => Stream<bool>.value(true);
}

class _StubAuth implements AuthService {
  @override
  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async =>
      AuthResult(AuthOutcome.success, userId: username);

  @override
  Future<int> syncUsers() async => 0;

  @override
  Future<int> localUserCount() async => 0;
}

Widget _app() => MaterialApp(
      theme: AppTheme.build(),
      home: LoginPage(
        config: AppConfig.fromEnvironment(),
        appVersion: '1.0.1.85',
        authService: _StubAuth(),
        loadHomeSummary: () async => const HomeSummary.empty(),
        openFeature: (_, __) => null,
        onSignedIn: () {},
        connectivityService: _FakeConnectivity(),
        // A session restored at start-up, so the app opens on home exactly as
        // it does for an inspector who never signed out.
        resumeAs: const SessionUser(userName: 'Ethan', roleName: 'Inspector'),
      ),
    );

/// Presses the system back button, the way the platform delivers it.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec()
        .encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a restored session opens the home screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Ethan'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('back on the home screen does not reveal the sign-in page',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _pressBack(tester);

    expect(find.text('Sign in'), findsNothing,
        reason: 'pressing back must not look like being signed out');
    expect(find.text('Welcome, Ethan'), findsOneWidget);
  });

  testWidgets('back on the home screen leaves the app instead', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _pressBack(tester);

    expect(
      platformCalls.map((c) => c.method),
      contains('SystemNavigator.pop'),
      reason: 'back on the first screen should exit, as on any Android app',
    );
  });
}
