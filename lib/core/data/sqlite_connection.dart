import 'dart:async';

import 'package:drift/drift.dart';
// The database runs in a background isolate, so a failed statement arrives
// wrapped. drift marks this library experimental; the wrapper has been
// stable for years and the alternative is matching on message text.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

/// How the handset's sqlite file is opened, and what happens when a write
/// finds it locked.
///
/// An inspector photographing a product on 2026-10-07 was told "The photo
/// could not be saved. SqliteException(5): database is locked" and lost the
/// shot. The record had already been captured; only the row naming the file
/// failed. Nothing in the app opens the database twice, so the second holder
/// of the lock is the handset itself: these devices run the camera close to
/// the memory ceiling (see `in_app_camera.dart`), and a process killed
/// mid-write leaves a journal behind for the next launch to roll back, while
/// an activity restarted under memory pressure can briefly leave two engines
/// — and so two connections — alive at once.
///
/// The database was opened with sqlite3's defaults, which answer a held lock
/// by failing the statement at once. Two changes make that survivable, and a
/// third catches what gets past them:
///
///  * **WAL.** In the default rollback journal a single reader blocks every
///    writer, which is how an ordinary INSERT ends up refused. Under
///    write-ahead logging readers and the writer do not block each other at
///    all, and a crash leaves a log any later connection can recover.
///  * **A busy timeout.** With one set, sqlite3 waits for a lock to clear
///    instead of giving up on the spot.
///  * **[RetryWhileLocked].** sqlite3 does not run its busy handler for every
///    kind of lock, so a statement that still comes back busy is tried again
///    a few times before the inspector is told anything.

/// How long sqlite3 waits for a held lock before it gives up, in
/// milliseconds. Long enough to outlast any write this app makes, short
/// enough that a genuinely stuck database does not freeze a form for a
/// minute.
const sqliteBusyTimeoutMs = 4000;

/// Prepares a freshly opened connection.
///
/// Runs inside the database's own background isolate, so it has to be a
/// top-level function: it is sent across the isolate boundary and may not
/// capture anything.
///
/// Every pragma here is best-effort. A handset whose filesystem will not take
/// write-ahead logging should still open its database and work as it did
/// before, rather than fail to start at all.
void configureFsaSqlite(CommonDatabase db) {
  // First, so the journal-mode change below can itself wait for a lock
  // rather than be refused by one.
  _pragma(db, 'PRAGMA busy_timeout = $sqliteBusyTimeoutMs');
  _pragma(db, 'PRAGMA journal_mode = WAL');
  // With WAL, NORMAL fsyncs at a checkpoint rather than at every commit. A
  // power cut can cost the last transaction — a tap on a form — but never
  // corrupts the file, and it keeps capture quick on a cheap handset.
  _pragma(db, 'PRAGMA synchronous = NORMAL');
}

void _pragma(CommonDatabase db, String statement) {
  try {
    db.execute(statement);
  } on SqliteException {
    // Not fatal: the setting is an improvement on the default, not a
    // requirement for the app to run.
  }
}

/// True when [error] is sqlite3 refusing a statement because something else
/// holds the lock — rather than any of the real faults (a constraint, a
/// missing column) that must never be retried.
///
/// Unwraps [DriftRemoteException]: the database lives in a background
/// isolate, so what reaches a form is the remote wrapper, not the
/// [SqliteException] itself.
bool isDatabaseLocked(Object error) {
  final cause = error is DriftRemoteException ? error.remoteCause : error;
  if (cause is SqliteException) {
    // SQLITE_BUSY (5) is another connection; SQLITE_LOCKED (6) is another
    // statement on this one. Both clear on their own.
    return cause.resultCode == 5 || cause.resultCode == 6;
  }
  // An exception that did not survive the isolate hop as itself still says
  // so in its message.
  final text = cause.toString().toLowerCase();
  return text.contains('database is locked') ||
      text.contains('database table is locked');
}

/// What to tell an inspector when a photograph could not be recorded.
///
/// Lives beside [isDatabaseLocked] rather than in the forms because all four
/// capture screens have to say the same thing. A lock is the one failure an
/// inspector can clear themselves — the handset is holding the store open
/// from a session that is already gone, and a full restart releases it — so
/// it is worth saying how instead of handing them a sqlite3 stack.
String photoSaveFailure(Object error) {
  if (isDatabaseLocked(error)) {
    return 'The photo could not be saved: the records store on this handset '
        'is busy. Close the app completely and open it again, then take the '
        'photo once more.';
  }
  return 'The photo could not be saved. $error';
}

/// Runs statements again when they lose a race for the database lock.
///
/// Only single statements are retried. A batch is drift's own loop over many
/// statements inside one transaction, and running it twice would apply the
/// ones that had already succeeded a second time.
class RetryWhileLocked extends QueryInterceptor {
  RetryWhileLocked({
    this.attempts = 3,
    this.pause = const Duration(milliseconds: 200),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? _sleep;

  /// How many times a statement is run in total, the first try included.
  final int attempts;

  /// The wait after the first failure. Doubles each time, so a lock held for
  /// a moment is not hammered.
  final Duration pause;

  /// Test seam: lets a test prove the retrying without spending the waits.
  final Future<void> Function(Duration) _wait;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  /// Counts how many statements had to be retried, for a test to read.
  int retries = 0;

  Future<T> _retrying<T>(Future<T> Function() run) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await run();
      } on Object catch (error) {
        if (attempt >= attempts || !isDatabaseLocked(error)) rethrow;
        retries++;
        await _wait(pause * attempt);
      }
    }
  }

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      _retrying(() => executor.ensureOpen(user));

  @override
  Future<int> runInsert(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _retrying(() => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _retrying(() => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _retrying(() => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _retrying(() => executor.runCustom(statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _retrying(() => executor.runSelect(statement, args));
}

/// The handset's database, opened the way this app needs it.
QueryExecutor fsaLocalExecutor() {
  return driftDatabase(
    name: 'fsa_local',
    native: const DriftNativeOptions(setup: configureFsaSqlite),
  ).interceptWith(RetryWhileLocked());
}
