// Rebuilds seizure sheets from an export, using the same document layer the
// handset runs — so a sheet regenerated here is the sheet the handset would
// produce today (Ethan, 2026-10-20).
//
// The seizures already on APS were filed before the form was rebuilt to the
// Department's template: they carry no Issued block, no Acknowledgement of
// receipt, no signatures and no authorisation. Regenerating replaces them.
//
//     dart run tool/backfill_seizures.dart <export dir> <out dir>
//
// <export dir> holds manifest.json and sig/ from export_seizures.py.
import 'dart:convert';
import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/core/documents/seizure_pdf.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: backfill_seizures.dart <export dir> <out dir>');
    exitCode = 64;
    return;
  }
  final export = Directory(args[0]);
  final out = Directory(args[1])..createSync(recursive: true);

  // The document layer is plain Dart: hand it the fonts and artwork the app
  // loads through its asset bundle.
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer.asByteData()),
    bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
        .buffer.asByteData()),
    logo: pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
    letterhead: pw.MemoryImage(
        await File('assets/images/fsa_letterhead_logo.jpg').readAsBytes()),
    letterheadLogo: pw.MemoryImage(
        await File('assets/images/letterhead_logo.png').readAsBytes()),
    letterheadIcons: pw.MemoryImage(
        await File('assets/images/letterhead_icons.png').readAsBytes()),
    letterheadFooter: pw.MemoryImage(
        await File('assets/images/letterhead_footer.png').readAsBytes()),
    departmentLogo: pw.MemoryImage(
        await File('assets/images/dept_agriculture_logo.jpg').readAsBytes()),
  ));

  final manifest = (jsonDecode(
          await File('${export.path}/manifest.json').readAsString()) as List)
      .cast<Map<String, dynamic>>();

  String sig(String? name) =>
      (name == null || name.isEmpty) ? '' : '${export.path}/sig/$name';
  DateTime? when(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  final written = <Map<String, String>>[];
  for (final r in manifest) {
    final id = r['seizure_id'].toString();
    final issued = when(r['issued_at']) ?? DateTime.now();
    final file = await SeizurePdf.write(
      out: File('${out.path}/seizure-$id.pdf'),
      clientName: r['client_name'] as String,
      clientAddress: r['client_address'] as String,
      clientTelephone: r['client_telephone'] as String,
      clientFax: r['client_fax'] as String,
      clientEmail: r['client_email'] as String,
      inspectionPoint: r['inspection_point'] as String,
      products: [
        SeizedProduct(
          productName: r['product_name'] as String,
          productClass: r['product_class'] as String,
          quantity: r['quantity'] as String,
          regulation: r['regulation'] as String,
          natureOfDeviation: r['nature_of_deviation'] as String,
          correctiveAction: (r['corrective_action'] as String).isEmpty
              ? 'Immediate'
              : r['corrective_action'] as String,
          remarks: r['remarks'] as String,
        ),
      ],
      issuedAt: issued,
      issuedPlace: r['client_name'] as String,
      inspectorName: r['inspector_name'] as String,
      inspectorSignaturePath: sig(r['inspector_signature'] as String?),
      receiverName: r['receiver_name'] as String,
      receiverIdNumber: r['receiver_id_number'] as String,
      receiverDesignation: r['receiver_designation'] as String,
      receiverSignaturePath: sig(r['receiver_signature'] as String?),
      receivedAt: when(r['received_at']) ?? issued,
      remarks: r['remarks'] as String,
    );
    written.add({
      'seizure_id': id,
      'visit_uuid': r['visit_uuid'].toString(),
      'record_uuid': r['record_uuid'].toString(),
      'record_kind': r['record_kind'].toString(),
      'file': file.path.split(Platform.pathSeparator).last,
      'bytes': '${file.lengthSync()}',
    });
    stdout.writeln('  seizure $id -> ${file.path.split(Platform.pathSeparator).last} '
        '(${file.lengthSync()} bytes)');
  }
  await File('${out.path}/written.json')
      .writeAsString(jsonEncode(written));
  stdout.writeln('${written.length} sheets rebuilt');
}
