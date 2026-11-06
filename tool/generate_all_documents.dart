// Renders the Agency's compliance documents for one worked visit per
// commodity, from the reference data the handset ships with.
//
//     dart run tool/generate_all_documents.dart <output directory>
//
// The forms are built by the same code the handset uses; only the fonts,
// the logo and the requirement wording come from disk instead of the asset
// bundle and the device database. It exists so the whole set can be
// produced — and checked against the Agency's own copies — on a machine
// where the Flutter test runner cannot start.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/direction_pdf.dart';
import 'package:fsa_app/core/documents/fsa_checklist_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/core/documents/quid_checklist_pdf.dart';
import 'package:fsa_app/features/eggs/data/egg_weighing_checklist_pdf.dart';
import 'package:fsa_app/features/invoicing/data/invoice_pdf.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_form_data.dart';
import 'package:fsa_app/features/rawrmp/data/composition_checklist_pdf.dart';
import 'package:fsa_app/core/documents/seizure_pdf.dart';
import 'package:fsa_app/features/visits/data/occurrence_document_pdf.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';

const inspector = 'CINGA NGONGO';
final generatedAt = DateTime(2026, 9, 1, 11, 30);

/// The sample pair of signatures every sheet is signed with (Ethan,
/// 2026-10-04), drawn into the output folder before the documents.
late String inspectorSignature;
late String managerSignature;

/// Two sample product photographs for the sampling checklists (Ethan,
/// 2026-10-04), so the sheets show where the pictures print.
late List<String> samplePhotos;

/// Five photographs for the grading sheet — one per sampled carcass.
late List<String> gradingPhotos;

/// Six deviation photographs for the egg rejection.
late List<String> sixPhotos;

/// Which folder each report is filed under. The Agency files by the kind of
/// document, not by commodity, so a seizure is found beside every other
/// seizure (Ethan, 2026-10-08).
const _folders = <String, String>{
  'RAW-Container-and-Labelling-Verification-Checklist.pdf': 'Labelling',
  'PMP-Container-and-Labelling-Verification-Checklist.pdf': 'Labelling',
  'POULTRY-Labelling-Verification-Checklist.pdf': 'Labelling',
  'EGG-Labeling-Checklist.pdf': 'Labelling',
  'RAW-Sampling-Checklist.pdf': 'Sampling',
  'PMP-Sampling-Checklist.pdf': 'Sampling',
  'POULTRY-Classification-and-Grading-Checklist.pdf': 'Grading',
  'POULTRY-QUID-Determination-Checklist.pdf': 'Grading',
  'EGG-Weighing-Checklist.pdf': 'Weighing',
  'RAW-Compositional-Requirements-Checklist.pdf': 'Composition',
  'RAW-Rejection.pdf': 'Rejections',
  'PMP-Rejection.pdf': 'Rejections',
  'POULTRY-Rejection.pdf': 'Rejections',
  'EGG-Rejection.pdf': 'Rejections',
  'RAW-Seizure.pdf': 'Seizures',
  'PMP-Seizure.pdf': 'Seizures',
  'POULTRY-Seizure.pdf': 'Seizures',
  'EGG-Seizure.pdf': 'Seizures',
  'Occurrence-Document.pdf': 'Occurrence',
  'RFI-Request-for-Invoice.pdf': 'Invoicing',
};

/// The report's file, inside the folder for its kind. A name with no folder
/// of its own lands at the top, so a new report is never lost quietly.
File _out(Directory out, String name) {
  final folder = _folders[name];
  return File(folder == null ? '${out.path}/$name' : '${out.path}/$folder/$name');
}

/// A stand-in photograph: a grey frame with a label across it.
Future<String> _drawPhoto(Directory out, String name, int shade) async {
  final canvas = img.Image(width: 600, height: 800);
  img.fill(canvas, color: img.ColorRgb8(shade, shade, shade));
  img.drawRect(canvas,
      x1: 20, y1: 20, x2: 579, y2: 779,
      color: img.ColorRgb8(90, 90, 90), thickness: 6);
  img.drawLine(canvas,
      x1: 20, y1: 20, x2: 579, y2: 779, color: img.ColorRgb8(120, 120, 120),
      thickness: 3);
  img.drawLine(canvas,
      x1: 579, y1: 20, x2: 20, y2: 779, color: img.ColorRgb8(120, 120, 120),
      thickness: 3);
  final file = File('${out.path}/sample-photo-$name.png');
  await file.writeAsBytes(img.encodePng(canvas));
  return file.path;
}

/// A signing pad's PNG: a stroke of ink across a transparent box, so the
/// sheets show where the signatures print and how large.
Future<String> _drawSignature(Directory out, String name, int seed) async {
  final canvas = img.Image(width: 600, height: 200, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 0));
  final ink = img.ColorRgba8(20, 30, 90, 255);
  int? px, py;
  for (var t = 0.0; t <= 1.0; t += 0.002) {
    final x = (40 + 520 * t).round();
    final y = (100 +
            55 * sin(t * 2 * pi * (2 + seed)) * (1 - t * 0.5) +
            25 * cos(t * 2 * pi * seed))
        .round();
    if (px != null) {
      img.drawLine(canvas,
          x1: px, y1: py!, x2: x, y2: y, color: ink, thickness: 5);
    }
    px = x;
    py = y;
  }
  final file = File('${out.path}/sample-signature-$name.png');
  await file.writeAsBytes(img.encodePng(canvas));
  return file.path;
}

/// One visit per commodity, so the office sees each document against a
/// facility of the right kind.
const visits = {
  'raw': (
    facility: 'Mabovula Butchery - Queenstown',
    address: '73 Robinson Queenstown 5320',
    town: 'Queenstown',
    type: 'Butchery',
    representative: 'S. Mabovula',
    producer: 'Karoo Meat Producers',
    product: 'Boerewors',
    batch: '4471',
  ),
  'pmp': (
    facility: 'SUPERSPAR - Westwood',
    address: '18 Phillips Rd, Westwood AH, Boksburg, 1477',
    town: 'Boksburg',
    type: 'Retailer/Distr. Center',
    representative: 'Buyelwa George',
    producer: 'Superspar Westwood',
    product: 'Cabanossi',
    batch: 'PMP-5527',
  ),
  'poultry': (
    facility: 'Rainbow Chickens - Hammarsdale',
    address: '1 Marshall Drive, Hammarsdale, 3700',
    town: 'Hammarsdale',
    type: 'Abattoir',
    representative: 'T. Ndlovu',
    producer: 'Rainbow Farms',
    product: 'Whole Frozen Chicken',
    batch: 'PM-8841',
  ),
  'egg': (
    facility: 'SHOPRITE - Bridge City Mall',
    address: 'Shop L2 Bridge City Mall, Kwamashu 4359',
    town: 'Kwamashu',
    type: 'Retailer/Distr. Center',
    representative: 'P. Person',
    producer: 'Nulaid Farms',
    product: 'Large Grade 1 Eggs',
    batch: 'EG-4471',
  ),
};

const inspectionDate = '1 September 2026';
const packedDate = '31 August 2026';

Future<void> main(List<String> args) async {
  final out = Directory(args.isEmpty ? 'build/documents' : args.first);
  await out.create(recursive: true);
  for (final folder in _folders.values.toSet()) {
    await Directory('${out.path}/$folder').create(recursive: true);
  }
  // The stand-in photographs and signatures are working files, not reports,
  // so they are drawn outside the report folder (Ethan, 2026-10-08).
  final scratch = await Directory.systemTemp.createTemp('fsa-sample-art');

  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf((await File('assets/fonts/Lato-Regular.ttf')
            .readAsBytes())
        .buffer
        .asByteData()),
    bold: pw.Font.ttf(
        (await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
            .buffer
            .asByteData()),
    logo: pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
    letterhead: pw.MemoryImage(
        await File('assets/images/fsa_letterhead_logo.jpg').readAsBytes()),
    letterheadLogo: pw.MemoryImage(
        await File('assets/images/letterhead_logo.png').readAsBytes()),
    letterheadIcons: pw.MemoryImage(
        await File('assets/images/letterhead_icons.png').readAsBytes()),
    letterheadFooter: pw.MemoryImage(
        await File('assets/images/letterhead_footer.png').readAsBytes()),
    // Without this the seizure sheets print with no Department of
    // Agriculture arms, which is what Neo Noe saw on the specimens
    // (2026-10-19) even though the handset's own copies carry them: the
    // app loads it through FsaFormAssetsBundle and this generator never
    // did.
    departmentLogo: pw.MemoryImage(
        await File('assets/images/dept_agriculture_logo.jpg').readAsBytes()),
  ));

  inspectorSignature = await _drawSignature(scratch, 'inspector', 1);
  managerSignature = await _drawSignature(scratch, 'manager', 2);
  samplePhotos = [
    await _drawPhoto(scratch, '1', 200),
    await _drawPhoto(scratch, '2', 170),
  ];
  // Grading samples five carcasses, one photograph each, so the grading
  // sheet shows five (Ethan, 2026-10-05).
  // Six, as the egg form allows for deviation photographs — the set an
  // underweight finding is evidenced with.
  sixPhotos = [
    for (var n = 1; n <= 6; n++) await _drawPhoto(scratch, 'egg-$n', 205 - n * 9),
  ];
  gradingPhotos = [
    for (var n = 1; n <= 5; n++) await _drawPhoto(scratch, 'grading-$n', 210 - n * 12),
  ];

  final written = <File>[
    ...await _raw(out),
    ...await _pmp(out),
    ...await _poultry(out),
    ...await _eggs(out),
    await _requestForInvoice(out),
    await _seizure(out),
    ...await _extraRejectionsAndSeizures(out),
    await _occurrence(out),
  ];
  for (final file in written) {
    stdout.writeln('${file.path.split(RegExp(r'[\\/]')).last}  '
        '(${await file.length()} bytes)');
  }
}

// --------------------------------------------------------------- helpers

/// The checklist rows a reference file carries for one kind of block.
Future<List<FsaChecklistRow>> _rows(
  String reference,
  String collection,
  bool Function(Map<String, dynamic>) where, {
  FsaDeviation Function(int index)? answer,
}) async {
  final raw = jsonDecode(await File('assets/reference/$reference').readAsString());
  final data = (raw is Map && raw['data'] is Map) ? raw['data'] : raw;
  final rows = ((data as Map)[collection] as List)
      .cast<Map<String, dynamic>>()
      .where(where)
      .toList()
    ..sort((a, b) =>
        ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0) as num));
  return [
    for (final (index, r) in rows.indexed)
      FsaChecklistRow(
        requirement: (r['description'] ?? '').toString(),
        // The egg reference names the column `regulation`; the meat
        // ones name it `regulation_reference`.
        regulation:
            (r['regulation_reference'] ?? r['regulation'] ?? '').toString(),
        // Bare millimetres, as the live document prints them and as the
        // PMP and raw sheets already did — the specimen used to add "mm"
        // and so did not match what the client is handed.
        standard: ((r['min_lettering_height'] ?? '').toString().isEmpty)
            ? '-'
            : (r['min_lettering_height']).toString(),
        deviation: answer?.call(index) ?? FsaDeviation.no,
      ),
  ];
}

/// Most requirements are met; the exceptions are what the sheet is for.
FsaDeviation Function(int) _failing(Set<int> indices) =>
    (index) => indices.contains(index) ? FsaDeviation.yes : FsaDeviation.no;

FsaDeviation _notApplicable(int _) => FsaDeviation.notApplicable;

List<FsaField> _left(({
  String facility,
  String address,
  String town,
  String type,
  String representative,
  String producer,
  String product,
  String batch
}) v,
        {String dateLabel = 'Date of Inspection:'}) =>
    [
      (label: dateLabel, value: inspectionDate),
      (label: 'Facility Name:', value: v.facility),
      (label: 'Reason for Inspection:', value: 'Inspection'),
      (label: 'Manufactured/Packed Date', value: packedDate),
    ];

List<FsaField> _right(({
  String facility,
  String address,
  String town,
  String type,
  String representative,
  String producer,
  String product,
  String batch
}) v) =>
    [
      (label: 'Producer', value: v.producer),
      (label: 'Product Name Inspected', value: v.product),
      (label: 'Batch Number', value: v.batch),
    ];

// ------------------------------------------------------------------ raw

Future<List<File>> _raw(Directory out) async {
  final v = visits['raw']!;
  final marking = await _rows('rawrmp_reference.json', 'checklist_items',
      (r) => r['section'] == 'marking',
      answer: _failing({4, 5}));
  final container = await _rows('rawrmp_reference.json', 'checklist_items',
      (r) => r['section'] == 'container');
  final scale = await _rows('rawrmp_reference.json', 'checklist_items',
      (r) => r['section'] == 'scale',
      answer: _failing({5}));
  final fridge = await _rows('rawrmp_reference.json', 'checklist_items',
      (r) => r['section'] == 'fridge',
      answer: _notApplicable);
  final notice = await _rows('rawrmp_reference.json', 'checklist_items',
      (r) => r['section'] == 'notice',
      answer: _notApplicable);

  final labelling = await FsaChecklistPdf.write(
    out: _out(out, 'RAW-Container-and-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.rawLabelling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: [
      FsaChecklistSection(title: 'MARKING REQUIREMENTS', rows: marking),
      FsaChecklistSection(title: 'CONTAINERS & OUTER CONTAINERS', rows: container),
      FsaChecklistSection(title: 'SCALE LABEL REQUIREMENTS', rows: scale),
      FsaChecklistSection(title: 'DISPLAY FRIDGE LABEL REQUIREMENTS', rows: fridge),
      FsaChecklistSection(
          title: 'NOTICE BOARDS, SIGNAGE, AVERTISEMENTS, ETC.', rows: notice),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'The country of origin is not indicated on the scale label, and '
        'the batch code is absent from the container marking.',
    remarks: 'The marking on the container is in contravention to R.2410 of '
        '26 August 2022 (Certain Raw Processed Meat Products Regulation)',
    documentTitle: 'Container and Labelling Verification Checklist',
  );

  final sampling = await FsaChecklistPdf.write(
    out: _out(out, 'RAW-Sampling-Checklist.pdf'),
    control: FsaDocuments.rawSampling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v, dateLabel: 'Date of Sampling:'),
    rightFields: _right(v),
    sections: const [
      FsaChecklistSection(title: 'SAMPLE DETAILS', rows: [
        FsaChecklistRow(requirement: 'Internal sample number', value: 'RMP-2026-118'),
        FsaChecklistRow(requirement: 'Sample size taken', value: '500 g'),
        FsaChecklistRow(requirement: 'Laboratory', value: 'Deltamune Laboratories'),
        FsaChecklistRow(
            requirement: 'Laboratory testing category',
            value: 'Composition & Species'),
        FsaChecklistRow(
            requirement: 'Testing for',
            value: 'Fat, Protein, Calcium (MRM only), DNA'),
        FsaChecklistRow(requirement: 'Storage method', value: 'Chilled'),
        FsaChecklistRow(requirement: 'Delivery method', value: 'Courier'),
        FsaChecklistRow(requirement: 'Waybill number', value: 'AWB-773311'),
      ]),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'Sample drawn from the display fridge in the presence of the manager.',
    remarks: 'Sample submitted for compositional analysis under R.2410.',
    documentTitle: 'Sampling Checklist',
  );

  // Eight rows since 2026-10-19, when mechanically deboned meat was given
  // one of its own (Neo Noe); the amounts are in kg and Total Meat Content
  // (row 9) is worked out from rows 1 to 8. The specimen shows MDM found
  // in a boerewors, which may not contain it — the reason for the row.
  final answers = CompositionChecklist.blank();
  answers[0] = const CompositionAnswer(deviation: false, contributionGrams: '1.2');
  answers[1] = const CompositionAnswer(deviation: false, contributionGrams: '0');
  answers[2] = const CompositionAnswer(deviation: true, contributionGrams: '0.03');
  answers[3] = const CompositionAnswer(deviation: false, contributionGrams: '0');
  answers[4] = const CompositionAnswer(deviation: true, contributionGrams: '0.06');
  answers[5] = const CompositionAnswer(deviation: false, contributionGrams: '0');
  answers[6] = const CompositionAnswer(deviation: false, contributionGrams: '0.02');
  answers[7] = const CompositionAnswer(
      deviation: true,
      contributionGrams: '0.04',
      remarks: 'MDM not permitted in boerewors');
  final composition = await CompositionChecklistPdf.write(
    out: _out(out, 'RAW-Compositional-Requirements-Checklist.pdf'),
    facilityName: v.facility,
    facilityAddress: v.address,
    dateOfSampling: inspectionDate,
    siteRepresentative: v.representative,
    representativePosition: 'Butchery Manager',
    facilityType: v.type,
    productName: v.product,
    batchNumber: v.batch,
    manufacturedPackedDate: packedDate,
    answers: answers,
    comments: 'Mechanically recovered meat and vegetable protein present in a '
        'product labelled as pure beef boerewors. Producer to be directed to '
        'correct the formulation and the label.',
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
  );

  final rejection = await DirectionPdf.write(
    out: _out(out, 'RAW-Rejection.pdf'),
    control: FsaDocuments.rawDirection,
    natureOfInspection: 'Certain Raw Processed Meat Products',
    regulation: 'R.2410 of 26 August 2022',
    photoPaths: samplePhotos,
    facilityName: v.facility,
    ownerOrRepresentative: v.representative,
    physicalAddress: v.address,
    emailAddress: 'elsadmin@econofoods.co.za',
    dateOfVisit: DateTime(2026, 9, 1),
    inspectionReason: 'Certain Raw Processed Meat Products',
    latestReference: 'INS-260901-0457',
    originalReference: 'CHK-260901-0133',
    subjectFields: [
      (label: 'Product Type', value: 'Certain Raw Processed Meat Products'),
      (label: 'Producer', value: v.producer),
      (label: 'Product Details', value: v.product),
      (label: 'Batch Number', value: v.batch),
    ],
    deviations: const [
      DirectionDeviation(
          product: 'Boerewors',
          nature: 'Date marking/batch code not indicated on the container '
              'marking.',
          regulation: 'Reg. 7(1)(d) & 10'),
      DirectionDeviation(
          product: 'Boerewors',
          nature: 'Country of origin not indicated on the container marking '
              'or on the scale label.',
          regulation: 'Reg. 7(1)(e) & 11'),
    ],
    correctByDate: '3 November 2026',
    // Two lines on purpose — the remark and the comment — to prove each lands
    // on its own ruled line instead of printing across the one below.
    actionsAndRemark: [
      'Rejection issued and discussed with Client',
      '1. The address or telephone number of the manufacturer, packer or '
          'seller is not indicated.',
    ].join('\n'),
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    pleaseNote: 'Failure to rectify by the date above will result in a '
        'seizure of the product in terms of the Agricultural Product '
        'Standards Act, No. 119 of 1990.',
  );
  return [labelling, sampling, composition, rejection];
}

// ------------------------------------------------------------------ pmp

Future<List<File>> _pmp(Directory out) async {
  final v = visits['pmp']!;
  Future<List<FsaChecklistRow>> rows(String section,
          {FsaDeviation Function(int)? answer}) =>
      _rows('pmp_reference.json', 'checklist_items', (r) => r['section'] == section,
          answer: answer);

  final labelling = await FsaChecklistPdf.write(
    out: _out(out, 'PMP-Container-and-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.pmpLabelling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: [..._right(v), (label: 'Sample Size', value: '218g')],
    sections: [
      FsaChecklistSection(
          title: 'MARKING REQUIREMENTS',
          rows: await rows('marking', answer: _notApplicable)),
      FsaChecklistSection(
          title: 'CONTAINERS & OUTER CONTAINERS', rows: await rows('container')),
      FsaChecklistSection(
          title: 'SCALE LABEL REQUIREMENTS',
          // 3, 4 and 6 are the date marking, the country of origin and the
          // manufacturer's name and telephone number — the three
          // non-conformities the rejection is served on, so the checklist
          // and the direction agree (Ethan, 2026-10-08).
          rows: await rows('scale', answer: _failing({3, 4, 6}))),
      FsaChecklistSection(
          title: 'DISPLAY FRIDGE LABEL REQUIREMENTS',
          rows: await rows('fridge', answer: _notApplicable)),
      FsaChecklistSection(
          title: 'NOTICE BOARDS, SIGNAGE, AVERTISEMENTS, ETC.',
          rows: await rows('notice', answer: _notApplicable)),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'The scale label carries no date marking or batch '
        'identification, no country of origin, and no name and telephone '
        'number for the manufacturer, packer or seller.',
    remarks: 'The marking on the container is in contravention to R.1283 of '
        '4 October 2019 (Processed Meat Products Regulation)',
    documentTitle: 'Container and Labelling Verification Checklist',
  );

  final sampling = await FsaChecklistPdf.write(
    out: _out(out, 'PMP-Sampling-Checklist.pdf'),
    control: FsaDocuments.pmpSampling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v, dateLabel: 'Date of Sampling:'),
    rightFields: [..._right(v), (label: 'Sample Size', value: '218g')],
    sections: const [
      FsaChecklistSection(title: 'SAMPLE DETAILS', rows: [
        FsaChecklistRow(requirement: 'Internal sample number', value: 'PMP-2026-207'),
        FsaChecklistRow(requirement: 'Sample size taken', value: '400 g'),
        FsaChecklistRow(requirement: 'Laboratory', value: 'Deltamune Laboratories'),
        FsaChecklistRow(
            requirement: 'Testing for', value: 'Fat, Protein'),
        FsaChecklistRow(requirement: 'Storage method', value: 'Chilled'),
        FsaChecklistRow(
            requirement: 'Recipe/ingredient list available', value: 'Yes'),
        FsaChecklistRow(requirement: 'Delivery method', value: 'Hand delivered'),
        FsaChecklistRow(requirement: 'Waybill number', value: '-'),
      ]),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'Sample drawn from the deli counter in the presence of the manager.',
    remarks: 'Sample submitted for compositional analysis under R.1283.',
    documentTitle: 'Sampling Checklist',
  );
  return [labelling, sampling];
}

// -------------------------------------------------------------- poultry

Future<List<File>> _poultry(Directory out) async {
  final v = visits['poultry']!;
  Future<List<FsaChecklistRow>> rows(String kind,
          {FsaDeviation Function(int)? answer}) =>
      _rows('poultry_reference.json', 'checklist_items', (r) => r['kind'] == kind,
          answer: answer);

  final labelling = await FsaChecklistPdf.write(
    out: _out(out, 'POULTRY-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.poultryLabelling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: [
      // One lettering table (Neo Noe, 2026-10-20): the Poultry Regulation
      // has no inner and outer container, so the sheet shows the container
      // once. The handset's own copy does the same.
      FsaChecklistSection(
          title: 'LETTERING: CONTAINER',
          rows: await rows('label_inner', answer: _failing({2}))),
      FsaChecklistSection(
          title: 'CONTAINER REQUIREMENTS', rows: await rows('container')),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    // Three numbered comments, as an inspector actually writes them. A
    // single short line never exercised the box growing, and the third
    // line used to print across the border (Kabelo, 2026-10-23).
    comments: '1. Incorrect indication of the grade designation as "Gr A" '
        'instead of "Grade A".\n'
        '2. The expression "Previously Frozen" may create a misleading '
        'impression regarding the nature of the product.\n'
        '3. The expression "Without Giblets/Giblets Removed/Giblets '
        'Excluded" is not indicated on the product container.',
    remarks: 'The marking on the container is in contravention to R.946 of '
        '27 March 1992, as amended (Poultry Meat Regulation)',
    documentTitle: 'Labelling Verification Checklist',
  );

  final grading = await FsaChecklistPdf.write(
    out: _out(out, 'POULTRY-Classification-and-Grading-Checklist.pdf'),
    control: FsaDocuments.poultryGrading,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: [
      FsaChecklistSection(
          title: 'QUALITY STANDARDS',
          // 1 is breast fleshiness and 9 is abrasions and cuts in the skin —
          // the comment below and the rejection name the same two
          // (Ethan, 2026-10-08).
          rows: await rows('grading', answer: _failing({1, 9}))),
      FsaChecklistSection(
          title: 'STANDARDS FOR PORTIONS', rows: await rows('portion')),
      FsaChecklistSection(
          title: 'PACKING REQUIREMENTS', rows: await rows('pack')),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'Breast fleshiness and skin damage outside the tolerance for the '
        'grade declared on the label.',
    remarks: 'The consignment is in contravention to R.946 of 27 March 1992, '
        'as amended (Poultry Meat Regulation)',
    photoPaths: gradingPhotos,
    documentTitle: 'Classification and Grading Checklist',
  );

  // The real QUID Determination Checklist (Ethan, 2026-10-04): one injector
  // weighed through, its injection rates beside its determination.
  const injectionBefore = ['1 402', '1 388', '1 420', '1 395', '1 410'];
  const injectionAfter = ['1 545', '1 530', '1 566', '1 539', '1 553'];
  const injectionGain = ['143', '142', '146', '144', '143'];
  const injectionRate = ['10.200', '10.231', '10.282', '10.323', '10.142'];
  const determinedFinal = ['1 561', '1 547', '1 580', '1 553', '1 569'];
  const determinedQuid = ['10.186', '10.278', '10.127', '10.174', '10.134'];
  const chillingFinal = ['1 410', '1 397', '1 429', '1 404', '1 419'];
  const chillingPickup = ['0.567', '0.644', '0.630', '0.641', '0.634'];
  final quid = await QuidChecklistPdf.write(
    out: _out(out, 'POULTRY-QUID-Determination-Checklist.pdf'),
    control: FsaDocuments.poultryQuid,
    facilityName: v.facility,
    dateOfInspection: inspectionDate,
    reasonForInspection: 'Inspection',
    registrationNumber: '2001/123456/07',
    portionType: 'Whole Carcass',
    // 10% on whole carcasses, 15% on portions (Neo Noe, 2026-10-19); the
    // specimen used to show a whole carcass against the portion figure.
    allowableQuidPercent: '10',
    isWaterChilled: true,
    chilling: [
      for (var i = 0; i < 5; i++)
        QuidCarcass(
          number: '${i + 1}',
          initialMassG: injectionBefore[i],
          finalMassG: chillingFinal[i],
          percent: chillingPickup[i],
        ),
    ],
    averagePickupPercent: '0.623',
    // Water chilling is read against Reg. 4(2)'s 7% absorbed moisture.
    waterChillWithinLimit: true,
    iterationNumber: '1',
    injectors: [
      QuidInjectorBlock(
        name: 'Injector 1 - brine',
        setPercent: '15',
        injection: [
          for (var i = 0; i < 5; i++)
            QuidInjectorCarcass(
              number: '${i + 1}',
              beforeMassG: injectionBefore[i],
              afterMassG: injectionAfter[i],
              gainG: injectionGain[i],
              ratePercent: injectionRate[i],
            ),
        ],
        averageRatePercent: '10.236',
        determination: [
          for (var i = 0; i < 5; i++)
            QuidDeterminedCarcass(
              sampleNumber: '${i + 1}',
              initialMassG: injectionBefore[i],
              finalMassG: determinedFinal[i],
              setPercent: '15',
              calculatedPercent: determinedQuid[i],
            ),
        ],
        averageQuidPercent: '10.180',
        verdict: 'Within the limit: 10.180% against the 16% allowed '
            '(set to 15% plus the tolerance), over 5 carcasses.',
        passes: true,
      ),
    ],
    averageQuidPercent: '10.180',
    quidInitialMassG: '7 015',
    quidAfterMassG: '7 810',
    quidGainMassG: '795',
    verificationDate: inspectionDate,
    documentName: 'Brine batch record BR-2291',
    documentVerified: 'YES',
    documentDeviationPresent: 'NO',
    documentDeviationComment: '',
    verificationRecords: const [
      QuidVerifiedRecord(
        date: inspectionDate,
        name: 'Brine batch record BR-2291',
        verified: 'YES',
        deviationPresent: 'NO',
        comment: '',
        photographed: 'NO',
      ),
      QuidVerifiedRecord(
        date: inspectionDate,
        name: 'Chiller temperature log',
        verified: 'YES',
        deviationPresent: 'NO',
        comment: '',
        photographed: 'NO',
      ),
    ],
    withinPermissibleLimit: 'YES',
    comments: '',
    remarks: '',
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    generatedAt: generatedAt,
  );
  return [labelling, grading, quid];
}

// ----------------------------------------------------------------- eggs

Future<List<File>> _eggs(Directory out) async {
  final v = visits['egg']!;
  final weighing = await EggWeighingChecklistPdf.write(
    out: _out(out, 'EGG-Weighing-Checklist.pdf'),
    facilityName: v.facility,
    facilityAddress: v.address,
    dateOfInspection: inspectionDate,
    representative: v.representative,
    facilityType: v.type,
    producerSupplier: v.producer,
    batchNumber: v.batch,
    bestBefore: '14 September 2026',
    declaredSize: 'Large',
    declaredGrade: 'Grade 1',
    traySize: '12',
    rows: [
      for (var i = 1; i <= 12; i++)
        EggWeighingRow(
          number: i,
          massG: 50.0 + i * 0.6,
          albumenHeightMm: 6.4 + i * 0.1,
          haughUnit: 72 + i.toDouble(),
          deviations:
              i % 5 == 0 ? const ['Large - <= 2g of Min. Weight'] : const [],
        ),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'Two eggs under the declared minimum mass. Consignment '
        'downgraded and a direction served on the retailer.',
    // The tray label photograph was never passed, so the sheet printed no
    // picture at all (Ethan, 2026-10-08).
    trayLabelPhotoPath: samplePhotos.first,
  );

  final labelling = await FsaChecklistPdf.write(
    out: _out(out, 'EGG-Labeling-Checklist.pdf'),
    control: FsaDocuments.eggLabelling,
    photoPaths: samplePhotos,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: [
      (label: 'Date of Inspection:', value: inspectionDate),
      (label: 'Facility Name:', value: v.facility),
      (label: 'Site Representative:', value: v.representative),
      // The size the consignment is sold as - the specimen has to show
      // it, or a review copy reads the same for every egg check.
      (label: 'Egg Size/Class', value: 'Extra Large'),
      (label: 'Tray Packaging Size', value: '30'),
    ],
    rightFields: [
      (label: 'Producer/Supplier', value: v.producer),
      (label: 'Batch Number', value: v.batch),
      (label: 'Best Before Date', value: '14 September 2026'),
      (label: 'Type of Facility', value: v.type),
    ],
    sections: [
      FsaChecklistSection(
          title: 'MARKING OF CONTAINERS',
          // Index 4 is the "Best Before"/"BB" row, [Reg. 8 (1)(f)] — the same
          // non-conformity the egg rejection is served on, so the checklist
          // and the direction agree (Ethan, 2026-10-08).
          rows: await _rows('eggs_reference.json', 'requirements',
              (r) => r['kind'] == 'label_pack',
              answer: _failing({4}))),
      FsaChecklistSection(
          title: 'MARKING OF OUTER CONTAINERS',
          rows: await _rows('eggs_reference.json', 'requirements',
              (r) => r['kind'] == 'label_outer',
              answer: _notApplicable)),
      FsaChecklistSection(
          title: 'PACKING REQUIREMENTS',
          rows: await _rows('eggs_reference.json', 'requirements',
              (r) => r['kind'] == 'packing')),
    ],
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    authorisedPersonSignaturePath: managerSignature,
    authorisedPersonName: v.representative,
    comments: 'The best-before date is not indicated on the container.',
    remarks: 'The marking on the container is in contravention to R.345 of '
        '20 March 2020 (Egg Regulation)',
    documentTitle: 'Egg Labeling Checklist',
  );
  return [weighing, labelling];
}

// ------------------------------------------------------- request for invoice

/// SOP-APS-002 — the Request for Invoice, which bills the visit.
///
/// One visit, four commodities, samples on the two meat ones: the hours and
/// the laboratory tests are what the Agency invoices against.
/// The seizure served on a consignment (FSA-SOP-APS-001 Annexure E).
Future<File> _seizure(Directory out) {
  final v = visits['raw']!;
  return SeizurePdf.write(
    out: _out(out, 'RAW-Seizure.pdf'),
    clientName: v.facility,
    clientAddress: v.address,
    clientTelephone: '045 838 1234',
    clientFax: '',
    clientEmail: 'shop@mabovula.test',
    inspectionPoint: v.facility,
    products: const [
      SeizedProduct(
        productName: 'Boerewors',
        productClass: 'Certain Raw Processed Meat Products',
        quantity: '40 packs (28 kg)',
        regulation: 'Reg. 7(1)',
        natureOfDeviation: 'No product name on the label.',
      ),
    ],
    issuedAt: DateTime(2026, 9, 1, 11, 30),
    issuedPlace: 'Queenstown',
    inspectorName: inspector,
    inspectorSignaturePath: inspectorSignature,
    receiverName: v.representative,
    receiverSignaturePath: managerSignature,
    receiverIdNumber: '8001015009087',
    receiverDesignation: 'Butchery Manager',
    findings: 'The product on display carried no product name on the label '
        'and was removed from sale and seized.',
  );
}

/// Every remaining rejection (PMP, poultry, egg) and seizure (PMP, poultry,
/// egg), so the sample set shows all four commodities' notices, not just RAW.
Future<List<File>> _extraRejectionsAndSeizures(Directory out) async {
  final pmp = visits['pmp']!;
  final pou = visits['poultry']!;
  final egg = visits['egg']!;

  Future<File> rejection(
          String name, dynamic control, String nature, dynamic v,
          List<DirectionDeviation> devs,
          {String reg = '',
          String email = '',
          List<String> photos = const [],
          List<String> actions = const []}) =>
      DirectionPdf.write(
        out: _out(out, name),
        control: control,
        natureOfInspection: nature,
        regulation: reg,
        photoPaths: photos.isEmpty ? samplePhotos : photos,
        facilityName: v.facility,
        ownerOrRepresentative: v.representative,
        physicalAddress: v.address,
        emailAddress: email,
        dateOfVisit: DateTime(2026, 9, 1),
        inspectionReason: nature,
        // Latest Reference No. = the inspection number; Original Reference
        // No. = the rejection number (Ethan, 2026-10-08).
        latestReference: 'INS-260901-0457',
        originalReference: 'CHK-260901-0133',
        subjectFields: [
          (label: 'Product Type', value: nature),
          (label: 'Producer', value: v.producer),
          (label: 'Product Details', value: v.product),
          (label: 'Batch Number', value: v.batch),
        ],
        deviations: devs,
        correctByDate: '3 November 2026',
        actionsAndRemark: (actions.isEmpty
                ? const [
                    'Rejection issued and discussed with Client',
                    '1. The required particulars are not indicated on the '
                        'label.',
                  ]
                : actions)
            .join('\n'),
        inspectorName: inspector,
        authorisedPersonName: v.representative,
        inspectorSignaturePath: inspectorSignature,
        authorisedPersonSignaturePath: managerSignature,
        pleaseNote: 'Failure to rectify by the date above will result in a '
            'seizure of the product in terms of the Agricultural Product '
            'Standards Act, No. 119 of 1990.',
      );

  Future<File> seizure(
          String name, dynamic v, String productClass, String qty) =>
      SeizurePdf.write(
        out: _out(out, name),
        clientName: v.facility,
        clientAddress: v.address,
        clientTelephone: '',
        clientFax: '',
        clientEmail: '',
        inspectionPoint: v.facility,
        products: [
          SeizedProduct(
            productName: v.product,
            productClass: productClass,
            quantity: qty,
            regulation: 'Reg. 7(1)',
            natureOfDeviation:
                'Required particulars not indicated on the label.',
          ),
        ],
        issuedAt: DateTime(2026, 9, 1, 11, 30),
        issuedPlace: v.town,
        inspectorName: inspector,
        inspectorSignaturePath: inspectorSignature,
        receiverName: v.representative,
        receiverSignaturePath: managerSignature,
        receiverIdNumber: '8001015009087',
        receiverDesignation: 'Manager',
        findings: 'The product on display carried no product name on the '
            'label and was removed from sale and seized.',
      );

  return [
    await rejection(
        'PMP-Rejection.pdf',
        FsaDocuments.pmpDirection,
        'Processed Meat Products',
        pmp,
        // The three deviations are the three rows the labelling checklist
        // flagged on this visit, under R.1283's own regulation numbers
        // (Ethan, 2026-10-08).
        const [
          DirectionDeviation(
              product: 'Cabanossi',
              nature: 'Date marking/batch identification not indicated on the '
                  'scale label.',
              regulation: 'Reg. 8(2)(a)'),
          DirectionDeviation(
              product: 'Cabanossi',
              nature: 'Country of origin not indicated on the scale label.',
              regulation: 'Reg. 8(2)(a)'),
          DirectionDeviation(
              product: 'Cabanossi',
              nature: 'Name and telephone number of the manufacturer, packer '
                  'or seller not indicated on the scale label.',
              regulation: 'Reg. 8(2)(b)'),
        ],
        email: 'manager@superspar-westwood.co.za',
        reg: 'R.1283 of 4 October 2019',
        actions: const [
          'Rejection issued and discussed with the Responsible Person on site.',
          '1. The affected product was removed from sale and placed on hold.',
          '2. Scale labels to be corrected to show the date marking/batch '
              'identification, the country of origin and the name and '
              'telephone number of the manufacturer, packer or seller.',
          '3. Corrected labelling to be submitted to the Agency for '
              'verification before the product is returned to sale.',
        ]),
    await rejection(
        'POULTRY-Rejection.pdf',
        FsaDocuments.poultryDirection,
        'Poultry Meat',
        pou,
        // One from the labelling checklist and one from the grading
        // checklist — the two sheets written on this visit
        // (Ethan, 2026-10-08).
        const [
          DirectionDeviation(
              product: 'Whole Frozen Chicken',
              nature: 'Physical address of the packer not indicated on the '
                  'inner container label.',
              regulation: 'Reg. 8(1)(i) and Reg. 11'),
          DirectionDeviation(
              product: 'Whole Frozen Chicken',
              nature: 'Breast fleshiness and skin damage outside the '
                  'tolerance for the grade declared on the label.',
              regulation: 'Reg. 10'),
        ],
        reg: 'R.946 of 27 March 1992, as amended'),
    await rejection(
        'EGG-Rejection.pdf',
        FsaDocuments.eggDirection,
        'Poultry Eggs',
        egg,
        const [
          DirectionDeviation(
              product: 'Large Grade 1 Eggs',
              nature: 'No "Best Before", "Best Quality Before" or "BB" '
                  'indication on the inner container.',
              regulation: 'Reg. 8(1)(f)'),
        ],
        reg: 'R.345 of 20 March 2020',
        photos: sixPhotos),
    await seizure(
        'PMP-Seizure.pdf', pmp, 'Processed Meat Products', '12 packs (3 kg)'),
    await seizure(
        'POULTRY-Seizure.pdf', pou, 'Poultry Meat', '20 birds (26 kg)'),
    await seizure('EGG-Seizure.pdf', egg, 'Poultry Eggs', '30 trays'),
  ];
}

/// The occurrence document (SOP-APS-009) written at the door.
Future<File> _occurrence(Directory out) {
  final v = visits['raw']!;
  return OccurrenceDocumentPdf.write(
    out: _out(out, 'Occurrence-Document.pdf'),
    facilityName: v.facility,
    facilityAddress: v.address,
    date: '1 September 2026',
    timeOfVisit: '10:15',
    registrationCode: 'ZA-PM-4471',
    inspectorName: inspector,
    description: 'On arrival the cold room door was found propped open and '
        'the display fridge was reading 9 °C. Boerewors and cabanossi on '
        'display carried no product name or batch code. The manager was '
        'told to close the cold room and to remove the unlabelled product '
        'from sale until it is labelled.',
    photoPaths: samplePhotos,
    ownerManagerDetails: v.representative,
    telephone: '045 838 1234',
    email: 'shop@mabovula.test',
    managerName: v.representative,
    inspectorSignaturePath: inspectorSignature,
    managerSignaturePath: managerSignature,
  );
}

Future<File> _requestForInvoice(Directory out) {
  final v = visits['raw']!;
  final visited = DateTime(2026, 9, 1, 9, 0);
  return InvoicePdf.write(
    InvoiceFormData(
      inspectorName: inspector,
      siteVisited: v.facility,
      siteManager: v.representative,
      productName: 'Boerewors, Cabanossi, Whole Frozen Chicken, Eggs',
      dateOfVisit: visited,
      timeStarted: '09:00',
      timeEnded: '12:00',
      pmpTicked: true,
      rawRmpTicked: true,
      eggsTicked: true,
      poultryTicked: true,
      sampleTakingTicked: true,
      normalHours: 3,
      overtimeHours: 0,
      sundayHours: 0,
      kilometres: 24,
      // The raw sample went for meat, fat, soya, starch, species and
      // calcium; the processed meat one for fat and protein.
      pmpFatTests: 1,
      pmpProteinTests: 1,
      pmpCalciumTests: 0,
      pmpPhysicalTests: 0,
      rawFatTests: 1,
      rawProteinTests: 1,
      rawSoyaTests: 1,
      rawStarchTests: 0,
      rawDnaTests: 1,
      rawCalciumTests: 1,
      managerSignaturePath: managerSignature,
      inspectorSignaturePath: inspectorSignature,
      signedAt: visited,
    ),
    outputPath: _out(out, 'RFI-Request-for-Invoice.pdf').path,
  );
}
