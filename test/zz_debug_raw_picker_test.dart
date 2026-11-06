import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/data/local_database.dart';
import 'package:fsa_app/core/widgets/picker_menu_field.dart';
import 'package:fsa_app/features/poultry/data/poultry_capture_repository.dart';
import 'package:fsa_app/features/rawrmp/data/rawrmp_repository.dart';
import 'package:fsa_app/features/rawrmp/domain/raw_record_kind.dart';
import 'package:fsa_app/features/rawrmp/presentation/rawrmp_inspection_form.dart';

void main() {
  testWidgets('debug', (tester) async {
    final db = LocalDatabase(NativeDatabase.memory());
    final raw = RawRmpRepository(database: db, baseUrl: 'http://example.test');
    final capture = PoultryCaptureRepository(database: db, baseUrl: 'http://example.test');
    // ignore: invalid_use_of_visible_for_testing_member
    await raw.writeReferenceForTest(jsonDecode(await File('assets/reference/rawrmp_reference.json').readAsString()) as Map<String, dynamic>);
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    await tester.pumpWidget(MaterialApp(home: RawRmpInspectionForm(repository: raw, captureRepository: capture, inspectorName: 'ethan', recordKind: RawRecordKind.composition)));
    await tester.pumpAndSettle();
    print('pickers<String>: ${find.byType(PickerMenuField<String>).evaluate().length}');
    print('hint texts: ${find.text('The class APS files this product under').evaluate().length}');
    print('Product Class labels: ${find.textContaining('Product Class', findRichText: true).evaluate().length}');
    print('Batch Number labels: ${find.textContaining('Batch Number', findRichText: true).evaluate().length}');
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where((t) => t.isNotEmpty).take(40).toList();
    print('first texts: $texts');
    await db.close();
  });
}
