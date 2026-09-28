import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;

import 'package:drift/drift.dart' hide Column, Table;

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
import 'features/pmp/data/pmp_repository.dart';
import 'features/pmp/presentation/pmp_pages.dart';
import 'features/rawrmp/data/rawrmp_repository.dart';
import 'features/rawrmp/presentation/rawrmp_pages.dart';
import 'features/sync/server_sync.dart';
import 'features/invoicing/data/invoice_repository.dart';
import 'features/visits/data/visit_repository.dart';
import 'features/sync/auto_sync.dart';
import 'features/visits/presentation/inspection_management_pages.dart';
import 'features/visits/presentation/store_visit_pages.dart';
import 'features/poultry/data/poultry_capture_repository.dart';
import 'features/poultry/data/poultry_repository.dart';
import 'features/poultry/presentation/poultry_menu_page.dart';
import 'core/documents/fsa_form_assets_bundle.dart';

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
  installFsaFormAssets();

  // On web, Flutter renders to a canvas and only builds the accessibility tree
  // once it detects assistive technology — which it cannot always do. Forcing
  // it on gives the DOM real, addressable elements, so screen readers work
  // unconditionally (and browser-driven tests can target controls by name).
  if (kIsWeb) {
    binding.ensureSemantics();
  }

  // Both ways up: inspectors hold a tablet however suits the job, and a
  // large screen ignores an app's portrait request anyway. Rotating does not
  // lose a half-filled form — the fields keep their state — and the content
  // column re-centres itself at the width the new orientation allows.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
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
  final pmp = PmpRepository(
    baseUrl: config.apiBaseUrl,
    database: database,
  );
  final rawRmp = RawRmpRepository(
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
      // The build as it was numbered, not as Android stores it:
      // --split-per-abi adds the ABI's offset to the version code, so an
      // arm64 handset on build 2119 reported "1.0.1.4119" to the inspector
      // and to anyone they read it out to.
      appVersion: '${packageInfo.version}.'
          '${const int.fromEnvironment('BUILD_NUMBER') > 0 ? const int.fromEnvironment('BUILD_NUMBER') : packageInfo.buildNumber}',
      loadHomeSummary: () => HomeSummary.load(database),
      fruitVeg: fruitVeg,
      eggs: eggs,
      eggsSync: eggsSync,
      poultry: poultry,
      poultryCapture: poultryCapture,
      pmp: pmp,
      rawRmp: rawRmp,
      visits: VisitRepository(database, baseUrl: config.apiBaseUrl),
      database: database,
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
    required this.pmp,
    required this.rawRmp,
    required this.visits,
    required this.database,
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
  final PmpRepository pmp;
  final RawRmpRepository rawRmp;
  final VisitRepository visits;
  final LocalDatabase database;
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

  /// Finished records the server has not acknowledged yet, across every
  /// commodity — what a sync pass has to get through, so it can report
  /// "Uploading 3 of 12" instead of an unmoving "Uploading…".
  Future<int> _pendingUploadCount() async {
    var pending = 0;
    pending += (await (database.select(database.eggInspections)
              ..where((t) =>
                  t.status.equals('completed') & t.isUploaded.equals(false)))
            .get())
        .length;
    pending += (await (database.select(database.poultryInspections)
              ..where((t) =>
                  t.status.equals('completed') & t.isUploaded.equals(false)))
            .get())
        .length;
    pending += (await (database.select(database.poultryLabelInspections)
              ..where((t) =>
                  t.status.equals('completed') & t.isUploaded.equals(false)))
            .get())
        .length;
    pending += (await (database.select(database.rawRmpInspections)
              ..where((t) =>
                  t.status.equals('completed') & t.isUploaded.equals(false)))
            .get())
        .length;
    pending += (await (database.select(database.pmpInspections)
              ..where((t) =>
                  t.status.equals('completed') & t.isUploaded.equals(false)))
            .get())
        .length;
    return pending;
  }

  Widget _app(ThemeMode mode) {
    final connectivity = ConnectivityService();
    final syncRunner = ServerSyncRunner(
      authService: authService,
      eggs: eggs,
      eggsSync: eggsSync,
      poultry: poultry,
      poultryCapture: poultryCapture,
      pmp: pmp,
      rawRmp: rawRmp,
      visits: visits,
      invoices: InvoiceRepository(database, visits),
    );
    // Signed in and online means synced — nobody should have to remember a
    // button. Uploads fire on sign-in, when connectivity returns, and when
    // a grouped inspection is signed off.
    AutoSync.instance.configure(
      runner: syncRunner,
      connectivity: connectivity,
      pendingCount: _pendingUploadCount,
    );
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
        connectivityService: connectivity,
        sessionStore: sessionStore,
        themeController: themeController,
        resumeAs: resumeAs,
        onSessionActive: (user) => AutoSync.instance.start(user.userName),
        onSessionEnded: AutoSync.instance.stop,
        // Pull the whole directory while the inspector still has signal, so
        // every client and facility is on the device before they drive out.
        // Fire-and-forget: a failure here is surfaced by the module and by the
        // home screen's update prompt, not by the login screen.
        onSignedIn: () => unawaited(eggs.syncReference().catchError((_) => 0)),
        // The home screen asks what is new and offers it; it never downloads
        // behind the inspector's back.
        checkForUpdates: () async {
          final updates = await eggs.pendingReferenceUpdates();
          return updates.hasAny ? updates.summary : null;
        },
        downloadUpdates: () => eggs.syncReference(),
        submitFeedback: (kind, details) async {
          final token = await database.readSyncState(
            OfflineCapableAuthService.accessTokenKey,
          );
          if (token == null || token.isEmpty) {
            throw StateError('Sign in online before sending feedback.');
          }
          final response = await http
              .post(
                Uri.parse('${config.apiBaseUrl}/api/support-tickets/'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'kind': kind, 'details': details}),
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 201) {
            throw StateError('Server returned ${response.statusCode}.');
          }
        },
        // Server Sync is a popup, not a page: the sidebar button runs the
        // whole handshake right where the inspector is standing.
        runServerSync: (context, username) => showServerSyncDialog(
          context,
          runner: syncRunner,
          username: username,
        ),
        // Feature routing lives here so no feature module imports another.
        openFeature: (feature, user) => switch (feature.id) {
          11 => StoreVisitListPage(
              visits: visits,
              eggs: eggs,
              eggsSync: eggsSync,
              poultry: poultry,
              poultryCapture: poultryCapture,
              rawRmp: rawRmp,
              pmp: pmp,
              inspectorName: user.userName,
              canRemoveRecords: user.canRemoveRecords,
            ),
          12 => InspectionManagementPage(
              visits: visits,
              eggs: eggs,
              invoices: InvoiceRepository(database, visits),
              database: database,
            ),
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
          4 => PmpMenuPage(
              repository: pmp,
              captureRepository: poultryCapture,
              user: user,
            ),
          5 => RawRmpMenuPage(
              repository: rawRmp,
              captureRepository: poultryCapture,
              user: user,
            ),
          _ => null,
        },
      ),
    );
  }
}
