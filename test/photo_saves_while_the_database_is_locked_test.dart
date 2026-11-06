import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// The database runs in a background isolate, so a failed statement arrives
// wrapped. drift marks this library experimental; the wrapper has been
// stable for years and the alternative is matching on message text.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/data/sqlite_connection.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// An inspector photographing a product was told "The photo could not be
/// saved. SqliteException(5): database is locked" and lost the shot
/// (Ethan, 2026-10-07). The photograph itself was taken and stored; only the
/// row naming the file was refused, because something else held the lock and
/// sqlite3's defaults answer that by failing the statement on the spot.
///
/// These tests hold the lock on purpose — a second connection with a read
/// transaction open, which is all it takes under the default rollback
/// journal — and check that a photograph is still recorded.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('fsa_lock_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps a handle for a moment after close; the temp folder is
      // the system's to reclaim.
    }
  });

  /// Creates the schema on a fresh file and closes it again, so the lock
  /// tests start from a database that already exists.
  Future<File> seeded({bool asTheAppOpensIt = false}) async {
    final file = File('${dir.path}/fsa_local.sqlite');
    final db = LocalDatabase(
      NativeDatabase(file, setup: asTheAppOpensIt ? configureFsaSqlite : null),
    );
    // Any statement opens the database and runs the migration.
    await db.customSelect('SELECT 1').get();
    await db.close();
    return file;
  }

  /// A second connection sitting on an open read transaction, as a
  /// connection left behind by a killed process or a restarted activity
  /// would be.
  raw.Database holdTheLock(File file) {
    final other = raw.sqlite3.open(file.path);
    other.execute('BEGIN');
    other.select('SELECT count(*) FROM poultry_photos');
    return other;
  }

  PoultryPhotosCompanion aPhoto() => PoultryPhotosCompanion.insert(
        recordUuid: 'f2158948-790e-461f-a996-9dc51abcc8e9',
        kind: 'pmp',
        filePath: '/data/user/0/za.co.eclick.fsa_app/app_flutter/'
            'inspection_photos/poultry_pmp_1791355542545.jpg',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(1791355542545),
      );

  test('the bug: sqlite3 defaults refuse the insert the moment a lock is held',
      () async {
    final file = await seeded();
    final other = holdTheLock(file);
    final db = LocalDatabase(NativeDatabase(file));

    await expectLater(
      db.into(db.poultryPhotos).insert(aPhoto()),
      throwsA(isA<raw.SqliteException>()
          .having((e) => e.resultCode, 'resultCode', 5)),
    );

    other.dispose();
    await db.close();
  });

  test('opened the way the app opens it, the photograph is recorded anyway',
      () async {
    final file = await seeded(asTheAppOpensIt: true);
    final other = holdTheLock(file);
    final db = LocalDatabase(NativeDatabase(file, setup: configureFsaSqlite));

    await db.into(db.poultryPhotos).insert(aPhoto());
    final saved = await db.select(db.poultryPhotos).get();
    expect(saved, hasLength(1));
    expect(saved.single.kind, 'pmp');

    other.dispose();
    await db.close();
  });

  test('write-ahead logging and a busy timeout are what make that work',
      () async {
    final file = await seeded(asTheAppOpensIt: true);
    final db = LocalDatabase(NativeDatabase(file, setup: configureFsaSqlite));

    final journal = await db.customSelect('PRAGMA journal_mode').getSingle();
    expect(journal.data.values.single, 'wal');
    final timeout = await db.customSelect('PRAGMA busy_timeout').getSingle();
    expect(timeout.data.values.single, sqliteBusyTimeoutMs);

    await db.close();
  });

  test(
      'the error a form actually sees is the remote wrapper, and it is '
      'recognised as a lock', () async {
    // The database runs in a background isolate on the handset, so what
    // reaches the capture screen is a DriftRemoteException around the
    // SqliteException — the shape isDatabaseLocked has to see through.
    final file = await seeded();
    final other = holdTheLock(file);
    final db = LocalDatabase(NativeDatabase.createBackgroundConnection(file));

    Object? caught;
    try {
      await db.into(db.poultryPhotos).insert(aPhoto());
    } on Object catch (error) {
      caught = error;
    }

    expect(caught, isA<DriftRemoteException>());
    expect(caught.toString(), contains('database is locked'));
    expect(isDatabaseLocked(caught!), isTrue);

    other.dispose();
    await db.close();
  });

  group('retrying a statement that lost the race', () {
    test('a lock that clears costs a wait, not the photograph', () async {
      final retry = RetryWhileLocked(wait: (_) async {});
      final db = LocalDatabase(
        NativeDatabase.memory()
            .interceptWith(_LockedUntil(2))
            .interceptWith(retry),
      );

      await db.into(db.poultryPhotos).insert(aPhoto());

      expect(await db.select(db.poultryPhotos).get(), hasLength(1));
      expect(retry.retries, 2);
      await db.close();
    });

    test('a real fault is reported at once, not tried again', () async {
      final retry = RetryWhileLocked(wait: (_) async {});
      final db = LocalDatabase(NativeDatabase.memory().interceptWith(retry));

      await expectLater(
        db.customStatement('INSERT INTO poultry_photos (nonsense) VALUES (1)'),
        throwsA(isA<raw.SqliteException>()),
      );
      expect(retry.retries, 0);
      await db.close();
    });

    test('a database that stays locked still gives up', () async {
      final retry = RetryWhileLocked(attempts: 3, wait: (_) async {});
      final db = LocalDatabase(
        NativeDatabase.memory()
            .interceptWith(_LockedUntil(99))
            .interceptWith(retry),
      );

      await expectLater(
        db.into(db.poultryPhotos).insert(aPhoto()),
        throwsA(isA<raw.SqliteException>()),
      );
      // Three runs in all: the first and two retries.
      expect(retry.retries, 2);
      await db.close();
    });
  });

  test('a lock is told apart from every other failure', () {
    expect(
        isDatabaseLocked(raw.SqliteException(5, 'database is locked')), isTrue);
    expect(isDatabaseLocked(raw.SqliteException(6, 'database table is locked')),
        isTrue);
    expect(isDatabaseLocked(raw.SqliteException(19, 'UNIQUE constraint failed')),
        isFalse);
    expect(isDatabaseLocked(raw.SqliteException(1, 'no such column: nonsense')),
        isFalse);
    expect(isDatabaseLocked(StateError('database is closed')), isFalse);
  });

  test('what the inspector is told names the one thing they can do', () {
    // Not a sqlite3 stack: a lock is the one failure an inspector can clear
    // themselves, so the message says how.
    final locked = photoSaveFailure(raw.SqliteException(5, 'database is locked'));
    expect(locked, contains('Close the app completely'));
    expect(locked, isNot(contains('SqliteException')));

    final other = photoSaveFailure(raw.SqliteException(19, 'UNIQUE failed'));
    expect(other, startsWith('The photo could not be saved.'));
    expect(other, contains('UNIQUE failed'));
  });
}

/// Refuses the first [failures] inserts with the error a held lock gives.
class _LockedUntil extends QueryInterceptor {
  _LockedUntil(this.failures);

  final int failures;
  int _seen = 0;

  @override
  Future<int> runInsert(
      QueryExecutor executor, String statement, List<Object?> args) {
    if (_seen++ < failures) {
      throw raw.SqliteException(5, 'database is locked', null, statement);
    }
    return executor.runInsert(statement, args);
  }
}
