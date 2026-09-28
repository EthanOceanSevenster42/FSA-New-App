import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/connectivity_service.dart';
import 'server_sync.dart';

/// Background synchronisation, so nobody has to remember the Server Sync
/// button: signed in and online means synced, period.
///
/// Runs the same handshake as the manual popup — users, reference data and
/// every completed record not yet on the register — but silently. It fires
/// when a session starts (sign-in or resume), whenever connectivity comes
/// back while the app is open, and the moment a grouped inspection is
/// signed off. Failures stay quiet: the record keeps waiting on the device
/// and the home screen's pending-upload count keeps saying so, exactly as
/// when there is no signal at all.
class AutoSync {
  AutoSync._();

  static final AutoSync instance = AutoSync._();

  ServerSyncRunner? _runner;
  ConnectivityService? _connectivity;
  StreamSubscription<bool>? _watch;
  String? _username;
  bool _running = false;

  /// True while a pass is in flight, so screens can say "Uploading…" rather
  /// than leaving a record looking stuck while it is in fact being sent.
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Bumped after every pass, so a screen can reload itself once the work
  /// it was watching has finished.
  final ValueNotifier<int> completedPasses = ValueNotifier<int>(0);

  /// How far the pass has got: records sent out of the number that were
  /// waiting when it started, so a screen can say "Uploading 3 of 12"
  /// rather than an unmoving "Uploading…". Null when nothing is in flight.
  final ValueNotifier<({int done, int total})?> progress =
      ValueNotifier<({int done, int total})?>(null);

  /// What went wrong on the last pass, step by step — empty when it all
  /// went through. Shown on Inspection Management so a record that will not
  /// go up says why, instead of failing quietly (Ethan, 2026-09-24).
  final ValueNotifier<List<String>> lastFailures =
      ValueNotifier<List<String>>(const []);

  /// Counts the records still waiting to reach the server, across every
  /// commodity. Supplied by the app root, which owns the database.
  Future<int> Function()? _pendingCount;

  /// Wires the machinery. Safe to call repeatedly — the app root rebuilds on
  /// theme changes — only the first call arms the connectivity watch.
  void configure({
    required ServerSyncRunner runner,
    required ConnectivityService connectivity,
    Future<int> Function()? pendingCount,
  }) {
    _runner = runner;
    _pendingCount = pendingCount ?? _pendingCount;
    _connectivity ??= connectivity;
    _watch ??= _connectivity!.onStatusChanged.listen((online) {
      if (online) unawaited(kick());
    });
  }

  /// A session began — remember whose work to push and sync right away.
  void start(String username) {
    _username = username;
    unawaited(kick());
  }

  /// The session ended; nothing further uploads until the next sign-in.
  void stop() => _username = null;

  /// Runs one silent sync if signed in, online, and not already running.
  Future<void> kick() async {
    final runner = _runner;
    final connectivity = _connectivity;
    final username = _username;
    if (runner == null || connectivity == null || username == null) {
      debugPrint('AutoSync: not ready (runner=${runner != null}, '
          'connectivity=${connectivity != null}, user=$username)');
      return;
    }
    if (_running) return;
    if (!await connectivity.isOnline) {
      debugPrint('AutoSync: offline, skipping');
      return;
    }
    debugPrint('AutoSync: pass starting for $username');
    _running = true;
    isSyncing.value = true;
    final counter = _pendingCount;
    final total = counter == null ? 0 : await counter();
    if (total > 0) progress.value = (done: 0, total: total);
    try {
      // The step list is the popup's; the callback here is what turns each
      // finished step into "sent so far". run() never throws — a failed
      // step is a reported outcome, and silently reported is what
      // background means.
      final steps = runner.freshSteps();
      await runner.run(steps, username, () {
        if (counter == null || total == 0) return;
        unawaited(counter().then((remaining) {
          if (!_running) return;
          final done = (total - remaining).clamp(0, total);
          progress.value = (done: done, total: total);
        }));
      });
      // Every step's outcome goes to the device log, so a failure can be
      // read back after the screen has moved on.
      for (final step in steps) {
        debugPrint('AutoSync: ${step.title} -> ${step.state.name}: '
            '${step.detail}');
      }
      final failures = [
        for (final step in steps)
          if (step.state == SyncStepState.failed)
            '${step.title}: ${step.detail}',
      ];
      // No server sign-in: every upload step "finishes" having sent
      // nothing. Said plainly, since it is the one thing that stops every
      // record going up and only a sign-in with a password cures it.
      final signedOut = steps.any((s) =>
          s.detail.toLowerCase().contains('sign in once with signal'));
      lastFailures.value = [
        if (signedOut)
          'Not signed in to the server. Log out and sign in again with '
              'signal — the sync then runs by itself.',
        ...failures,
      ];
    } finally {
      _running = false;
      isSyncing.value = false;
      progress.value = null;
      completedPasses.value++;
    }
  }
}
