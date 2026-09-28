import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/data/local_database.dart';
import '../../../core/services/connectivity_service.dart';
import 'eggs_repository.dart';

/// Outcome of one sync pass.
class SyncReport {
  const SyncReport({
    required this.inspectionsSent,
    required this.directionsSent,
    required this.failures,
    this.firstError,
  });

  const SyncReport.nothingToDo()
      : inspectionsSent = 0,
        directionsSent = 0,
        failures = 0,
        firstError = null;

  final int inspectionsSent;
  final int directionsSent;

  /// Records that were tried and did not go up. They stay pending.
  final int failures;

  /// Why the first of them did not go up, as the server or the network put
  /// it — shown with the failure rather than swallowed (Ethan, 2026-09-24).
  final String? firstError;

  int get sent => inspectionsSent + directionsSent;
  bool get didAnything => sent > 0 || failures > 0;
}

/// Pushes locally-held work to the server, and keeps trying whenever the
/// device regains a network route.
///
/// Records are always written to the device first. This service is the only
/// thing that decides when they leave it, so capture never blocks on a signal
/// and nothing is lost when there isn't one.
class EggsSyncService {
  EggsSyncService({
    required this.repository,
    required this.connectivity,
  });

  final EggsRepository repository;
  final ConnectivityService connectivity;

  StreamSubscription<bool>? _subscription;

  /// Retries while the app is open, not only when the signal comes back.
  ///
  /// Watching connectivity alone misses everything that fails while already
  /// online — a token that had to be refreshed, a server restarting, a request
  /// that timed out on a weak bar of signal. Those would sit untouched until
  /// the connection dropped and returned, or the app was reopened, which is
  /// not something an inspector should have to arrange.
  Timer? _retry;

  /// How often to try again. Short enough that a record does not linger,
  /// long enough to be invisible: a pass with nothing pending is a single
  /// indexed query.
  static const retryInterval = Duration(minutes: 2);

  /// Emits after every pass that did something, so open screens can refresh
  /// and say what happened.
  final _reports = StreamController<SyncReport>.broadcast();
  Stream<SyncReport> get onSync => _reports.stream;

  /// True while a pass is running. Guards against the connectivity stream and
  /// a manual trigger overlapping and uploading the same record twice.
  bool _running = false;
  bool get isRunning => _running;

  /// Watches connectivity and syncs on every transition to online.
  ///
  /// Also runs once immediately: the app may well be started with a signal and
  /// records left over from the last outing.
  void start() {
    _subscription ??= connectivity.onStatusChanged.listen((online) {
      if (online) unawaited(syncNow());
    });
    _retry ??= Timer.periodic(retryInterval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  Future<void> dispose() async {
    // Stopped before anything is awaited: a timer left armed across the
    // teardown can fire into a service that is halfway shut down.
    _retry?.cancel();
    _retry = null;
    await _subscription?.cancel();
    _subscription = null;
    await _reports.close();
  }

  /// Uploads everything still pending. Safe to call at any time.
  ///
  /// Returns what actually happened rather than throwing: a failed upload is
  /// an expected state out in the field, not an error to surface as a crash.
  /// Anything that fails keeps its pending flag and is retried next pass.
  Future<SyncReport> syncNow() async {
    if (_running) return const SyncReport.nothingToDo();
    // Claim the pass before the first await. Checking the flag and then
    // awaiting before setting it lets two callers past the guard and uploads
    // every pending record twice.
    _running = true;

    var inspections = 0;
    var directions = 0;
    var failures = 0;

    try {
      // No token means this device has never completed an online sign-in, so
      // there is nothing to authenticate the upload with.
      final token = await repository.storedToken();
      if (token == null) return const SyncReport.nothingToDo();
      if (!await connectivity.isOnline) return const SyncReport.nothingToDo();

      // Both loops go through _trySend, so the background pass heals a stale
      // lookup table exactly as a save does. Handling rejection only on the
      // save path left everything captured earlier stuck: it retried every two
      // minutes into the same 400 and never recovered.
      for (final inspection in await repository.savedInspections()) {
        // Only finished work goes up; a draft is still being captured.
        if (inspection.status != 'completed') continue;
        if (inspection.isUploaded) {
          // The record is up, but an attachment may have failed on the pass
          // that sent it — a rejected photograph or signature would
          // otherwise sit on the handset with nothing left to carry it.
          try {
            await repository.uploadAttachments(
              inspection.clientUuid,
              token: token,
            );
          } on Object {
            // Retried on the next pass; nothing is lost by staying quiet.
          }
          continue;
        }
        final outcome = await _trySend(
          _uploadInspection(inspection.clientUuid),
          heal: () => repository.repointLookupIds(inspection.clientUuid),
        );
        if (outcome == SendOutcome.sent) {
          inspections++;
        } else {
          failures++;
        }
      }

      for (final direction in await repository.savedDirections()) {
        if (direction.isUploaded) continue;
        if (direction.status != 'completed') continue;
        final outcome = await _trySend(
          (t) => repository.uploadDirection(direction, token: t),
        );
        if (outcome == SendOutcome.sent) {
          directions++;
        } else {
          failures++;
        }
      }

      final report = SyncReport(
        inspectionsSent: inspections,
        directionsSent: directions,
        failures: failures,
        firstError: failures == 0 ? null : _lastError,
      );
      if (report.didAnything && !_reports.isClosed) _reports.add(report);
      return report;
    } finally {
      _running = false;
    }
  }

  /// Uploads a single record straight after capture, so an inspector standing
  /// in signal sees it land rather than waiting for the next pass.
  ///
  /// Returns true only when the server confirmed it. A false is not an error:
  /// the record is already on the device and the next pass will retry it.
  Future<bool> sendNow(EggInspection inspection) => _sendOne(
        _uploadInspection(inspection.clientUuid),
        heal: () => repository.repointLookupIds(inspection.clientUuid),
      );

  /// Uploads the inspection as it is stored *now*, not as it was when the
  /// caller loaded it — a heal between the first attempt and the retry
  /// changes the ids on the row, and the retry has to carry the new ones.
  Future<void> Function(String token) _uploadInspection(String uuid) =>
      (token) async {
        final current = await repository.inspectionByUuid(uuid);
        if (current == null) return;
        await repository.upload(current, token: token);
      };

  /// As [sendNow], for a direction.
  Future<bool> sendDirectionNow(EggDirection direction) => _sendOne(
        (token) => repository.uploadDirection(direction, token: token),
      );

  Future<bool> _sendOne(
    Future<void> Function(String token) upload, {
    Future<bool> Function()? heal,
  }) async {
    _lastOutcome = await _trySend(upload, heal: heal);
    return _lastOutcome == SendOutcome.sent;
  }

  /// Why the last send did or did not happen, so the inspector is told the
  /// truth rather than "it will upload automatically" in every case.
  SendOutcome _lastOutcome = SendOutcome.sent;
  SendOutcome get lastOutcome => _lastOutcome;

  RecordRejected? _lastRejection;

  /// The last reason a send failed, whatever it was.
  String? _lastError;

  SendOutcome _failedWith(Object error, SendOutcome outcome) {
    _lastError = '$error';
    debugPrint('EggsSync: upload failed — $error');
    return outcome;
  }

  /// Why the server refused the last record, when it did.
  RecordRejected? get lastRejection => _lastRejection;

  Future<SendOutcome> _trySend(
    Future<void> Function(String token) upload, {
    Future<bool> Function()? heal,
  }) async {
    if (!await connectivity.isOnline) return SendOutcome.offline;

    // Checked after connectivity: refreshing an expired token needs a network,
    // so with no signal this would report "sign in again" for what is really
    // just a tunnel.
    final token = await repository.storedToken();
    if (token == null) return SendOutcome.notAuthenticated;

    try {
      await upload(token);
      return SendOutcome.sent;
    } on RecordRejected catch (e) {
      // Almost always this device holding lookup rows from another server, or
      // the ids the rules shipped with, so the ids it sends mean nothing here.
      // Refresh the tables, re-point the record at the rows they now hold,
      // and try again rather than handing the inspector a sync problem to
      // solve in the field — they are standing at a consignment, not at a desk.
      final refreshed = await _refreshReferenceOnce();
      var healed = false;
      if (heal != null) {
        try {
          healed = await heal();
        } on Object {
          // The heal is best effort; a failure inside it must not turn a
          // plain rejection into a crash of the whole pass.
        }
      }
      if (refreshed || healed) {
        try {
          await upload(token);
          return SendOutcome.sent;
        } on RecordRejected catch (again) {
          _lastRejection = again;
          return _failedWith(again, SendOutcome.rejected);
        } on Object catch (error) {
          return _failedWith(error, SendOutcome.failed);
        }
      }
      _lastRejection = e;
      return _failedWith(e, SendOutcome.rejected);
    } on Object catch (error) {
      return _failedWith(error, SendOutcome.failed);
    }
  }

  /// Whether the reference data has already been re-fetched this session.
  ///
  /// Guards against a record that is genuinely malformed sending the app round
  /// a download loop on every retry.
  bool _refreshed = false;

  Future<bool> _refreshReferenceOnce() async {
    if (_refreshed) return false;
    _refreshed = true;
    try {
      // A full sync rebuilds the tables from what the server sends, inside
      // one transaction. Emptying them first and then failing to reach the
      // server left the handset with nothing to inspect with.
      await repository.syncReference(full: true);
      return true;
    } on Object {
      return false;
    }
  }
}

/// What happened to a send, beyond "it worked or it didn't".
enum SendOutcome {
  sent,

  /// No signal. The record waits, and the service will retry by itself.
  offline,

  /// Online, but this handset holds no usable credentials — nobody has signed
  /// in here while online, or the refresh token has lapsed. Retrying will not
  /// help, so the inspector has to be told.
  notAuthenticated,

  /// Reached the server, but something went wrong that may not recur — a
  /// dropped connection, a timeout, a restart. Worth trying again.
  failed,

  /// The server understood and refused the record. Retrying is pointless; the
  /// inspector has to be told.
  rejected,
}
