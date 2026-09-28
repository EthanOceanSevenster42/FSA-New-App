import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/seizure_decision_dialog.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/eggs/domain/egg_rules.dart';
import 'package:fsa_app/features/eggs/presentation/egg_inspection_form.dart';
import 'package:fsa_app/features/visits/domain/visit_prefill.dart';

/// The seizure question, put on the premises.
///
/// Annexure D of FSA-SOP-APS-001 draws the line at omission: a size or grade
/// designation that is not indicated at all is an immediate seizure under
/// section 8, while a wrong one is a 30-day rectification. The handset
/// treated both the same, so a consignment the SOP says to seize went out
/// with a rectification date on it and the decision was never put to the
/// inspector.
void main() {
  group('the rule', () {
    test('an omission is a seizure, and says which one', () {
      expect(
        EggRules.seizureReasons(
          sizeNotIndicated: true,
          gradeNotIndicated: false,
          trayNotIndicated: false,
        ),
        ['The size designation is not indicated on the pack (Reg. 10).'],
      );
      expect(
        EggRules.seizureReasons(
          sizeNotIndicated: true,
          gradeNotIndicated: true,
          trayNotIndicated: true,
        ),
        hasLength(3),
      );
    });

    test('a consignment with every indication on it is not seized', () {
      expect(
        EggRules.seizureRequired(
          sizeNotIndicated: false,
          gradeNotIndicated: false,
          trayNotIndicated: false,
        ),
        isFalse,
      );
    });
  });

  group('the record', () {
    late LocalDatabase db;
    late EggsRepository eggs;

    setUp(() async {
      db = LocalDatabase(NativeDatabase.memory());
      eggs = EggsRepository(database: db, baseUrl: '');
      await eggs.writeReferenceForTest(
          jsonDecode(await File('assets/reference/eggs_reference.json')
              .readAsString()) as Map<String, dynamic>);
    });
    tearDown(() async => db.close());

    testWidgets('an answered record does not ask a second time',
        (tester) async {
      await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
            clientUuid: 'egg-1',
            inspectedAt: DateTime(2026, 9, 23, 9),
            updatedAt: DateTime(2026, 9, 23, 9),
            visitUuid: const Value('visit-1'),
            inspectorUsername: const Value('ethan'),
            producerSupplier: Value((await eggs.suppliers()).first.name),
            declaredSizeId: const Value(-1),
            seizureDecision: Value(SeizureDecision.seize.stored),
          ));
      await tester.pumpWidget(MaterialApp(
        home: EggInspectionForm(
          repository: eggs,
          inspectorName: 'ethan',
          resumeUuid: 'egg-1',
          visit: const VisitPrefill(
            uuid: 'visit-1',
            facilityName: 'Kroon Foods',
            facilityAddress: '',
            facilityPhone: '',
            contactPerson: '',
            contactEmail: '',
            representative: '',
            managerName: '',
            managerEmail: '',
            facilityType: 'Retail outlet',
            inspectionReason: 'Inspection',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The size is not indicated, so the rule says seize — but the answer
      // is already on the record, so the question is not put again.
      expect(find.text('This consignment must be seized'), findsNothing);
    });
  });

  group('the dialog', () {
    testWidgets('offers both answers and returns the one chosen',
        (tester) async {
      SeizureDecision? answer;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                answer = await askAboutSeizure(context,
                    reason: 'The size designation is not indicated.');
              },
              child: const Text('ask'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('This consignment must be seized'), findsOneWidget);
      expect(find.text('Proceed with seizure'), findsOneWidget);
      expect(find.text('Carry on inspecting'), findsOneWidget);

      await tester.tap(find.text('Proceed with seizure'));
      await tester.pumpAndSettle();
      expect(answer, SeizureDecision.seize);
    });

    testWidgets('carrying on is an answer of its own', (tester) async {
      SeizureDecision? answer;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                answer = await askAboutSeizure(context, reason: 'No batch code.');
              },
              child: const Text('ask'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carry on inspecting'));
      await tester.pumpAndSettle();
      expect(answer, SeizureDecision.inspect);
      expect(SeizureDecision.of('inspect'), SeizureDecision.inspect);
      expect(SeizureDecision.of(''), isNull);
    });
  });
}
