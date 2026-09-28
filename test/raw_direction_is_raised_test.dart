import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';

/// The direction the original raises for you.
///
/// `SaveDirection` in the legacy app numbers the notice as it writes it —
/// `client / inspector cloud id / dd/MM/yyyy / nn`, where nn is how many that
/// inspector has raised today. The office quotes that number back, so it has
/// to be generated the same way and never renumbered.
void main() {
  late LocalDatabase db;
  late RawRmpRepository repo;
  final today = DateTime(2026, 9, 22, 10, 30);

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    repo = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    final raw =
        await File('assets/reference/rawrmp_reference.json').readAsString();
    await repo.writeReferenceForTest(jsonDecode(raw) as Map<String, dynamic>);
    await db.into(db.syncedUsers).insert(SyncedUsersCompanion.insert(
          id: const Value(37),
          username: 'ethan',
        ));
  });
  tearDown(() async => db.close());

  Future<void> raise(String uuid, {DateTime? at}) =>
      repo.saveDirection(RawRmpDirectionsCompanion.insert(
        clientUuid: uuid,
        issuedAt: at ?? today,
        updatedAt: at ?? today,
        inspectorUsername: const Value('ethan'),
      ));

  test('the number is the client, the inspector, the date and a count',
      () async {
    final reference = await repo.nextDirectionReference(
      inspectorUsername: 'ethan',
      clientName: 'Kroon Foods',
      at: today,
    );

    // 37 is the inspector's id as the server knows it — the original's cloud
    // user id — and 01 is the first direction of the day.
    expect(reference, 'Kroon Foods/37/22/09/2026/01');
  });

  test('it counts up through the day', () async {
    await raise('d-1');
    await raise('d-2');

    expect(
      await repo.nextDirectionReference(
          inspectorUsername: 'ethan', clientName: 'Kroon Foods', at: today),
      endsWith('/03'),
    );
  });

  test('yesterday does not carry into today', () async {
    await raise('d-old', at: today.subtract(const Duration(days: 1)));

    expect(
      await repo.nextDirectionReference(
          inspectorUsername: 'ethan', clientName: 'Kroon Foods', at: today),
      endsWith('/01'),
    );
  });

  test('another inspector keeps their own count', () async {
    await raise('d-1');
    await db.into(db.rawRmpDirections).insert(
        RawRmpDirectionsCompanion.insert(
            clientUuid: 'd-other',
            issuedAt: today,
            updatedAt: today,
            inspectorUsername: const Value('armand')));

    expect(
      await repo.nextDirectionReference(
          inspectorUsername: 'armand', clientName: 'Kroon Foods', at: today),
      // One of theirs today, so the next is 02 — ethan's does not count.
      endsWith('/02'),
    );
  });

  test('an inspector the device has never synced still gets a number',
      () async {
    final reference = await repo.nextDirectionReference(
      inspectorUsername: 'nobody',
      clientName: 'Kroon Foods',
      at: today,
    );

    // No id to quote rather than a nought, which would read as an id.
    expect(reference, 'Kroon Foods/22/09/2026/01');
  });
}
