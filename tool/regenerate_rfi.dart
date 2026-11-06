// Rebuild one Request for Invoice form from corrected figures.
//
// An RFI is written on the handset at sign-off, so a value typed wrongly
// there is baked into the PDF the facility receives. Correcting the record
// on the server fixes what APS bills but not the document already issued,
// and that document is what the facility reads.
//
// This writes the form again through the app's own generator, so the result
// is the same layout the handset produces rather than an edited copy. The
// two signatures are passed back in: they belong to this form and were
// recovered from it.
//
//   dart run tool/regenerate_rfi.dart <out.pdf>
//
// The figures are given below rather than read from a database: this is a
// one-off correction to a named document, and spelling them out keeps what
// changed visible in review.
import 'dart:io';

import 'package:pdf/widgets.dart' as pw;

import 'package:fsa_app/core/documents/fsa_form_pdf.dart';
import 'package:fsa_app/features/invoicing/data/invoice_pdf.dart';
import 'package:fsa_app/features/invoicing/domain/invoice_form_data.dart';

Future<void> main(List<String> args) async {
  final out = args.isNotEmpty ? args.first : 'rfi.pdf';

  // The handset loads these through the asset bundle; a command-line run
  // has to hand them over itself or the form has no letterhead.
  FsaForm.useAssets(FsaFormAssets(
    regular: pw.Font.ttf(
        (await File('assets/fonts/Lato-Regular.ttf').readAsBytes())
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
    departmentLogo: pw.MemoryImage(
        await File('assets/images/dept_agriculture_logo.jpg').readAsBytes()),
  ));

  const sigDir = r'C:\temp\rfi';

  final form = InvoiceFormData(
    inspectorName: 'Jofred Steyn',
    siteVisited: 'Royal Stores Mandela Park',
    siteManager: 'Justin Julius',
    productName: 'Eggs, Label/Container, Certain Raw Processed Meat '
        'Products, Processed Meat Products',
    dateOfVisit: DateTime(2026, 10, 21),
    // The visit ran 15:30 to 16:05 and is billed as 15:30 to 16:00 —
    // Jofred asked for the form to read half past three to four, which is
    // the half hour he worked inside normal time, and it stops the five
    // minutes past four reading as overtime to the invoicing office
    // (Jofred via Ethan, 2026-10-29).
    timeStarted: '15:30',
    timeEnded: '16:00',
    pmpTicked: true,
    rawRmpTicked: true,
    eggsTicked: true,
    poultryTicked: true,
    sampleTakingTicked: true,
    // One hour, the minimum charge, and no overtime. The form billed it as
    // half an hour of normal time plus half an hour of overtime, because
    // the five minutes past four o'clock were rounded up into their own
    // half-hour band. The tariff printed on the form reads "a minimum of
    // one hour will be charged. Thereafter time will be charged in half
    // hour segments" — under an hour is one hour, charged where the
    // inspection was worked, so an inspection that ended at 16:05 carries
    // no overtime at all.
    normalHours: 1,
    overtimeHours: 0,
    sundayHours: 0,
    kilometres: 80,
    // The laboratory work is unchanged: two fat and two protein tests on
    // the raw processed meat samples.
    rawFatTests: 2,
    rawProteinTests: 2,
    managerSignaturePath: '$sigDir${Platform.pathSeparator}sig1.png',
    inspectorSignaturePath: '$sigDir${Platform.pathSeparator}sig2.png',
    signedAt: DateTime(2026, 10, 21),
  );

  final file = await InvoicePdf.write(form, outputPath: out);
  stdout.writeln('wrote ${file.path} (${await file.length()} bytes)');
}
