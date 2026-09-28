// Renders the Agency's compliance documents for one worked example, without
// a phone or a Flutter engine.
//
// The forms are built by the same code the handset uses; only the fonts and
// the logo come from disk instead of the asset bundle. Run it with
//
//     dart run tool/generate_documents.dart <output directory>
//
// It exists so the documents can be produced — and checked against the
// Agency's own copies — on a machine where the Flutter test runner cannot
// start.

import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_checklist_pdf.dart';
import 'package:fsa_app/core/documents/fsa_documents.dart';
import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/eggs/data/egg_weighing_checklist_pdf.dart';
import 'package:fsa_app/features/rawrmp/data/composition_checklist_pdf.dart';
import 'package:fsa_app/features/rawrmp/domain/composition_checklist.dart';

/// The worked example: one visit to a butchery, inspected today.
const facility = 'Mabovula Butchery - Queenstown';
const address = '73 Robinson Queenstown 5320';
const representative = 'S. Mabovula';
const position = 'Butchery Manager';
const inspector = 'CINGA NGONGO';
const producer = 'Karoo Meat Producers';
const product = 'Boerewors';
const batch = '4471';
const packedDate = '2026/08/31';
const inspectionDate = '2026/09/01';
final generatedAt = DateTime(2026, 9, 1, 11, 30);

Future<void> main(List<String> args) async {
  final out = Directory(args.isEmpty ? 'build/documents' : args.first);
  await out.create(recursive: true);

  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes()).buffer.asByteData()),
    bold: pw.Font.ttf(
        (await File('assets/fonts/Lato-Bold.ttf').readAsBytes()).buffer.asByteData()),
    logo: pw.MemoryImage(await File('assets/images/FSA_Logo.png').readAsBytes()),
  ));

  final written = <File>[
    await _rawLabelling(out),
    await _rawSampling(out),
    await _composition(out),
    await _eggWeighing(out),
  ];

  for (final file in written) {
    stdout.writeln('${file.path}  (${await file.length()} bytes)');
  }
}

/// SOP-APS-RAW-001 — the container and labelling verification checklist.
Future<File> _rawLabelling(Directory out) {
  FsaChecklistRow row(String requirement, String regulation, String std,
          FsaDeviation deviation) =>
      FsaChecklistRow(
          requirement: requirement,
          regulation: regulation,
          standard: std,
          deviation: deviation);

  return FsaChecklistPdf.write(
    out: File('${out.path}/FSA-Mabovula-Butchery-Container-and-Labelling-'
        'Verification-Checklist.pdf'),
    control: FsaDocuments.rawLabelling,
    facilityName: facility,
    generatedAt: generatedAt,
    leftFields: const [
      (label: 'Date of Inspection:', value: inspectionDate),
      (label: 'Facility Name:', value: facility),
      (label: 'Reason for Inspection:', value: 'Inspection'),
      (label: 'Manufactured/Packed Date', value: packedDate),
    ],
    rightFields: const [
      (label: 'Producer', value: producer),
      (label: 'Product Name Inspected', value: product),
      (label: 'Batch Number', value: batch),
    ],
    sections: [
      FsaChecklistSection(title: 'MARKING REQUIREMENTS', rows: [
        row('Prescribed Particulars', '[Reg. 7(1)]', '-', FsaDeviation.no),
        row('Appropriate Product Name', '[Reg. 7(1)(a) & 8]', '3.0mm',
            FsaDeviation.no),
        row('Additions to Appropriate Product Name', '[Reg. 7(1)(b) & 9]',
            '3.0mm', FsaDeviation.no),
        row('Name and Address', '[Reg. 7(1)(c)]', '1.0mm', FsaDeviation.no),
        row('Date Marking/Batch Code/Batch Number', '[Reg. 7(1)(d) & 10]',
            '1.0mm', FsaDeviation.yes),
        row('Country of Origin', '[Reg. 7(1)(e) & 11]', '1.0mm',
            FsaDeviation.yes),
        row('Restricted Particulars (section 6 of APS Act)', '[Reg. 13]', '-',
            FsaDeviation.no),
      ]),
      FsaChecklistSection(title: 'CONTAINERS & OUTER CONTAINERS', rows: [
        row('Suitable for the Purpose', '[Reg. 6(1)(a)(i)]', '-',
            FsaDeviation.no),
        row('Protect the contents thereof', '[Reg. 6(1)(a)(ii)]', '-',
            FsaDeviation.no),
        row('Will not impart any undesirable flavour',
            '[Reg. 6(1)(a)(iii & 6(2)(b)]', '-', FsaDeviation.no),
        row('Be strong, will not damage or deform',
            '[Reg. 6(1)(b) & 6(2)(a)]', '-', FsaDeviation.no),
        row('Be Intact', '[Reg. 6(1)(c) & 6(2)(a)]', '', FsaDeviation.no),
        row('Closed Properly', '[Reg. 6(1)(d)]', '-', FsaDeviation.no),
      ]),
      FsaChecklistSection(title: 'SCALE LABEL REQUIREMENTS', rows: [
        row('Prescribed Particulars', '[Reg. 7(2) & (a)]', '-',
            FsaDeviation.no),
        row('Appropriate Product Name', '[Reg. 7(2) & (a)]', '1.0mm',
            FsaDeviation.no),
        row('Additions to Appropriate Product Name', '[Reg. 7(2) & (a)]',
            '1.0mm', FsaDeviation.no),
        row('Name and Address', '[Reg. 7(2)(b)]', '1.0mm', FsaDeviation.no),
        row('Date Marking/Batch Code/Batch Number', '[Reg. 7(2) & (a)]',
            '1.0mm', FsaDeviation.no),
        row('Country of Origin', '[Reg. 7(2) & (a)]', '1.0mm',
            FsaDeviation.yes),
        row('Restricted Particulars (section 6 of APS Act)', '[Reg 14]', '-',
            FsaDeviation.no),
      ]),
      FsaChecklistSection(
          title: 'DISPLAY FRIDGE LABEL REQUIREMENTS',
          rows: [
            row('Appropriate product name - in immediate vacinity of each '
                'class.', '[Reg. 12]', '-', FsaDeviation.notApplicable),
          ]),
      FsaChecklistSection(
          title: 'NOTICE BOARDS, SIGNAGE, AVERTISEMENTS, ETC.',
          rows: [
            row('May not convey or create, directly or by implication, a '
                'false or misleading impressions.', '[Reg. 13]', '-',
                FsaDeviation.notApplicable),
          ]),
    ],
    inspectorName: inspector,
    authorisedPersonName: representative,
    comments: 'The country of origin is not indicated on the scale label, and '
        'the batch code is absent from the container marking.',
    remarks: 'The marking on the container is in contravention to R.2410 of '
        '26 August 2022 (Certain Raw Processed Meat Products Regulation)',
    documentTitle: 'Container and Labelling Verification Checklist',
  );
}

/// SOP-APS-RAW-002 — the sampling checklist.
Future<File> _rawSampling(Directory out) => FsaChecklistPdf.write(
      out: File('${out.path}/FSA-Mabovula-Butchery-Sampling-Checklist.pdf'),
      control: FsaDocuments.rawSampling,
      facilityName: facility,
      generatedAt: generatedAt,
      leftFields: const [
        (label: 'Date of Sampling:', value: inspectionDate),
        (label: 'Facility Name:', value: facility),
        (label: 'Reason for Inspection:', value: 'Inspection'),
        (label: 'Manufactured/Packed Date', value: packedDate),
      ],
      rightFields: const [
        (label: 'Producer', value: producer),
        (label: 'Product Name Inspected', value: product),
        (label: 'Batch Number', value: batch),
      ],
      sections: const [
        FsaChecklistSection(title: 'SAMPLE DETAILS', rows: [
          FsaChecklistRow(
              requirement: 'Internal sample number', value: 'RMP-2026-118'),
          FsaChecklistRow(requirement: 'Sample size taken', value: '500 g'),
          FsaChecklistRow(
              requirement: 'Laboratory', value: 'Deltamune Laboratories'),
          FsaChecklistRow(
              requirement: 'Laboratory testing category',
              value: 'Composition & Species'),
          FsaChecklistRow(requirement: 'Storage method', value: 'Chilled'),
          FsaChecklistRow(
              requirement: 'Calcium content test requested (MRM only)',
              value: 'Yes'),
          FsaChecklistRow(requirement: 'Delivery method', value: 'Courier'),
          FsaChecklistRow(
              requirement: 'Waybill number', value: 'AWB-773311'),
        ]),
      ],
      inspectorName: inspector,
      authorisedPersonName: representative,
      comments: 'Sample drawn from the display fridge in the presence of the '
          'manager.',
      remarks: 'Sample submitted for compositional analysis under R.2410.',
      documentTitle: 'Sampling Checklist',
    );

/// SOP-APS-RAW-003 — the compositional requirements checklist.
Future<File> _composition(Directory out) {
  final answers = CompositionChecklist.blank();
  answers[0] = const CompositionAnswer(
      deviation: false, contributionGrams: '100', remarks: 'Beef only');
  answers[1] = const CompositionAnswer(deviation: false);
  answers[2] = const CompositionAnswer(
      deviation: true, contributionGrams: '3', remarks: 'Soya protein found');
  answers[4] = const CompositionAnswer(
      deviation: true,
      contributionGrams: '6',
      remarks: 'MRM present, not declared');
  answers[8] =
      const CompositionAnswer(deviation: false, contributionGrams: '88');
  return CompositionChecklistPdf.write(
    out: File('${out.path}/FSA-Mabovula-Butchery-Compositional-Checklist.pdf'),
    facilityName: facility,
    facilityAddress: address,
    dateOfSampling: inspectionDate,
    siteRepresentative: representative,
    representativePosition: position,
    facilityType: 'Butchery',
    productName: product,
    batchNumber: batch,
    manufacturedPackedDate: packedDate,
    answers: answers,
    comments: 'Mechanically recovered meat and vegetable protein present in a '
        'product labelled as pure beef boerewors. Producer to be directed to '
        'correct the formulation and the label.',
    inspectorName: inspector,
    authorisedPersonName: representative,
  );
}

/// SOP-APS-EGGS-003 — the egg weighing checklist.
Future<File> _eggWeighing(Directory out) => EggWeighingChecklistPdf.write(
      out: File('${out.path}/FSA-Mabovula-Butchery-Egg-Weighing-'
          'Checklist.pdf'),
      facilityName: facility,
      facilityAddress: address,
      dateOfInspection: inspectionDate,
      representative: representative,
      facilityType: 'Butchery',
      producerSupplier: 'Nulaid Farms',
      batchNumber: 'EG-4471',
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
            deviations: i % 5 == 0
                ? const ['Large - <= 2g of Min. Weight']
                : const [],
          ),
      ],
      inspectorName: inspector,
      authorisedPersonName: representative,
      comments: 'Two eggs under the declared minimum mass. Consignment '
          'downgraded and a direction served on the retailer.',
    );
