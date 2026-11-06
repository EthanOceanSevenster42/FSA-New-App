import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// "Re-send everything" on the Server Sync screen.
///
/// An ordinary sync leaves an already-sent inspection alone, which is right
/// — otherwise every pass would re-upload days of work. But when the office
/// is holding an older copy than the device has (documents built by an
/// earlier version of the app, say) there has to be a way to put it right.
/// Reported 2026-10-08: an egg rejection reached APS with none of its six
/// deviation photographs.
void main() {
  late LocalDatabase db;
  late VisitRepository visits;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    visits = VisitRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed(String uuid,
          {required bool uploaded, required bool completed}) =>
      db.into(db.storeVisits).insert(StoreVisitsCompanion.insert(
            uuid: uuid,
            startedAt: DateTime.utc(2026, 10, 8, 8),
            completedAt:
                completed ? Value(DateTime.utc(2026, 10, 8, 10)) : const Value.absent(),
            isUploaded: Value(uploaded),
          ));

  Future<bool> uploadedOf(String uuid) async => (await (db.select(db.storeVisits)
            ..where((t) => t.uuid.equals(uuid)))
          .getSingle())
      .isUploaded;

  test('a sent inspection goes up again', () async {
    await seed('sent', uploaded: true, completed: true);

    final marked = await visits.markAllForResend();

    expect(marked, 1);
    expect(await uploadedOf('sent'), isFalse,
        reason: 'clearing the sent flag is what puts it back in front of sync');
  });

  test('an unfinished visit is left alone', () async {
    await seed('draft', uploaded: false, completed: false);

    final marked = await visits.markAllForResend();

    expect(marked, 0, reason: 'nothing signed off, nothing to send again');
    expect(await uploadedOf('draft'), isFalse);
  });

  test('one already waiting is not counted twice', () async {
    await seed('waiting', uploaded: false, completed: true);
    await seed('sent', uploaded: true, completed: true);

    final marked = await visits.markAllForResend();

    expect(marked, 1, reason: 'only the one that had been sent');
    expect(await uploadedOf('waiting'), isFalse);
    expect(await uploadedOf('sent'), isFalse);
  });

  test('nothing on the device reports nothing to send', () async {
    expect(await visits.markAllForResend(), 0);
  });
}
