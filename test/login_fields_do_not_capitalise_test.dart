import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/config/app_config.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/auth/domain/auth_service.dart';
import 'package:fsa_app/features/auth/presentation/login_page.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

/// The keyboard must not edit what an inspector typed.
///
/// A password field is left alone by the keyboard while it is obscured — but
/// the eye toggle turns obscuring off, and some Android keyboards then
/// capitalise the first letter. "password" went to the server as "Password",
/// which is a different password, and the only thing the inspector saw was
/// "credentials are incorrect". It cost a working account during testing.
class _Auth implements AuthService {
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

class _Online implements ConnectivityService {
  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onStatusChanged => Stream<bool>.value(true);
}

void main() {
  Future<List<TextField>> fields(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: LoginPage(
          config: AppConfig.fromEnvironment(),
          appVersion: '1.0.1.86',
          authService: _Auth(),
          loadHomeSummary: () async => const HomeSummary.empty(),
          openFeature: (_, __) => null,
          onSignedIn: () {},
          connectivityService: _Online(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widgetList<TextField>(find.byType(TextField)).toList();
  }

  testWidgets('neither credential field lets the keyboard capitalise',
      (tester) async {
    for (final field in await fields(tester)) {
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    }
  });

  testWidgets('the password stays uncapitalised once revealed', (tester) async {
    await fields(tester);

    // Reveal it — this is the state in which the keyboard stops treating the
    // field as a password and starts "helping". While obscured the icon offers
    // to show it; the icon shown is the inverse of the current state.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    final password = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.obscureText == false && f.focusNode != null);
    expect(password.textCapitalization, TextCapitalization.none);
  });
}
