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

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_checklist_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/eggs/data/egg_weighing_checklist_pdf.dart';
import 'package:fsa_app/features/invoicing/data/invoice_pdf.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_form_data.dart';
import 'package:fsa_app/features/rawrmp/data/composition_checklist_pdf.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';

const inspector = 'CINGA NGONGO';
final generatedAt = DateTime(2026, 9, 1, 11, 30);

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
    batch: 'none',
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

const inspectionDate = '2026/09/01';
const packedDate = '2026/08/31';

Future<void> main(List<String> args) async {
  final out = Directory(args.isEmpty ? 'build/documents' : args.first);
  await out.create(recursive: true);

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
  ));

  final written = <File>[
    ...await _raw(out),
    ...await _pmp(out),
    ...await _poultry(out),
    ...await _eggs(out),
    await _requestForInvoice(out),
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
        standard: ((r['min_lettering_height'] ?? '').toString().isEmpty)
            ? '-'
            : '${r['min_lettering_height']}mm',
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
    out: File('${out.path}/RAW-Container-and-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.rawLabelling,
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
    authorisedPersonName: v.representative,
    comments: 'The country of origin is not indicated on the scale label, and '
        'the batch code is absent from the container marking.',
    remarks: 'The marking on the container is in contravention to R.2410 of '
        '26 August 2022 (Certain Raw Processed Meat Products Regulation)',
    documentTitle: 'Container and Labelling Verification Checklist',
  );

  final sampling = await FsaChecklistPdf.write(
    out: File('${out.path}/RAW-Sampling-Checklist.pdf'),
    control: FsaDocuments.rawSampling,
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
        FsaChecklistRow(requirement: 'Storage method', value: 'Chilled'),
        FsaChecklistRow(
            requirement: 'Calcium content test requested (MRM only)', value: 'Yes'),
        FsaChecklistRow(requirement: 'Delivery method', value: 'Courier'),
        FsaChecklistRow(requirement: 'Waybill number', value: 'AWB-773311'),
      ]),
    ],
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    comments: 'Sample drawn from the display fridge in the presence of the manager.',
    remarks: 'Sample submitted for compositional analysis under R.2410.',
    documentTitle: 'Sampling Checklist',
  );

  final answers = CompositionChecklist.blank();
  answers[0] = const CompositionAnswer(
      deviation: false, contributionGrams: '100', remarks: 'Beef only');
  answers[1] = const CompositionAnswer(deviation: false);
  answers[2] = const CompositionAnswer(
      deviation: true, contributionGrams: '3', remarks: 'Soya protein found');
  answers[4] = const CompositionAnswer(
      deviation: true, contributionGrams: '6', remarks: 'MRM present, not declared');
  answers[8] = const CompositionAnswer(deviation: false, contributionGrams: '88');
  final composition = await CompositionChecklistPdf.write(
    out: File('${out.path}/RAW-Compositional-Requirements-Checklist.pdf'),
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
    authorisedPersonName: v.representative,
  );
  return [labelling, sampling, composition];
}

// ------------------------------------------------------------------ pmp

Future<List<File>> _pmp(Directory out) async {
  final v = visits['pmp']!;
  Future<List<FsaChecklistRow>> rows(String section,
          {FsaDeviation Function(int)? answer}) =>
      _rows('pmp_reference.json', 'checklist_items', (r) => r['section'] == section,
          answer: answer);

  final labelling = await FsaChecklistPdf.write(
    out: File('${out.path}/PMP-Container-and-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.pmpLabelling,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: [..._right(v), (label: 'Primary Sample Size', value: '218g')],
    sections: [
      FsaChecklistSection(
          title: 'MARKING REQUIREMENTS',
          rows: await rows('marking', answer: _notApplicable)),
      FsaChecklistSection(
          title: 'CONTAINERS & OUTER CONTAINERS', rows: await rows('container')),
      FsaChecklistSection(
          title: 'SCALE LABEL REQUIREMENTS',
          rows: await rows('scale', answer: _failing({4}))),
      FsaChecklistSection(
          title: 'DISPLAY FRIDGE LABEL REQUIREMENTS',
          rows: await rows('fridge', answer: _notApplicable)),
      FsaChecklistSection(
          title: 'NOTICE BOARDS, SIGNAGE, AVERTISEMENTS, ETC.',
          rows: await rows('notice', answer: _notApplicable)),
    ],
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    comments: 'The country of origin is not indicated on the scale label.',
    remarks: 'The marking on the container is in contravention to R.1283 of '
        '4 October 2019 (Processed Meat Products Regulation)',
    documentTitle: 'Container and Labelling Verification Checklist',
  );

  final sampling = await FsaChecklistPdf.write(
    out: File('${out.path}/PMP-Sampling-Checklist.pdf'),
    control: FsaDocuments.pmpSampling,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v, dateLabel: 'Date of Sampling:'),
    rightFields: [..._right(v), (label: 'Primary Sample Size', value: '218g')],
    sections: const [
      FsaChecklistSection(title: 'SAMPLE DETAILS', rows: [
        FsaChecklistRow(requirement: 'Internal sample number', value: 'PMP-2026-207'),
        FsaChecklistRow(requirement: 'Primary sample size', value: '218 g'),
        FsaChecklistRow(requirement: 'Sample size taken', value: '400 g'),
        FsaChecklistRow(requirement: 'Laboratory', value: 'Deltamune Laboratories'),
        FsaChecklistRow(requirement: 'Storage method', value: 'Chilled'),
        FsaChecklistRow(
            requirement: 'Recipe/ingredient list available', value: 'Yes'),
        FsaChecklistRow(requirement: 'Delivery method', value: 'Hand delivered'),
        FsaChecklistRow(requirement: 'Waybill number', value: '-'),
      ]),
    ],
    inspectorName: inspector,
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
    out: File('${out.path}/POULTRY-Labelling-Verification-Checklist.pdf'),
    control: FsaDocuments.poultryLabelling,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: [
      FsaChecklistSection(
          title: 'LETTERING: INNER CONTAINER',
          rows: await rows('label_inner', answer: _failing({2}))),
      FsaChecklistSection(
          title: 'LETTERING: OUTER CONTAINER', rows: await rows('label_outer')),
      FsaChecklistSection(
          title: 'CONTAINER REQUIREMENTS', rows: await rows('container')),
    ],
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    comments: 'The packer\'s physical address is not indicated on the inner '
        'container label.',
    remarks: 'The marking on the container is in contravention to R.946 of '
        '27 March 1992, as amended (Poultry Meat Regulation)',
    documentTitle: 'Labelling Verification Checklist',
  );

  final grading = await FsaChecklistPdf.write(
    out: File('${out.path}/POULTRY-Classification-and-Grading-Checklist.pdf'),
    control: FsaDocuments.poultryGrading,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: [
      FsaChecklistSection(
          title: 'QUALITY STANDARDS',
          rows: await rows('grading', answer: _failing({1, 6}))),
      FsaChecklistSection(
          title: 'STANDARDS FOR PORTIONS', rows: await rows('portion')),
      FsaChecklistSection(
          title: 'PACKING REQUIREMENTS', rows: await rows('pack')),
    ],
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    comments: 'Breast fleshiness and skin damage outside the tolerance for the '
        'grade declared on the label.',
    remarks: 'The consignment is in contravention to R.946 of 27 March 1992, '
        'as amended (Poultry Meat Regulation)',
    documentTitle: 'Classification and Grading Checklist',
  );

  final quid = await FsaChecklistPdf.write(
    out: File('${out.path}/POULTRY-QUID-Determination-Checklist.pdf'),
    control: FsaDocuments.poultryQuid,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: _left(v),
    rightFields: _right(v),
    sections: const [
      FsaChecklistSection(title: 'CHILLING METHOD', rows: [
        FsaChecklistRow(requirement: 'Chilling method declared', value: 'Water'),
        FsaChecklistRow(
            requirement: 'Permissible water content for the method',
            value: '8.0 %'),
      ]),
      FsaChecklistSection(title: 'DETERMINATION', rows: [
        FsaChecklistRow(requirement: 'Number of carcasses sampled', value: '20'),
        FsaChecklistRow(requirement: 'Average initial carcass mass', value: '1 412 g'),
        FsaChecklistRow(requirement: 'Average final carcass mass', value: '1 561 g'),
        FsaChecklistRow(requirement: 'Water uptake determined', value: '10.5 %'),
        FsaChecklistRow(
            requirement: 'Within the permissible limit', value: 'NO'),
      ]),
    ],
    inspectorName: inspector,
    authorisedPersonName: v.representative,
    comments: 'Water uptake of 10.5% exceeds the 8.0% permitted for water '
        'chilling.',
    remarks: 'The consignment is in contravention to R.946 of 27 March 1992, '
        'as amended (Poultry Meat Regulation)',
    documentTitle: 'QUID Determination Checklist',
  );
  return [labelling, grading, quid];
}

// ----------------------------------------------------------------- eggs

Future<List<File>> _eggs(Directory out) async {
  final v = visits['egg']!;
  final weighing = await EggWeighingChecklistPdf.write(
    out: File('${out.path}/EGG-Weighing-Checklist.pdf'),
    facilityName: v.facility,
    facilityAddress: v.address,
    dateOfInspection: inspectionDate,
    representative: v.representative,
    facilityType: v.type,
    producerSupplier: v.producer,
    batchNumber: v.batch,
    bestBefore: '2026/09/14',
    declaredSize: 'Large',
    declaredGrade: 'Grade 1',
    traySize: '12-Pack',
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
    authorisedPersonName: v.representative,
    comments: 'Two eggs under the declared minimum mass. Consignment '
        'downgraded and a direction served on the retailer.',
  );

  final labelling = await FsaChecklistPdf.write(
    out: File('${out.path}/EGG-Labeling-Checklist.pdf'),
    control: FsaDocuments.eggLabelling,
    facilityName: v.facility,
    generatedAt: generatedAt,
    leftFields: [
      (label: 'Date of Inspection:', value: inspectionDate),
      (label: 'Facility Name:', value: v.facility),
      (label: 'Site Representative:', value: v.representative),
      (label: 'Tray Packaging Size', value: '12-Pack'),
    ],
    rightFields: [
      (label: 'Producer/Supplier', value: v.producer),
      (label: 'Batch Number', value: v.batch),
      (label: 'Best Before Date', value: '2026/09/14'),
      (label: 'Type of Facility', value: v.type),
    ],
    sections: [
      FsaChecklistSection(
          title: 'MARKING OF CONTAINERS',
          rows: await _rows('eggs_reference.json', 'requirements',
              (r) => r['kind'] == 'label_pack',
              answer: _failing({3}))),
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
      managerSignaturePath: '',
      inspectorSignaturePath: '',
      signedAt: visited,
    ),
    outputPath: '${out.path}/RFI-Request-for-Invoice.pdf',
  );
}
