import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/core/widgets/restricted_particulars_picker.dart';
import 'package:fsa_app/features/eggs/data/eggs_repository.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

/// A restricted particular the Agency's list does not have is typed in at
/// the inspection and travels with that record — not into the list every
/// inspector picks from (Ethan, 2026-09-23).
///
/// The meat forms had a free-text keyword box under the picker for this;
/// eggs had nowhere at all. Now all four forms take typed ones through the
/// same picker, and eggs carries them to the office like the others.
void main() {
  late LocalDatabase db;

  setUp(() => db = LocalDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('eggs', () {
    test('a typed-in particular reaches the office with the record',
        () async {
      late Map<String, dynamic> sent;
      final eggs = EggsRepository(
        database: db,
        baseUrl: 'https://server.test',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"id": 7}', 201);
        }),
      );
      await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
            clientUuid: 'egg-typed',
            inspectedAt: DateTime(2026, 9, 23, 9),
            updatedAt: DateTime(2026, 9, 23, 9),
            status: const Value('completed'),
            restrictedParticularIds: const Value('3'),
            restrictedParticularsText:
                Value(TypedParticulars.pack({'Grain fed', 'Barn laid'})),
          ));
      final row = (await db.select(db.eggInspections).get()).single;

      await eggs.upload(row, token: 'jwt');

      expect(sent['restricted_particulars'], [3]);
      expect(sent['restricted_particulars_text'], 'Grain fed\nBarn laid');
    });

    test('the list the inspectors choose from is not written to', () async {
      final eggs = EggsRepository(database: db, baseUrl: '');
      // ignore: invalid_use_of_visible_for_testing_member
      await eggs.writeReferenceForTest(
          jsonDecode(await File('assets/reference/eggs_reference.json')
              .readAsString()) as Map<String, dynamic>);
      final before = (await db.select(db.eggRestrictedParticulars).get()).length;

      await db.into(db.eggInspections).insert(EggInspectionsCompanion.insert(
            clientUuid: 'egg-typed',
            inspectedAt: DateTime(2026, 9, 23, 9),
            updatedAt: DateTime(2026, 9, 23, 9),
            restrictedParticularsText: const Value('Grain fed'),
          ));

      final after = (await db.select(db.eggRestrictedParticulars).get()).length;
      expect(after, before);
      // And the names the summary shows are the chosen ones plus the typed
      // one, from the record itself.
      final row = (await db.select(db.eggInspections).get()).single;
      expect(TypedParticulars.unpack(row.restrictedParticularsText),
          {'Grain fed'});
    });
  });

  group('the raw form', () {
    late Map<String, dynamic> bundle;

    setUp(() async {
      bundle = jsonDecode(
              await File('assets/reference/rawrmp_reference.json')
                  .readAsString())
          as Map<String, dynamic>;
    });

    testWidgets('offers the typing entry in the picker, and no keyword box',
        (tester) async {
      final repository =
          RawRmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundle);
      await tester.pumpWidget(MaterialApp(
        home: RawRmpInspectionForm(
          repository: repository,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'ethan',
        ),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.text('Restricted Particulars Present'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      // Say the label carries some.
      await tester.tap(find.descendant(
        of: find.ancestor(
          of: find.text('Restricted Particulars Present'),
          matching: find.byType(YesNoQuestion),
        ),
        matching: find.text('YES'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Selection of Restricted Particular Keywords'),
          findsNothing,
          reason: 'typed ones go through the picker now');
      await tester.ensureVisible(find.text('Add restricted particular'));
      await tester.tap(find.text('Add restricted particular'));
      await tester.pumpAndSettle();
      expect(find.text(RestrictedParticularsPicker.typeItInLabel),
          findsOneWidget);
    });
  });

  test('every form takes typed ones through the shared picker', () {
    final forms = [
      'lib/features/eggs/presentation/egg_inspection_form.dart',
      'lib/features/rawrmp/presentation/rawrmp_inspection_form.dart',
      'lib/features/pmp/presentation/pmp_inspection_form.dart',
      'lib/features/poultry/presentation/poultry_label_checklist_form.dart',
    ];
    for (final path in forms) {
      final source = File(path).readAsStringSync();
      expect(source.contains(RegExp(r'typed: _typed(Restricted|Particulars),')),
          isTrue,
          reason: '$path must hand the picker a place for typed ones');
      expect(source.contains('Selection of Restricted Particular Keywords'),
          isFalse,
          reason: '$path must not keep a second way to type one in');
    }
  });
}
