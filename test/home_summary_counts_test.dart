import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/session/session_store.dart';
import 'package:fsa_app/features/home/domain/home_summary.dart';

/// "At a glance" has to be a count, including zero.
///
/// Both figures were left null and drawn as "—" with the hint "Not yet
/// recorded", from when capture did not exist. It does now, so an inspector
/// who has genuinely done none today should see 0 — a dash reads as the app
/// not working, and one who has three should see three.
void main() {
  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    // The dashboard reports the signed-in inspector's own work, so these
    // figures only exist in the context of a session.
    await db.writeSyncState(SessionStore.userKey, 'inspector1');
  });
  tearDown(() async => db.close());

  Future<void> inspection({
    required String uuid,
    required DateTime at,
    String status = 'completed',
    bool uploaded = false,
  }) async {
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            inspectedAt: at,
            updatedAt: at,
            status: Value(status),
            isUploaded: Value(uploaded),
          ),
        );
  }

  Future<void> direction({
    required String uuid,
    bool uploaded = false,
    String status = 'completed',
  }) async {
    final at = DateTime.now();
    await db.into(db.eggDirections).insert(
          EggDirectionsCompanion.insert(
            inspectorUsername: const Value('inspector1'),
            clientUuid: uuid,
            issuedAt: at,
            updatedAt: at,
            status: Value(status),
            isUploaded: Value(uploaded),
          ),
        );
  }

  test('a quiet day reads zero, not a dash', () async {
    final s = await HomeSummary.load(db);
    expect(s.inspectionsToday, 0);
    expect(s.pendingUpload, 0);
  });

  test("today's completed inspections are counted", () async {
    final now = DateTime.now();
    await inspection(uuid: 'a', at: now, uploaded: true);
    await inspection(uuid: 'b', at: now, uploaded: true);

    expect((await HomeSummary.load(db)).inspectionsToday, 2);
  });

  test('yesterday does not count towards today', () async {
    final now = DateTime.now();
    await inspection(uuid: 'old', at: now.subtract(const Duration(days: 1)));
    await inspection(uuid: 'new', at: now);

    expect((await HomeSummary.load(db)).inspectionsToday, 1);
  });

  test('a draft is not an inspection done', () async {
    await inspection(uuid: 'half', at: DateTime.now(), status: 'draft');

    expect((await HomeSummary.load(db)).inspectionsToday, 0);
  });

  group('pending upload', () {
    test('counts inspections and directions still on the device', () async {
      await inspection(uuid: 'a', at: DateTime.now());
      await direction(uuid: 'd1');
      await direction(uuid: 'd2', uploaded: true);

      expect((await HomeSummary.load(db)).pendingUpload, 2);
    });

    test('nothing pending once everything is up', () async {
      await inspection(uuid: 'a', at: DateTime.now(), uploaded: true);
      await direction(uuid: 'd1', uploaded: true);

      expect((await HomeSummary.load(db)).pendingUpload, 0);
    });

    test('a record stuck from yesterday still counts', () async {
      // It was not captured today, but it still needs sending — the tile is
      // about the outbox, not about today.
      await inspection(
        uuid: 'stuck',
        at: DateTime.now().subtract(const Duration(days: 3)),
      );

      final s = await HomeSummary.load(db);
      expect(s.inspectionsToday, 0);
      expect(s.pendingUpload, 1);
    });

    test('a draft is not waiting to be sent', () async {
      await inspection(uuid: 'half', at: DateTime.now(), status: 'draft');

      expect((await HomeSummary.load(db)).pendingUpload, 0);
    });
  });

  test('the empty summary is zeroes, not nulls', () {
    const s = HomeSummary.empty();
    expect(s.inspectionsToday, 0);
    expect(s.pendingUpload, 0);
    expect(s.offlineUsers, 0);
  });
}
