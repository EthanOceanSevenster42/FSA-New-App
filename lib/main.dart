import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/config/app_config.dart';
import 'core/data/local_database.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/device_service.dart';
import 'core/services/permission_service.dart';
import 'core/session/session_store.dart';
import 'core/session/session_user.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/api_auth_service.dart';
import 'features/auth/data/offline_capable_auth_service.dart';
import 'features/auth/data/user_sync_repository.dart';
import 'features/auth/domain/auth_service.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/eggs/data/eggs_repository.dart';
import 'features/eggs/data/eggs_sync_service.dart';
import 'features/eggs/presentation/eggs_menu_page.dart';
import 'features/fruitveg/data/fruitveg_repository.dart';
import 'features/fruitveg/presentation/fruitveg_menu_page.dart';
import 'features/home/domain/home_summary.dart';
import 'features/poultry/data/poultry_capture_repository.dart';
import 'features/poultry/data/poultry_repository.dart';
import 'features/poultry/presentation/poultry_menu_page.dart';

Future<void> main() async {
  // A failure during bootstrap must not leave a blank screen with nothing but
  // a minified stack in the console — inspectors in the field cannot report
  // that, and neither can a browser harness.
  try {
    await _bootstrap();
  } on Object catch (error, stack) {
    runApp(_StartupFailureApp(error: error, stack: stack));
  }
}

Future<void> _bootstrap() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // On web, Flutter renders to a canvas and only builds the accessibility tree
  // once it detects assistive technology — which it cannot always do. Forcing
  // it on gives the DOM real, addressable elements, so screen readers work
  // unconditionally (and browser-driven tests can target controls by name).
  if (kIsWeb) {
    binding.ensureSemantics();
  }

  // Portrait only: the capture forms are laid out for a phone held upright,
  // and a rotation mid-inspection would reflow a half-filled form.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Ask once, up front. Every inspection records a location, so prompting
  // mid-inspection would interrupt an inspector standing at a consignment.
  // A refusal does not block start-up.
  unawaited(PermissionService.ensureLocation());

  final packageInfo = await PackageInfo.fromPlatform();
  final config = AppConfig.fromEnvironment();

  // The database comes first: the device identifier is generated once and
  // stored there, so it must exist before DeviceService can resolve one.
  final database = LocalDatabase();
  final device = await DeviceService.init(database);
  final syncRepository = UserSyncRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );
  final fruitVeg = FruitVegRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );
  final eggs = EggsRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );
  final poultry = PoultryRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );
  final poultryCapture = PoultryCaptureRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );

  // Put the inspection rules on the device before anything can ask for them.
  // They ship inside the app, so a handset that has never had signal can still
  // capture an inspection. A no-op on every launch after the first.
  try {
    await eggs.seedRulesFromBundle();
  } on Object catch (error, stack) {
    // Not fatal: the rules can still be synced. Recorded rather than swallowed
    // so a broken asset shows up instead of looking like an empty database.
    debugPrint('Bundled egg rules could not be loaded: $error\n$stack');
  }

  // Pushes anything captured offline as soon as a route reappears, for the
  // whole life of the process — an inspector should never have to remember to
  // press Send.
  final eggsSync = EggsSyncService(
    repository: eggs,
    connectivity: ConnectivityService(),
  )..start();

  // Who was signed in when the process last ran. Android kills backgrounded
  // apps freely — opening the camera on a 2 GB handset is usually enough —
  // and without this the inspector came back to the sign-in screen partway
  // through an inspection.
  final sessionStore = SessionStore(database);
  final resumeAs = await sessionStore.restore();

  // Read before the first frame, so the app opens in the chosen theme rather
  // than flashing the other one.
  final themeController = ThemeController(database);
  await themeController.load();

  runApp(
    FsaApp(
      config: config,
      themeController: themeController,
      sessionStore: sessionStore,
      resumeAs: resumeAs,
      appVersion: '${packageInfo.version}.${packageInfo.buildNumber}',
      loadHomeSummary: () => HomeSummary.load(database),
      fruitVeg: fruitVeg,
      eggs: eggs,
      eggsSync: eggsSync,
      poultry: poultry,
      poultryCapture: poultryCapture,
      // Server-first, with a local fallback so an inspector with no signal is
      // never locked out. See OfflineCapableAuthService.
      authService: OfflineCapableAuthService(
        remote: ApiAuthService(
          baseUrl: config.apiBaseUrl,
          // The raw identifier goes to the server; only the display is masked.
          deviceId: device.deviceId,
          deviceModel: device.model,
        ),
        database: database,
        syncRepository: syncRepository,
      ),
    ),
  );
}

/// Shown when [_bootstrap] throws, instead of a blank canvas.
///
/// An inspector can read this out over the phone; a minified console stack
/// they cannot see is worth nothing to support.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The application could not start',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1D1D1D),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please report this message to the service desk.',
                  style: TextStyle(color: Color(0xFF6D6D6D)),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error\n\n$stack',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF3C3C3C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FsaApp extends StatelessWidget {
  const FsaApp({
    super.key,
    required this.config,
    required this.appVersion,
    required this.authService,
    required this.loadHomeSummary,
    required this.fruitVeg,
    required this.eggs,
    required this.eggsSync,
    required this.poultry,
    required this.poultryCapture,
    required this.sessionStore,
    required this.themeController,
    this.resumeAs,
  });

  final AppConfig config;
  final String appVersion;
  final AuthService authService;
  final Future<HomeSummary> Function() loadHomeSummary;
  final FruitVegRepository fruitVeg;
  final EggsRepository eggs;
  final EggsSyncService eggsSync;
  final PoultryRepository poultry;
  final PoultryCaptureRepository poultryCapture;
  final SessionStore sessionStore;

  /// Light, dark, or whatever the phone is set to.
  final ThemeController themeController;

  /// Set when a previous session is still valid, so the app resumes at the
  /// home screen instead of asking for credentials again.
  final SessionUser? resumeAs;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) {
        // The palette is global rather than context-based — several hundred
        // references, many without a BuildContext to hand — so it has to be
        // set before the tree below is built, or a frame is drawn with a
        // palette that does not match its ThemeData.
        final platform = MediaQuery.platformBrightnessOf(context);
        AppColors.use(themeController.resolve(platform));
        return _app(mode);
      },
    );
  }

  Widget _app(ThemeMode mode) {
    return MaterialApp(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: mode,
      home: LoginPage(
        config: config,
        appVersion: appVersion,
        authService: authService,
        loadHomeSummary: loadHomeSummary,
        connectivityService: ConnectivityService(),
        sessionStore: sessionStore,
        themeController: themeController,
        resumeAs: resumeAs,
        // Pull the whole directory while the inspector still has signal, so
        // every client and facility is on the device before they drive out.
        // Fire-and-forget: a failure here is surfaced by the module and by the
        // home screen's update prompt, not by the login screen.
        onSignedIn: () => unawaited(
          eggs.syncReference(full: true).catchError((_) => 0),
        ),
        // The home screen asks what is new and offers it; it never downloads
        // behind the inspector's back.
        checkForUpdates: () async {
          final updates = await eggs.pendingReferenceUpdates();
          return updates.hasAny ? updates.summary : null;
        },
        downloadUpdates: () => eggs.syncReference(),
        // Feature routing lives here so no feature module imports another.
        openFeature: (feature, user) => switch (feature.id) {
          1 => FruitVegMenuPage(
              repository: fruitVeg,
              inspectorName: user.userName,
            ),
          2 => EggsMenuPage(
              repository: eggs,
              user: user,
              syncService: eggsSync,
            ),
          3 => PoultryMenuPage(
              repository: poultry,
              captureRepository: poultryCapture,
              user: user,
            ),
          _ => null,
        },
      ),
    );
  }
}
