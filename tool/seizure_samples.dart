import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/core/documents/seizure_pdf.dart';

/// Draws the seizure form as the handset draws it today, one per commodity.
///
/// The seizures already filed with the office were captured over several
/// weeks and the sheet was redesigned on 12 October, so the filed copies
/// show the layout of the day they were served rather than the layout an
/// inspector would get now — a poultry seizure from 2 October looks nothing
/// like an egg seizure from today, and the difference is the date, not the
/// commodity. There is one builder behind all four, so the only honest way
/// to compare commodities is to draw them from the same code
/// (Ethan, 2026-10-12).
///
/// The wording of each deviation is taken from a seizure actually served,
/// so the regulation and the Annexure reference are the real ones.
///
///   dart run tool/seizure_samples.dart <output directory>
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: seizure_samples.dart <output directory>');
    exitCode = 2;
    return;
  }
  final dir = Directory(args.first)..createSync(recursive: true);
  final issued = DateTime(2026, 10, 12, 11, 20);

  // The same fonts and letterhead the handset draws with, so the sample is
  // the sheet an inspector would serve and not an approximation of it.
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
            .buffer
            .asByteData()),
    bold: pw.Font.ttf((await File('assets/fonts/Lato-Bold.ttf').readAsBytes())
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
    departmentLogo: pw.MemoryImage(
        await File('assets/images/dept_agriculture_logo.jpg').readAsBytes()),
  ));

  final samples = <({String file, String commodity, SeizedProduct product})>[
    (
      file: 'CURRENT - EGG.pdf',
      commodity: 'Eggs',
      product: const SeizedProduct(
        productName: 'Eggs',
        productClass: 'Size: Not indicated, Grade: Not indicated',
        quantity: '12 x 18-pack',
        regulation: 'R.541 of 30 June 2017',
        natureOfDeviation:
            'Seizure under FSA-SOP-APS-001 Annexure D: The size designation '
            'is not indicated on the pack (Reg. 10).; The grade designation '
            'is not indicated on the pack (Reg. 10).',
      ),
    ),
    (
      file: 'CURRENT - POULTRY.pdf',
      commodity: 'Poultry Meat',
      product: const SeizedProduct(
        productName: 'Whole Bird',
        productClass: 'Grade: Not indicated',
        quantity: '24 units',
        regulation: 'R.946 of 27 March 1992',
        natureOfDeviation:
            'Seizure under FSA-SOP-APS-001 Annexure C: the grade designation '
            'is not indicated at all (Reg. 10).',
      ),
    ),
    (
      file: 'CURRENT - RAW RMP.pdf',
      commodity: 'Certain Raw Processed Meat Products',
      product: const SeizedProduct(
        productName: 'Econo value burger',
        productClass: 'Class: Not indicated',
        quantity: '30 x 1 kg',
        regulation: 'R.2410 of 26 August 2022',
        natureOfDeviation:
            'Seizure under FSA-SOP-APS-001 Annexure A: the product name is '
            'not indicated at all.',
      ),
    ),
    (
      file: 'CURRENT - PMP.pdf',
      commodity: 'Processed Meat Products',
      product: const SeizedProduct(
        productName: 'Russian Sausage',
        productClass: 'Class: Not indicated',
        quantity: '15 x 500 g',
        regulation: 'R.1283 of 4 October 2019',
        natureOfDeviation:
            'Seizure under FSA-SOP-APS-001 Annexure B: the product name is '
            'not indicated at all.',
      ),
    ),
  ];

  for (final s in samples) {
    final out = await SeizurePdf.write(
      out: File('${dir.path}/${s.file}'),
      clientName: 'Sample Store',
      clientAddress: '1 Example Road, Pretoria',
      clientTelephone: '012 345 6789',
      clientFax: '',
      clientEmail: 'manager@example.co.za',
      inspectionPoint: 'Retailer/Distr. Center',
      products: [s.product],
      issuedAt: issued,
      issuedPlace: 'Sample Store',
      inspectorName: 'Inspector Name',
      receiverName: 'Store Manager',
      receiverIdNumber: '',
      receiverDesignation: 'Manager',
      // No findings note and no signatures: a sample carrying either would
      // not be the sheet an inspector serves, and the point of these is to
      // show the real layout.
    );
    stdout.writeln('${s.commodity.padRight(38)} -> ${out.path}');
  }
}
