import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_store.dart';
import 'package:fsa_app/core/session/session_user.dart';

/// Staying signed in across a restart.
///
/// Android kills backgrounded apps to reclaim memory, and opening the camera
/// on a 2 GB handset is usually enough to trigger it. Without a remembered
/// session that put the inspector back at sign-in, mid-inspection, possibly
/// with no signal to sign back in.
void main() {
  late LocalDatabase db;
  late SessionStore store;

  const ethan = SessionUser(userName: 'Ethan', roleName: 'Inspector');

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    store = SessionStore(db);
  });

  tearDown(() async => db.close());

  test('a fresh device has no session', () async {
    expect(await store.restore(), isNull);
  });

  test('a saved session comes back after a restart', () async {
    await store.save(ethan);

    // A new store over the same database is what the next launch sees.
    final restored = await SessionStore(db).restore();

    expect(restored, isNotNull);
    expect(restored!.userName, 'Ethan');
    expect(restored.roleName, 'Inspector');
  });

  test('the role is kept, so admin tools do not vanish on restart', () async {
    const admin =
        SessionUser(userName: 'Ethan', roleName: 'System Administrator');
    await store.save(admin);

    final restored = await store.restore();

    expect(restored!.isSystemAdministrator, isTrue);
  });

  test('signing out is remembered too', () async {
    await store.save(ethan);
    await store.clear();

    // Otherwise the next launch would walk straight back in as the person who
    // deliberately signed out.
    expect(await store.restore(), isNull);
  });

  group('ageing out', () {
    test('a session within the window is restored', () async {
      final now = DateTime.now().toUtc();
      await store.save(ethan, now: now.subtract(const Duration(days: 6)));

      expect(await store.restore(now: now), isNotNull);
    });

    test('a session past the window is not', () async {
      final now = DateTime.now().toUtc();
      await store.save(
        ethan,
        now: now.subtract(SessionStore.maxAge + const Duration(hours: 1)),
      );

      expect(await store.restore(now: now), isNull);
    });

    test('the window covers a multi-day trip out of signal', () async {
      // Short enough that a mislaid handset is not open indefinitely, long
      // enough that an inspector in the field is not locked out.
      expect(SessionStore.maxAge.inDays, greaterThanOrEqualTo(3));
      expect(SessionStore.maxAge.inDays, lessThanOrEqualTo(30));
    });
  });

  test('a record with no timestamp is treated as no session', () async {
    // Malformed rather than eternal: a missing stamp must not mean a session
    // that never expires.
    await db.writeSyncState('session.userName', 'Ethan');
    await db.writeSyncState('session.roleName', 'Inspector');
    await db.writeSyncState('session.signedInAt', '');

    expect(await store.restore(), isNull);
  });

  test('saving again refreshes the clock', () async {
    final now = DateTime.now().toUtc();
    await store.save(ethan, now: now.subtract(const Duration(days: 6)));
    await store.save(ethan, now: now);

    expect(
      await store.restore(now: now.add(const Duration(days: 6))),
      isNotNull,
    );
  });
}
