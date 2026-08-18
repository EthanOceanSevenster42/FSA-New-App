import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';

/// Photographs and signatures on a poultry record.
///
/// The behaviour worth pinning down is the signature one: a refusal is an
/// outcome the original has a role for, and re-signing must replace rather
/// than accumulate.
void main() {
  late LocalDatabase db;
  late PoultryCaptureRepository repo;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    repo = PoultryCaptureRepository(
      database: db,
      baseUrl: 'http://example.test',
    );
  });
  tearDown(() async => db.close());

  group('photographs', () {
    test('belong to a record and a screen', () async {
      await repo.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: 'rec-1',
          kind: 'grading',
          filePath: '/tmp/a.jpg',
          capturedAt: DateTime(2026, 8, 18, 9),
        ),
      );
      await repo.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: 'rec-2',
          kind: 'label',
          filePath: '/tmp/b.jpg',
          capturedAt: DateTime(2026, 8, 18, 10),
        ),
      );

      final first = await repo.photosFor('rec-1');
      expect(first, hasLength(1));
      expect(first.single.kind, 'grading');
      // A record's photographs are its own; one table serving three screens
      // must not leak between them.
      expect(await repo.photosFor('rec-2'), hasLength(1));
    });

    test('are returned in the order they were taken', () async {
      for (final hour in [11, 9, 10]) {
        await repo.addPhoto(
          PoultryPhotosCompanion.insert(
            recordUuid: 'rec',
            kind: 'quid',
            filePath: '/tmp/$hour.jpg',
            capturedAt: DateTime(2026, 8, 18, hour),
          ),
        );
      }

      final paths = (await repo.photosFor('rec')).map((p) => p.filePath);
      expect(paths, ['/tmp/9.jpg', '/tmp/10.jpg', '/tmp/11.jpg']);
    });

    test('deleting one leaves the rest', () async {
      await repo.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: 'rec',
          kind: 'grading',
          filePath: '/tmp/a.jpg',
          capturedAt: DateTime(2026, 8, 18, 9),
        ),
      );
      final id = await repo.addPhoto(
        PoultryPhotosCompanion.insert(
          recordUuid: 'rec',
          kind: 'grading',
          filePath: '/tmp/b.jpg',
          capturedAt: DateTime(2026, 8, 18, 10),
        ),
      );

      await repo.deletePhoto(id);

      final left = await repo.photosFor('rec');
      expect(left, hasLength(1));
      expect(left.single.filePath, '/tmp/a.jpg');
    });
  });

  group('signatures', () {
    Future<void> sign(String role, {String? path, bool declined = false}) =>
        repo.saveSignature(
          PoultrySignaturesCompanion.insert(
            recordUuid: 'rec',
            role: role,
            signedAt: DateTime(2026, 8, 18, 12),
            filePath: Value(path ?? ''),
            declined: Value(declined),
          ),
        );

    test('re-signing replaces rather than accumulates', () async {
      await sign('client', path: '/tmp/first.png');
      await sign('client', path: '/tmp/second.png');

      final all = await repo.signaturesFor('rec');
      // A client re-signs when the first attempt is unreadable. Two rows would
      // leave the record with two answers to one question.
      expect(all, hasLength(1));
      expect(all.single.filePath, '/tmp/second.png');
    });

    test('each role is held separately', () async {
      await sign('inspector', path: '/tmp/i.png');
      await sign('client', path: '/tmp/c.png');

      final roles = (await repo.signaturesFor('rec')).map((s) => s.role);
      expect(roles, containsAll(['inspector', 'client']));
    });

    test('a refusal is recorded, not left blank', () async {
      await sign('no_client', declined: true);

      final refusal = (await repo.signaturesFor('rec')).single;
      // Absence would be indistinguishable from an inspection nobody
      // finished; the original treats "No Client Signature" as a role.
      expect(refusal.declined, isTrue);
      expect(refusal.filePath, isEmpty);
    });

    test('withdrawing a refusal clears the flag rather than the row', () async {
      await sign('no_client', declined: true);
      await sign('no_client');

      final row = (await repo.signaturesFor('rec')).single;
      expect(row.declined, isFalse);
    });
  });
}
