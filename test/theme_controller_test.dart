import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/theme/app_theme.dart';
import 'package:fsa_app/core/theme/theme_controller.dart';

/// Light or dark, remembered between launches.
///
/// Inspectors work in cold rooms before dawn and in direct sun at midday;
/// neither setting suits both. A preference that resets on every launch is not
/// a preference, so it is stored with the rest of the device state.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('follows the phone until told otherwise', () async {
    final c = ThemeController(db);
    await c.load();

    expect(c.value, ThemeMode.system);
    expect(c.resolve(Brightness.dark), Brightness.dark);
    expect(c.resolve(Brightness.light), Brightness.light);
  });

  test('a choice survives a restart', () async {
    final first = ThemeController(db);
    await first.set(ThemeMode.dark);

    // A fresh controller on the same device, as after relaunching.
    final second = ThemeController(db);
    await second.load();

    expect(second.value, ThemeMode.dark);
  });

  test('an explicit choice ignores what the phone is set to', () async {
    final c = ThemeController(db);
    await c.set(ThemeMode.light);

    expect(c.resolve(Brightness.dark), Brightness.light,
        reason: 'the inspector asked for light');
  });

  test('unreadable storage falls back to following the phone', () async {
    await db.writeSyncState('ui.themeMode', 'chartreuse');
    final c = ThemeController(db);
    await c.load();

    expect(c.value, ThemeMode.system);
  });

  test('listeners are told, so the app rebuilds', () async {
    final c = ThemeController(db);
    var notified = 0;
    c.addListener(() => notified++);

    await c.set(ThemeMode.dark);
    expect(notified, 1);

    // Setting the same value again is not a change.
    await c.set(ThemeMode.dark);
    expect(notified, 1);
  });

  group('the palette actually differs', () {
    test('dark is not light', () {
      expect(AppPalette.dark.surface, isNot(AppPalette.light.surface));
      expect(AppPalette.dark.ink, isNot(AppPalette.light.ink));
      expect(AppPalette.dark.border, isNot(AppPalette.light.border));
    });

    test('the brand colours are the same in both', () {
      // A logo does not change colour when the sun goes down.
      final light = AppTheme.build(Brightness.light);
      final dark = AppTheme.build(Brightness.dark);
      expect(light.colorScheme.primary, dark.colorScheme.primary);
    });

    test('building a theme does not disturb the palette in force', () {
      // The bug this pins: AppTheme.build used to set the global palette as a
      // side effect. The app root builds BOTH themes on every frame — light
      // first, then dark — so the dark call always won and choosing Light left
      // every surface dark. Only whoever holds the resolved brightness may set
      // the palette.
      AppColors.use(Brightness.light);

      AppTheme.build(Brightness.dark);
      AppTheme.build(Brightness.light);

      expect(AppColors.surface, AppPalette.light.surface,
          reason: 'building a dark theme must not make the app dark');
      expect(AppColors.ink, AppPalette.light.ink);
    });

    test('the palette follows what was explicitly asked for', () {
      AppColors.use(Brightness.dark);
      expect(AppColors.surface, AppPalette.dark.surface);

      AppColors.use(Brightness.light);
      expect(AppColors.surface, AppPalette.light.surface);
    });

    test('each theme describes its own brightness', () {
      expect(AppTheme.build(Brightness.dark).brightness, Brightness.dark);
      expect(AppTheme.build(Brightness.light).brightness, Brightness.light);
    });

    test('dark text is legible on dark surfaces', () {
      // Not a full contrast audit — just that they are not near-identical,
      // which is the mistake that makes a "dark mode" unreadable.
      double luminance(Color c) => c.computeLuminance();
      expect(
        (luminance(AppPalette.dark.ink) - luminance(AppPalette.dark.surface))
            .abs(),
        greaterThan(0.5),
      );
      expect(
        (luminance(AppPalette.light.ink) - luminance(AppPalette.light.surface))
            .abs(),
        greaterThan(0.5),
      );
    });
  });
}
