import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';

/// `Migrator.createTable` builds a table with its current full schema, so an
/// old database upgrading across many versions must not fall over when a
/// later block ADDs a column the CREATE already included. The Redmi with a
/// pre-visits database crashed on exactly this ("duplicate column name:
/// planned_eggs") until every ALTER went through the guard.
void main() {
  test('adding a column that already exists is a no-op, not a crash',
      () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Force the schema into being before using the migrator directly.
    await db.customSelect('SELECT 1').get();
    final m = db.createMigrator();

    // Twice over: present already (created with the table), and after the
    // first call did nothing.
    await db.addColumnIfMissing(m, db.storeVisits, db.storeVisits.plannedEggs);
    await db.addColumnIfMissing(m, db.storeVisits, db.storeVisits.plannedEggs);
    await db.addColumnIfMissing(
        m, db.storeVisits, db.storeVisits.managerSignaturePath);

    final info = await db
        .customSelect('PRAGMA table_info("store_visits")')
        .get();
    final names = info.map((r) => r.data['name']).toList();
    expect(names.where((n) => n == 'planned_eggs').length, 1);
    expect(names, contains('manager_signature_path'));
  });
}
