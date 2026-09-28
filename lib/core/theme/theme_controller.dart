import 'package:flutter/material.dart';

import '../data/local_database.dart';

/// Remembers whether the inspector wants light, dark, or whatever the phone is
/// set to.
///
/// Kept with the rest of the device state rather than in a separate store, so
/// there is one place a handset's settings live. Persisted because a preference
/// that resets on every launch is not a preference.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._database) : super(ThemeMode.system);

  final LocalDatabase _database;

  static const _key = 'ui.themeMode';

  /// Reads the stored choice. Anything unrecognised — or nothing at all —
  /// means follow the phone.
  Future<void> load() async {
    final stored = await _database.readSyncState(_key);
    value = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    await _database.writeSyncState(
        _key,
        switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        });
  }

  /// What to show the inspector for the current choice.
  String get label => switch (value) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Match phone',
      };

  /// The brightness this resolves to right now, given what the phone is set
  /// to. Needed because the palette has to be in force before the widget tree
  /// is built, and `Theme.of(context)` is not available that early.
  Brightness resolve(Brightness platform) => switch (value) {
        ThemeMode.light => Brightness.light,
        ThemeMode.dark => Brightness.dark,
        ThemeMode.system => platform,
      };
}
