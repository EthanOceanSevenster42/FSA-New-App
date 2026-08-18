import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/services/connectivity_service.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/features/home/domain/app_feature.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';
import 'package:fsa_app/features/home/presentation/home_page.dart';

/// 360x800dp — the small-phone baseline the field devices sit on.
void _useSmallPhoneViewport(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

class _FakeConnectivity implements ConnectivityService {
  _FakeConnectivity({this.online = true});

  final bool online;

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onStatusChanged => Stream<bool>.value(online);
}

Widget _wrap({
  String role = 'Inspector',
  bool offline = false,
  HomeSummary? summary,
}) =>
    MaterialApp(
      theme: AppTheme.build(),
      home: HomePage(
        userName: 'Ethan',
        roleName: role,
        appVersion: '1.0.1.85',
        connectivity: _FakeConnectivity(online: !offline),
        loadSummary: () async => summary ?? const HomeSummary.empty(),
        openFeature: (_, __) => null,
        onSignOut: () {},
      ),
    );

void main() {
  testWidgets('lays out without overflow on a 360dp screen', (tester) async {
    // The first version of this grid overflowed by 7px here, which would have
    // shipped as visible clipping on an entry-level handset.
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the commodities currently in scope', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    for (final title in [
      'Eggs',
      'Poultry Products',
      'Processed Meat',
      'Raw Processed Meat',
      'SAPA',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '$title missing');
    }
  });

  testWidgets('Fruit & Vegetables is deliberately not offered', (tester) async {
    // Parked while Eggs is the focus. Its code and backend remain; this test
    // exists so re-adding it is a conscious change rather than an accident.
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Fruit & Vegetables'), findsNothing);
  });

  testWidgets('greets the user and shows their role', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Ethan'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
  });

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pumpAndSettle();
  }

  testWidgets('Admin Tools is hidden from a plain inspector', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await openDrawer(tester);

    expect(find.text('Admin Tools'), findsNothing);
  });

  testWidgets('Admin Tools appears for an administrator', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(role: 'System Administrator'));
    await tester.pumpAndSettle();
    await openDrawer(tester);

    expect(find.text('Admin Tools'), findsOneWidget);
  });

  testWidgets('drawer carries every destination', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(role: 'System Administrator'));
    await tester.pumpAndSettle();
    await openDrawer(tester);

    for (final f in kAppFeatures) {
      expect(
        find.text(f.title),
        findsWidgets,
        reason: '${f.title} missing from the drawer',
      );
    }
  });

  testWidgets('reports real offline-user count and never-synced state',
      (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(
      summary: const HomeSummary(offlineUsers: 5, lastSyncAt: null),
    ));
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('a quiet day shows zero, not a dash', (tester) async {
    // These used to render "—" with the hint "Not yet recorded", from when
    // capture did not exist. It does now, so an inspector who has genuinely
    // done none today must see 0 — a dash reads as the app not working.
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('—'), findsNothing);
    expect(find.text('captured today'), findsOneWidget);
    expect(find.text('everything is sent'), findsOneWidget);
  });

  // Separate tests, not one with two pumps: Flutter reuses State across
  // pumpWidget calls of the same widget type, so initState (which subscribes
  // to connectivity) would not run a second time.
  testWidgets('chip says Offline when there is no route', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap(offline: true));
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('chip says Online when a route exists', (tester) async {
    _useSmallPhoneViewport(tester);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
  });

  test('feature ids are unique', () {
    // main.dart routes on these ids, so a duplicate would silently send two
    // menu entries to the same screen.
    final ids = kAppFeatures.map((f) => f.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'duplicate feature id');
  });

  test('only the finished commodities are offered', () {
    // Enabling a feature before its screens exist sends an inspector to a dead
    // end, so this list is updated deliberately as each one lands.
    final built = kAppFeatures.where((f) => f.available).map((f) => f.title);
    expect(built, ['Eggs', 'Poultry Products']);
  });
}
