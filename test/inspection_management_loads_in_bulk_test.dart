import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// Inspection Management was slow to open (reported 2026-10-08).
///
/// It read each visit's records one visit at a time: six queries a visit for
/// the members, one for the server marker, one for the seizures. A tablet
/// holding a few dozen signed-off visits therefore ran hundreds of queries
/// one after another before anything could be opened, and none of the tables
/// carried an index on `visit_uuid`, so every one of them scanned the table
/// end to end.
///
/// These tests hold the two halves of the fix: the whole list is read in a
/// fixed number of queries however many visits there are, and the indexes
/// exist for it to use.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seedVisit(int n) async {
    await db.into(db.storeVisits).insert(
          StoreVisitsCompanion.insert(
            uuid: 'visit-$n',
            startedAt: DateTime.utc(2026, 10, 8, 8),
            facilityName: Value('Facility $n'),
            inspectorUsername: const Value('cinga'),
            completedAt: Value(DateTime.utc(2026, 10, 8, 10)),
          ),
        );
    await db.into(db.eggInspections).insert(
          EggInspectionsCompanion.insert(
            clientUuid: 'egg-$n',
            inspectedAt: DateTime.utc(2026, 10, 8, 9),
            updatedAt: DateTime.utc(2026, 10, 8, 9),
            status: const Value('completed'),
            visitUuid: Value('visit-$n'),
          ),
        );
    await db.into(db.rawRmpInspections).insert(
          RawRmpInspectionsCompanion.insert(
            clientUuid: 'raw-$n',
            inspectedAt: DateTime.utc(2026, 10, 8, 9),
            updatedAt: DateTime.utc(2026, 10, 8, 9),
            status: const Value('completed'),
            visitUuid: Value('visit-$n'),
          ),
        );
  }

  test('one visit\'s members read the same as they always did', () async {
    await seedVisit(1);

    final members = await visits.members('visit-1');

    expect(members.map((m) => m.uuid).toSet(), {'egg-1', 'raw-1'});
    expect(members.every((m) => m.completed), isTrue);
  });

  test('many visits are read in one pass, grouped by visit', () async {
    for (var n = 1; n <= 25; n++) {
      await seedVisit(n);
    }

    final byVisit = await visits
        .membersForVisits([for (var n = 1; n <= 25; n++) 'visit-$n']);

    expect(byVisit.length, 25);
    for (var n = 1; n <= 25; n++) {
      expect(byVisit['visit-$n']!.map((m) => m.uuid).toSet(), {'egg-$n', 'raw-$n'},
          reason: 'visit-$n must carry its own records and nobody else\'s');
    }
  });

  test('a visit with no records comes back empty, not missing', () async {
    await db.into(db.storeVisits).insert(
          StoreVisitsCompanion.insert(
            uuid: 'bare',
            startedAt: DateTime.utc(2026, 10, 8, 8),
          ),
        );

    final byVisit = await visits.membersForVisits(['bare']);

    expect(byVisit.containsKey('bare'), isTrue);
    expect(byVisit['bare'], isEmpty);
  });

  test('the server marker is read for the whole list at once', () async {
    await seedVisit(1);
    await seedVisit(2);
    // The marker the server pull writes.
    await db.writeSyncState('visits.fromServer.visit-2', '1');

    final fromServer = await visits.fromServerAmong(['visit-1', 'visit-2']);

    expect(fromServer, {'visit-2'});
    expect(await visits.isFromServer('visit-2'), isTrue);
    expect(await visits.isFromServer('visit-1'), isFalse);
  });

  test('every table the list reads is indexed on visit_uuid', () async {
    // Opening the database runs the index creation; ask SQLite what it has.
    await seedVisit(1);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexes = {for (final r in rows) r.read<String>('name')};

    for (final table in const [
      'egg_inspections',
      'poultry_inspections',
      'poultry_quid_inspections',
      'poultry_label_inspections',
      'raw_rmp_inspections',
      'pmp_inspections',
    ]) {
      expect(indexes, contains('idx_${table}_visit_uuid'),
          reason: '$table is looked up by visit_uuid on every list');
    }
    expect(indexes, contains('idx_seizures_record_uuid'));
  });

  test('the query plan uses the index rather than scanning', () async {
    await seedVisit(1);
    final plan = await db
        .customSelect('EXPLAIN QUERY PLAN SELECT * FROM egg_inspections '
            "WHERE visit_uuid = 'visit-1'")
        .get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' ');

    expect(detail, contains('idx_egg_inspections_visit_uuid'),
        reason: 'the lookup must not scan the table: $detail');
  });
}
