import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/session/session_user.dart';
import '../../home/domain/app_feature.dart';
import '../../home/domain/home_summary.dart';
import '../../home/presentation/home_page.dart';
import '../domain/auth_service.dart';

/// Sign-in screen.
///
/// The visual
/// design follows the Food Safety Agency brand (red #DE2F1B, teal #007890,
/// Lato) rather than the vivid purple the old app shipped.
///
/// Rebuild discipline matters here because the page carries a full-bleed
/// photograph. Transient UI state (busy, obscured, online) lives in
/// [ValueNotifier]s so a keystroke or a button press rebuilds only the widget
/// that changed — never the background. See [_Background].
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.config,
    required this.authService,
    required this.connectivityService,
    required this.appVersion,
    required this.loadHomeSummary,
    required this.openFeature,
    this.sessionStore,
    this.themeController,
    this.resumeAs,
    this.checkForUpdates,
    this.downloadUpdates,
    required this.onSignedIn,
  });

  /// Fired once a sign-in succeeds, so feature modules can warm their
  /// reference data while the inspector still has signal. Must not block the
  /// login flow — failures are the module's problem to surface, not this
  /// screen's.
  final VoidCallback onSignedIn;

  /// Supplies the home dashboard figures. Injected so the login screen has no
  /// dependency on the database.
  final Future<HomeSummary> Function() loadHomeSummary;

  /// Resolves a feature to its page, or null when not built yet.
  final Widget? Function(AppFeature, SessionUser) openFeature;

  /// Remembers who signed in, so the app does not ask again after Android
  /// kills it in the background. Optional, so the page can be tested without
  /// a database.
  final SessionStore? sessionStore;

  /// Light / dark preference, offered from the home drawer.
  final ThemeController? themeController;

  /// A session restored at startup. When present the home screen is opened
  /// immediately and the inspector never sees this page.
  final SessionUser? resumeAs;

  /// Passed straight to the home screen, which offers newly-published
  /// reference records rather than downloading them unasked.
  final Future<String?> Function()? checkForUpdates;
  final Future<int> Function()? downloadUpdates;

  final AppConfig config;
  final AuthService authService;
  final ConnectivityService connectivityService;
  final String appVersion;

  /// Passed in rather than read from `DeviceService.instance` so the page has
  /// no global dependency and can be widget-tested without platform channels.

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  final _isBusy = ValueNotifier<bool>(false);
  final _isOnline = ValueNotifier<bool>(true);
  final _obscurePassword = ValueNotifier<bool>(true);

  StreamSubscription<bool>? _connectivitySub;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    final resume = widget.resumeAs;
    if (resume != null) {
      // Straight past the sign-in screen. Deferred a frame because the
      // Navigator is not usable until the first build has run.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openHome(resume);
      });
    }
    unawaited(_watchConnectivity());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Decode the background before first paint so the page does not flash
      // the ink backdrop on a slow handset.
      unawaited(
        precacheImage(const AssetImage('assets/images/bg_meat.webp'), context),
      );
    }
  }

  Future<void> _watchConnectivity() async {
    _isOnline.value = await widget.connectivityService.isOnline;
    _connectivitySub =
        widget.connectivityService.onStatusChanged.listen((v) => _isOnline.value = v);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    _isBusy.dispose();
    _isOnline.dispose();
    _obscurePassword.dispose();
    super.dispose();
  }

  /// The original stripped *all* whitespace from both fields via
  /// `Regex.Replace(value, @"\s", "")`. Preserved so existing credentials
  /// containing stray spaces keep working.
  static String _stripWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s'), '');

  Future<void> _signIn() async {
    if (_isBusy.value) return;
    FocusScope.of(context).unfocus();
    _isBusy.value = true;

    final AuthResult result;
    try {
      result = await widget.authService.signIn(
        username: _stripWhitespace(_usernameController.text),
        password: _stripWhitespace(_passwordController.text),
      );
    } on Object {
      // Report the actual failure rather than a generic 'try again'.
      if (!mounted) return;
      _isBusy.value = false;
      await _alert('Login', 'Error!. Try again');
      return;
    }

    // Clear the busy state *before* showing any dialog. Leaving it set means
    // the spinner keeps animating underneath the modal and the button stays
    // disabled until the user dismisses it.
    if (!mounted) return;
    _isBusy.value = false;

    switch (result.outcome) {
      case AuthOutcome.success:
        if (widget.config.isTrialVersion) {
          await _alert(
            'Trial/Evaluation Version',
            'This version is not ready for Official Use. Please contact the '
                'Service Desk to arrange for the official version to be ready '
                'for download.',
          );
        }
        if (!mounted) return;
        widget.onSignedIn();
        final user = SessionUser(
          userName: result.userId ?? 'Inspector',
          roleName: result.roleName ?? 'Inspector',
        );
        // Remembered before navigating, so a process death on the very first
        // screen still leaves a session to come back to.
        await widget.sessionStore?.save(user);
        if (!mounted) return;
        await _openHome(user);
        // Returning here means the user signed out; clear the password so the
        // next person at the handset cannot simply press Sign in again.
        _passwordController.clear();
      case AuthOutcome.invalidCredentials:
        await _alert('Login', 'Login Particulars Entered is Not Correct');
      case AuthOutcome.accountSuspended:
        await _alert(
          'Login',
          'User or your Organisation account has been suspended!',
        );
      case AuthOutcome.accountInactive:
        await _alert(
          'Login',
          'User or your Organisation account is no longer valid',
        );
      case AuthOutcome.failure:
        await _alert(
          'Login',
          result.message ??
              'There is an error with this login.\n'
                  'Please contact your company representative.',
        );
    }
  }

  /// Opens the home screen, whether the inspector just signed in or the app
  /// resumed a session after Android killed it in the background.
  Future<void> _openHome(SessionUser user) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PopScope(
          // This sign-in page stays underneath the home screen for the whole
          // session, so popping home would put the inspector back on it — and
          // being shown a sign-in screen reads as having been signed out, in
          // the middle of a job, while the session is in fact still valid.
          // Back on the home screen should leave the app, as it does in every
          // other Android app; the session survives, so returning goes
          // straight back to home.
          //
          // Signing out still works: it pops directly rather than through the
          // back button, which is the deliberate act this guard is not for.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) SystemNavigator.pop();
          },
          child: HomePage(
            userName: user.userName,
            roleName: user.roleName,
            appVersion: widget.appVersion,
            themeController: widget.themeController,
            connectivity: widget.connectivityService,
            loadSummary: widget.loadHomeSummary,
            openFeature: widget.openFeature,
            checkForUpdates: widget.checkForUpdates,
            downloadUpdates: widget.downloadUpdates,
            onSignOut: () async {
              // Signing out is deliberate, so the remembered session goes with
              // it — otherwise the next launch would walk straight back in.
              await widget.sessionStore?.clear();
              if (!mounted) return;
              // Back to this page, however deep the inspector happens to be.
              //
              // A single pop is not enough: the tap comes from the drawer, and
              // that pop merely closes the drawer. The session was cleared but
              // the screen did not change, so signing out looked like a dead
              // button — while the next launch quietly asked for a password.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _syncUsers() async {
    if (_isBusy.value) return;

    await _alert(
      'Synchronise',
      'Application will do quick sync with the Server.\n'
          'Please ensure Internet Connectivity is on.',
    );
    if (!mounted) return;

    if (!_isOnline.value) {
      await _alert(
        'Synchronise Error',
        'Unable to initiate sync owing to Internet Connectivity being off.\n'
            'Please contact the service desk immediately about this problem',
      );
      return;
    }

    _isBusy.value = true;
    int? written;
    try {
      written = await widget.authService.syncUsers();
    } on Object {
      written = null;
    }

    // As above: stop the spinner before the dialog opens.
    if (!mounted) return;
    _isBusy.value = false;

    if (written == null) {
      await _alert(
        'Synchronise Error',
        'The synchronise with the server did not work.\n'
            'Please contact the company representative for further assistance',
      );
      return;
    }

    // Report what actually happened, rather than saying "Complete" even when
    // it had synced nothing, so a silently failing sync looked like a success.
    //
    // One number, and only one: how many accounts were new to this device.
    // `written` is not a count of rows written — the button re-fetches every
    // user, so rows written is always the whole organisation, and reporting
    // that as "Added 5 new users" on every press named five arrivals that did
    // not exist. A result of zero is the normal, healthy case.
    if (!mounted) return;

    await _alert(
      'Synchronise',
      written == 0
          ? 'Already up to date. No new users to download.'
          : 'User Synchronise is Complete.\n'
              'Added $written new user${written == 1 ? '' : 's'}.',
    );
  }


  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Photo background is dark at the top, so the status bar needs light icons.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.ink,
        // Keep the body at full height when the keyboard opens. Otherwise the
        // Scaffold shrinks it, the BoxFit.cover background re-lays out, and the
        // photo visibly jumps every time a field is focused. Keyboard avoidance
        // is handled by the scroll view's bottom padding instead.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // const, so this subtree is skipped entirely on parent rebuilds.
            const _Background(),
            SafeArea(
              child: _KeyboardInsetPadding(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(),
                    const SizedBox(height: 20),
                    _Footer(
                      appVersion: widget.appVersion,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The form sits on an opaque white card. The logo lives inside it rather
  /// than on the photograph — the mark is red and teal with no outline, so it
  /// loses contrast against a dark image.
  Widget _card() => RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Masthead(),
              const SizedBox(height: 22),
              Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 20),
              Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Enter your inspector credentials to continue.',
                style: TextStyle(
                  fontSize: 14.5,
                  color: AppColors.muted,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 22),
              _form(),
            ],
          ),
        ),
      );

  Widget _form() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Login Name'),
          ValueListenableBuilder<bool>(
            valueListenable: _isBusy,
            builder: (context, busy, _) => TextField(
              controller: _usernameController,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: TextStyle(fontSize: 16, color: AppColors.ink),
              decoration: const InputDecoration(
                hintText: 'Login Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              // Original: entry_LoginName.Completed => entry_Password.Focus()
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Password'),
          ValueListenableBuilder<bool>(
            valueListenable: _isBusy,
            builder: (context, busy, _) => ValueListenableBuilder<bool>(
              valueListenable: _obscurePassword,
              builder: (context, obscure, _) => TextField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                enabled: !busy,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                // Revealing the password stops the keyboard treating this as a
                // password field, and some keyboards then capitalise the first
                // letter. "password" silently became "Password", which the
                // server rejects — reported to the inspector as nothing more
                // than "credentials are incorrect".
                textCapitalization: TextCapitalization.none,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 16, color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => _obscurePassword.value = !obscure,
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.muted,
                    ),
                  ),
                ),
                // Original: entry_Password.Completed => SignedInProcedure(...)
                onSubmitted: (_) => _signIn(),
              ),
            ),
          ),
          const SizedBox(height: 28),
          ValueListenableBuilder<bool>(
            valueListenable: _isBusy,
            builder: (context, busy, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: busy ? null : _signIn,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('SIGN IN'),
                ),
                const SizedBox(height: 14),
                Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'First time on this device?',
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : _syncUsers,
                      child: const Text('Sync users'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
}

/// Full-bleed photograph plus scrim.
///
/// Deliberately `const` and isolated behind a [RepaintBoundary]: the parent
/// rebuilds on every keystroke and state change, and without this the 1456px
/// image widget would be rebuilt and repainted each time.
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    // sizeOf/devicePixelRatioOf rather than MediaQuery.of, so a keyboard
    // opening (which changes viewInsets) does not invalidate this subtree.
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // cacheWidth caps the decoded bitmap at the device's pixel width.
          // Without it the full 1456px image is decoded on every handset,
          // which is wasted memory on a 2-4GB device.
          Image.asset(
            'assets/images/bg_meat.webp',
            key: const ValueKey('login-background'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            cacheWidth: (width * dpr).round().clamp(480, 1456),
          ),
          // Scrim: enough to seat the card and keep the footer legible,
          // light enough that the photograph still reads.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Color(0x73000000),
                  Color(0xC7000000),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolling container whose bottom padding tracks the soft keyboard.
///
/// Isolated so that `viewInsets` changes rebuild only this widget rather than
/// the whole page — [MediaQuery.viewInsetsOf] scopes the dependency.
class _KeyboardInsetPadding extends StatelessWidget {
  const _KeyboardInsetPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 20, 18, 20 + bottom),
      child: child,
    );
  }
}

/// Official Food Safety Agency logo.
///
/// The mark is a transparent PNG containing only brand red and teal — no white
/// or black pixels. The organisation name is inside the logo, so it is not
/// repeated as text; "INSPECTOR" identifies the application, not the agency.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168),
          child: Image.asset(
            'assets/images/FSA_Logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            cacheWidth: 504, // 168dp at 3x; the source is 744px.
            semanticLabel: 'Food Safety Agency',
          ),
        ),
        const SizedBox(height: 14),
        Container(width: 36, height: 3, color: AppColors.brandRed),
        const SizedBox(height: 10),
        const Text(
          'INSPECTOR',
          style: TextStyle(
            color: AppColors.brandTeal,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.appVersion});

  final String appVersion;

  // The handset identifier is deliberately not shown. It is generated and
  // stored on the device and sent with each sign-in so an administrator can
  // see which handsets are in use; it is not something an inspector needs to
  // read off the screen.
  @override
  Widget build(BuildContext context) => Text(
        'Version $appVersion',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xD9FFFFFF)),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      );
}
