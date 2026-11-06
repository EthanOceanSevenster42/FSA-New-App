// Renders egg labelling checklists for the backfill, with the same code and
// layout the handset uses — only the fonts and letterhead come from disk.
//
//   dart run tool/backfill_egg_labelling.dart <export-dir> <output-dir>
//
// <export-dir> holds manifest.json and images/ produced by the backend's
// export step. One PDF per record is written to <output-dir>, named
// <doc_id>.pdf, matching exactly what a completed, worked-through egg
// inspection would have produced on the handset.

import 'dart:convert';
import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/data/regulation_reference.dart';
import 'package:fsa_app/core/documents/fsa_checklist_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';

// The same section headings, in the same order, the handset uses.
const _titles = {
  'label_pack': 'MARKING OF CONTAINERS',
  'label_outer': 'MARKING OF OUTER CONTAINERS',
  'packing': 'PACKING REQUIREMENTS',
};

Future<pw.MemoryImage?> _img(String path) async {
  if (path.isEmpty) return null;
  final f = File(path);
  if (!f.existsSync()) return null;
  return pw.MemoryImage(await f.readAsBytes());
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/backfill_egg_labelling.dart '
        '<export-dir> <output-dir>');
    exit(2);
  }
  final exportDir = Directory(args[0]);
  final outDir = Directory(args[1])..createSync(recursive: true);

  // Load the same assets installFsaFormAssets() installs on the handset, so
  // the backfilled sheets carry the identical letterhead.
  Future<pw.MemoryImage> image(String rel) async =>
      pw.MemoryImage(await File('assets/images/$rel').readAsBytes());
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer
            .asByteData()),
    bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
        .buffer
        .asByteData()),
    logo: await image('FSA_Logo.png'),
    letterhead: await image('fsa_letterhead_logo.jpg'),
    letterheadLogo: await image('letterhead_logo.png'),
    letterheadIcons: await image('letterhead_icons.png'),
    letterheadFooter: await image('letterhead_footer.png'),
  ));

  final manifest = jsonDecode(
          await File('${exportDir.path}/manifest.json').readAsString())
      as Map<String, dynamic>;
  final requirements =
      (manifest['requirements'] as List).cast<Map<String, dynamic>>();
  final records = (manifest['records'] as List).cast<Map<String, dynamic>>();

  var written = 0;
  for (final r in records) {
    final failed = {
      for (final id in (r['failed_requirement_ids'] as List)) id as int,
    };
    final outer = r['outer_labelling_available'] as bool? ?? false;

    final sections = <FsaChecklistSection>[];
    for (final kind in _titles.keys) {
      if (kind == 'label_outer' && !outer) continue;
      final rows = requirements.where((q) => q['kind'] == kind).toList();
      if (rows.isEmpty) continue;
      sections.add(FsaChecklistSection(
        title: _titles[kind]!,
        rows: [
          for (final q in rows)
            FsaChecklistRow(
              requirement: q['description'] as String,
              regulation: cleanRegulation(q['regulation'] as String? ?? ''),
              deviation: failed.contains(q['id'] as int)
                  ? FsaDeviation.yes
                  : FsaDeviation.no,
            ),
        ],
      ));
    }
    if (sections.isEmpty) continue;

    String rel(String key) {
      final p = r[key] as String? ?? '';
      return p.isEmpty ? '' : '${exportDir.path}/$p';
    }

    final out = File('${outDir.path}/${r['doc_id']}.pdf');
    await FsaChecklistPdf.write(
      out: out,
      control: FsaDocuments.eggLabelling,
      facilityName: r['facility_name'] as String,
      leftFields: [
        (label: 'Date of Inspection:', value: r['date_ymd'] as String),
        (label: 'Facility Name:', value: r['facility_name'] as String),
        (label: 'Site Representative:', value: r['representative'] as String),
        (label: 'Tray Packaging Size', value: r['tray_size'] as String),
      ],
      rightFields: [
        (label: 'Producer/Supplier', value: r['producer_supplier'] as String),
        (label: 'Batch Number', value: r['batch_number'] as String),
        (label: 'Best Before Date', value: r['best_before_ymd'] as String),
        (label: 'Type of Facility', value: r['facility_type'] as String),
      ],
      sections: sections,
      inspectorName: r['inspector_name'] as String,
      authorisedPersonName: r['authorised_person_name'] as String,
      comments: r['comments'] as String,
      remarks: r['remarks'] as String,
      photoPaths: [if (rel('label_photo').isNotEmpty) rel('label_photo')],
      inspectorSignaturePath: rel('inspector_signature'),
      authorisedPersonSignaturePath: rel('authorised_signature'),
      documentTitle: 'Egg Labelling Checklist',
    );
    written++;
  }
  stdout.writeln('wrote $written PDF(s) to ${outDir.path}');
}
