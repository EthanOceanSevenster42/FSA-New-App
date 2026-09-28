import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/features/poultry/presentation/signature_pad.dart';
import 'package:fsa_app/features/visits/data/visit_repository.dart';

/// The client's signature is optional; the inspector's is not. A refusal is
/// recorded the way the standalone forms record it, not left as a blank.
void main() {
  group('the signature pad', () {
    testWidgets('offers "No client signature" only when asked, and returns '
        'signatureDeclined for it', (tester) async {
      String? result = 'unset';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await captureSignature(
                context,
                title: 'Store / Client Signature',
                outputPath: '${Directory.systemTemp.path}/never-written.png',
                declineLabel: 'No client signature',
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No client signature'), findsOneWidget);
      // Nothing drawn: Next stays disabled, the refusal does not.
      final next = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
      expect(next.onPressed, isNull);

      await tester.tap(find.text('No client signature'));
      await tester.pumpAndSettle();
      expect(result, signatureDeclined);
    });

    testWidgets('the inspector\'s pad has no way to decline', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => captureSignature(
              context,
              title: 'Inspector Signature',
              outputPath: '${Directory.systemTemp.path}/never-written.png',
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No client signature'), findsNothing);
      expect(find.text('Next'), findsOneWidget);
    });
  });

  group('signing off a visit without the client', () {
    late LocalDatabase db;
    late Directory tmp;
    setUp(() {
      db = LocalDatabase(NativeDatabase.memory());
      tmp = Directory.systemTemp.createTempSync('sig');
    });
    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test('records a declined client signature and the inspector\'s own',
        () async {
      final visits = VisitRepository(db);
      await visits.create('v-1', 'Cinga');
      final now = DateTime(2026, 8, 28, 9);
      await db.into(db.poultryInspections).insert(
            PoultryInspectionsCompanion.insert(
              clientUuid: 'p-1',
              inspectedAt: now,
              updatedAt: now,
              visitUuid: const Value('v-1'),
              inspectorUsername: const Value('Cinga'),
              status: const Value('ready'),
            ),
          );
      await db.into(db.eggInspections).insert(
            EggInspectionsCompanion.insert(
              clientUuid: 'e-1',
              inspectedAt: now,
              updatedAt: now,
              visitUuid: const Value('v-1'),
              inspectorUsername: const Value('Cinga'),
              status: const Value('ready'),
            ),
          );
      final inspector = File('${tmp.path}/inspector.png')
        ..writeAsBytesSync([1, 2, 3]);

      await visits.complete(
        visitUuid: 'v-1',
        managerSignaturePath: signatureDeclined,
        inspectorSignaturePath: inspector.path,
        managerName: '',
        inspectorName: 'Cinga',
      );

      final poultrySigs = await db.select(db.poultrySignatures).get();
      expect(poultrySigs.map((s) => s.role).toSet(), {'no_client', 'inspector'});
      final refused = poultrySigs.singleWhere((s) => s.role == 'no_client');
      expect(refused.declined, isTrue);
      expect(refused.filePath, isEmpty);
      final signed = poultrySigs.singleWhere((s) => s.role == 'inspector');
      expect(File(signed.filePath).existsSync(), isTrue);

      final poultry = await db.select(db.poultryInspections).getSingle();
      expect(poultry.noClientSignaturePresent, isTrue);
      expect(poultry.status, 'completed');

      final eggSigs = await db.select(db.eggSignatures).get();
      final manager = eggSigs.singleWhere((s) => s.role == 'manager');
      expect(manager.declined, isTrue);
      expect(manager.filePath, isEmpty);
      expect(eggSigs.singleWhere((s) => s.role == 'inspector').filePath,
          isNotEmpty);

      final visit = await visits.byUuid('v-1');
      expect(visit!.managerSignaturePath, isEmpty);
      expect(visit.inspectorSignaturePath, inspector.path);
    });

    test('a signed client is stored as before', () async {
      final visits = VisitRepository(db);
      await visits.create('v-2', 'Cinga');
      final now = DateTime(2026, 8, 28, 9);
      await db.into(db.poultryInspections).insert(
            PoultryInspectionsCompanion.insert(
              clientUuid: 'p-2',
              inspectedAt: now,
              updatedAt: now,
              visitUuid: const Value('v-2'),
              inspectorUsername: const Value('Cinga'),
              status: const Value('ready'),
            ),
          );
      final manager = File('${tmp.path}/manager.png')..writeAsBytesSync([1]);
      final inspector = File('${tmp.path}/inspector.png')
        ..writeAsBytesSync([2]);
      await visits.complete(
        visitUuid: 'v-2',
        managerSignaturePath: manager.path,
        inspectorSignaturePath: inspector.path,
        managerName: 'Sam',
        inspectorName: 'Cinga',
      );
      final sigs = await db.select(db.poultrySignatures).get();
      expect(sigs.map((s) => s.role).toSet(), {'client', 'inspector'});
      expect(sigs.every((s) => !s.declined), isTrue);
      final poultry = await db.select(db.poultryInspections).getSingle();
      expect(poultry.noClientSignaturePresent, isFalse);
    });
  });
}
