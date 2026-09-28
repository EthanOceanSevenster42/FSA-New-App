import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/core/widgets/compliance_slider.dart';
import 'package:fsa_app/features/pmp/data/pmp_repository.dart';
import 'package:fsa_app/features/pmp/presentation/pmp_inspection_form.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/seizures/data/seizure_repository.dart';
import 'package:fsa_app/features/visits/data/record_documents.dart';

/// FSA-SOP-APS-001 Annexure E (Ethan, 2026-09-27): every immediate seizure
/// is recorded on the Department's seizure sheet. Choosing "Proceed with
/// seizure" asks for the particulars, writes the seizure, and the sheet is
/// offered beside the record's other documents.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    FsaForm.useAssets(FsaFormAssets(
      regular: pw.Font.ttf(
          (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
              .buffer
              .asByteData()),
      bold: pw.Font.ttf(
          (await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
              .buffer
              .asByteData()),
      logo: pw.MemoryImage(
          await File('assets/images/FSA_Logo.png').readAsBytes()),
    ));
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    final when = DateTime(2026, 9, 7, 13, 52);
    await SeizureRepository(database: db).record(SeizuresCompanion.insert(
      clientUuid: 'seizure-1',
      recordUuid: 'raw-1',
      recordKind: 'rawrmp',
      issuedAt: when,
      updatedAt: when,
      inspectorUsername: const Value('kabelo'),
      clientName: const Value('Checkers Blueberry Square'),
      clientAddress:
          const Value('Cnr Beyers Naude & Blueberry St, Roodepoort'),
      clientTelephone: const Value('011 251 2755'),
      clientEmail: const Value('store@example.com'),
      inspectionPoint: const Value('Butchery'),
      productName: const Value('Venison Boerewors'),
      productClass: const Value('Boerewors Raw'),
      quantity: const Value('5 packs (2.106 kg)'),
      regulation: const Value('Reg 5(7) of R2410 of 26 August 2022'),
      natureOfDeviation: const Value('The product does not comply with the '
          'compositional standard for the class concerned (Boerewors)'),
      remarks: const Value(
          'The product is manufactured using venison meat (game meat)'),
      receiverName: const Value('Manel'),
      receiverIdNumber: const Value('0747676100'),
      receiverDesignation: const Value('Butchery Manager'),
    ));
  }

  test('the seizure sheet builds from the record', () async {
    await seed();
    final file = await SeizureRepository(database: db)
        .buildDocument('raw-1', into: Directory.systemTemp);
    expect(file, isNotNull);
    expect(file!.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(4000));
    expect(file.path, endsWith('FSA-Checkers-Blueberry-Square-Seizure-raw-1.pdf'));
  });

  test('a seized consignment offers the sheet beside its documents',
      () async {
    await seed();
    final documents = await documentsForRecord(db, 'rawrmp', 'raw-1');
    expect(documents.map((d) => d.title), contains('Seizure'));
    expect(await documentsForRecord(db, 'rawrmp', 'raw-2'), isEmpty);
  });

  test('a record is seized once', () async {
    await seed();
    await seed();
    expect(await db.select(db.seizures).get(), hasLength(1));
  });

  group('on the PMP form', () {
    late Map<String, dynamic> bundle;

    setUp(() async {
      bundle = jsonDecode(
              await File('assets/reference/pmp_reference.json').readAsString())
          as Map<String, dynamic>;
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repository =
          PmpRepository(database: db, baseUrl: 'http://example.test');
      // ignore: invalid_use_of_visible_for_testing_member
      await repository.writeReferenceForTest(bundle);
      await tester.pumpWidget(MaterialApp(
        home: PmpInspectionForm(
          repository: repository,
          captureRepository: PoultryCaptureRepository(
              database: db, baseUrl: 'http://example.test'),
          inspectorName: 'ethan',
        ),
      ));
      await settle(tester);
    }

    Future<void> yes(WidgetTester tester, String label) async {
      final target = find.descendant(
        of: find.ancestor(
            of: find.text(label), matching: find.byType(YesNoQuestion)),
        matching: find.text('YES'),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await settle(tester);
    }

    Future<void> untick(WidgetTester tester, String description) async {
      final slider = find.descendant(
        of: find.ancestor(
            of: find.textContaining(description).first,
            matching: find.byType(Row)),
        matching: find.byType(ComplianceSlider),
      );
      await tester.ensureVisible(slider.first);
      tester.widget<ComplianceSlider>(slider.first).onChanged(false);
      await settle(tester);
    }

    testWidgets('proceeding with a seizure asks the particulars and records it',
        (tester) async {
      await open(tester);
      await yes(tester, 'Marking Label Present');
      await untick(tester, 'Date Marking/Batch Identification');
      expect(find.text('This consignment must be seized'), findsOneWidget);
      await tester.tap(find.text('Proceed with seizure'));
      await settle(tester);

      expect(find.text('Seizure particulars'), findsOneWidget);
      // Nothing is recorded without a quantity.
      await tester.tap(find.text('Record seizure'));
      await settle(tester);
      expect(find.textContaining('Say how much is seized'), findsOneWidget);
      expect(await db.select(db.seizures).get(), isEmpty);

      await tester.enterText(
          find.byKey(const Key('seizure-quantity')), '5 packs (2.106 kg)');
      await tester.enterText(
          find.byKey(const Key('seizure-receiver-id')), '0747676100');
      await tester.tap(find.text('Record seizure'));
      await settle(tester);
      expect(find.text('Seizure particulars'), findsNothing);

      final seizure = (await db.select(db.seizures).get()).single;
      expect(seizure.recordKind, 'pmp');
      expect(seizure.quantity, '5 packs (2.106 kg)');
      expect(seizure.receiverIdNumber, '0747676100');
      expect(seizure.regulation, 'R.1283 of 4 October 2019');
      expect(seizure.natureOfDeviation, contains('no batch code'));
      expect(seizure.inspectorUsername, 'ethan');
      expect(find.textContaining('Seizure under section 8'), findsOneWidget);
    });
  });
}
