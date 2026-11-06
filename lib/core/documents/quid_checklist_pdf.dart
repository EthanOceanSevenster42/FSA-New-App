import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fsa_form_pdf.dart';

/// One carcass on the chilling table: what it weighed going in, coming out,
/// and what it therefore took up.
class QuidCarcass {
  const QuidCarcass({
    required this.number,
    this.initialMassG = '',
    this.finalMassG = '',
    this.percent = '',
  });

  final String number;
  final String initialMassG;
  final String finalMassG;

  /// Pick up for the chilling table, QUID for the determination table.
  final String percent;
}

/// One carcass under the injector that ran it, for the determination.
class QuidDeterminedCarcass {
  const QuidDeterminedCarcass({
    required this.sampleNumber,
    this.initialMassG = '',
    this.finalMassG = '',
    this.setPercent = '',
    this.calculatedPercent = '',
  });

  final String sampleNumber;
  final String initialMassG;

  /// The mass off the process, which QUID is taken as a proportion of.
  final String finalMassG;

  /// What the plant says the injector is set to, repeated on every row as
  /// the original's table repeats it.
  final String setPercent;

  /// What this carcass actually gained.
  final String calculatedPercent;
}

/// One carcass on the injector table.
class QuidInjectorCarcass {
  const QuidInjectorCarcass({
    required this.number,
    this.beforeMassG = '',
    this.afterMassG = '',
    this.gainG = '',
    this.ratePercent = '',
  });

  final String number;
  final String beforeMassG;
  final String afterMassG;
  final String gainG;
  final String ratePercent;
}

/// One injector on the sheet: the carcasses it injected, with their
/// injection rate, beside the carcasses its QUID was determined on.
///
/// The inspectors' paper sheet (the Rainbow Chickens example, 23 September
/// 2026) is ruled this way — one block per injector, its "Injector Name"
/// table on the left, its "Determination of QUID" table on the right with
/// the injector's setting in the QUID column heading, and an average under
/// each. The finding is made per injector, because a plant running three
/// injectors can have two in order and one over the limit, and a pooled
/// table hides exactly that. The sheet used to print one injection table
/// for every carcass under a single name and only group the determination.
class QuidInjectorBlock {
  const QuidInjectorBlock({
    required this.name,
    this.setPercent = '',
    this.injection = const [],
    this.averageRatePercent = '',
    this.determination = const [],
    this.averageQuidPercent = '',
    this.verdict = '',
    this.passes,
  });

  final String name;

  /// What the plant says the injector is set to — the paper's "QUID 15%"
  /// column heading.
  final String setPercent;
  final List<QuidInjectorCarcass> injection;
  final String averageRatePercent;
  final List<QuidDeterminedCarcass> determination;
  final String averageQuidPercent;

  /// 'PASS', 'FAIL', or why no finding can be made yet.
  final String verdict;

  /// Null while there are too few carcasses to judge on.
  final bool? passes;
}

/// The QUID determination checklist — SOP-APS-PM-001.
///
/// Laid out as the Agency's own report does it (FSA-WEB's
/// `PoultryQUIDInspectionChecklistReport` with its water-chilling,
/// air-chilling and injector sub-reports): an information block, the chilling
/// table for the method declared, the injector table where the product is
/// injected, and the determination of QUID — each a carcass-by-carcass table
/// with its own average underneath.
///
/// The general checklist layout does not fit this document. Its columns are
/// requirement / regulation / std / deviation, and a QUID sheet is
/// measurements: a carcass number and three masses per row.
/// One "Verification of Records" entry as the sheet prints it, with
/// whether its document was photographed on the handset.
class QuidVerifiedRecord {
  const QuidVerifiedRecord({
    required this.date,
    required this.name,
    required this.verified,
    required this.deviationPresent,
    required this.comment,
    required this.photographed,
  });
  final String date;
  final String name;
  final String verified;
  final String deviationPresent;
  final String comment;
  final String photographed;
}

abstract final class QuidChecklistPdf {
  static Future<File> write({
    required File out,
    required FsaDocControl control,
    required String facilityName,
    required String dateOfInspection,
    required String reasonForInspection,
    required String registrationNumber,
    required String portionType,
    String productName = '',
    required String allowableQuidPercent,
    required bool isWaterChilled,
    required List<QuidCarcass> chilling,
    required String averagePickupPercent,

    /// Whether the average pick-up is inside Reg. 4(2)'s absorbed-moisture
    /// limit on a water-chilled line. Null where nothing was weighed, or
    /// where the line is air chilled and the limit does not apply.
    bool? waterChillWithinLimit,

    /// That limit as the column heading prints it — "7". Supplied by the
    /// caller so the rule lives with the rest of the QUID arithmetic and
    /// not in the layout.
    String waterChillLimitPercent = '7',
    required String iterationNumber,

    /// One block per injector on the set-up list: its injection-rate table
    /// beside its determination table, as the paper sheet rules it.
    required List<QuidInjectorBlock> injectors,
    required String averageQuidPercent,

    /// The consignment totals behind that average: what the carcasses
    /// weighed off the line, off the process, and the difference.
    required String quidInitialMassG,
    required String quidAfterMassG,
    required String quidGainMassG,
    required String verificationDate,
    required String documentName,
    required String documentVerified,
    required String documentDeviationPresent,
    required String documentDeviationComment,

    /// Every record verified at the line. When given, these are printed as
    /// a list in place of the single document fields above, which is what
    /// a record from before the list holds.
    List<QuidVerifiedRecord> verificationRecords = const [],

    /// The rejection the weighing ended in — empty when it ended in none.
    String rejectionReason = '',
    String rejectionRemarks = '',
    String rejectionCorrectBy = '',
    String rejectionAction = '',

    /// 'YES' or 'NO' where the determination can be read against the
    /// allowable figure, empty where one of the two is missing. The sheet
    /// states the verdict rather than leaving the office to compare two
    /// numbers printed a page apart.
    required String withinPermissibleLimit,
    required String comments,
    required String remarks,
    required String inspectorName,
    required String authorisedPersonName,
    String inspectorSignaturePath = '',
    String authorisedPersonSignaturePath = '',
    DateTime? generatedAt,
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.signature(inspectorSignaturePath);
    final authorisedSignature =
        await FsaForm.signature(authorisedPersonSignaturePath);
    final doc = pw.Document();

    pw.Widget head(String v) => FsaForm.cell(v, a, isBold: true, size: 7);
    pw.Widget body(String v) => FsaForm.cell(v, a, size: 7.5);

    // Header rows are shaded, as the Request for Invoice shades its own: a
    // table of measurements reads faster when the headings are not the same
    // weight of white as the figures under them.
    pw.Widget table(List<String> columns, List<List<String>> rows) => pw.Table(
          border: FsaForm.border(),
          columnWidths: {
            for (var i = 0; i < columns.length; i++)
              i: pw.FlexColumnWidth(i == 0 ? 1.2 : 1.0),
          },
          children: [
            pw.TableRow(
              // Repeated where a table runs onto the next page: a column of
              // masses with no heading over it cannot be read.
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [for (final c in columns) head(c)],
            ),
            for (final r in rows)
              pw.TableRow(children: [for (final v in r) body(v)]),
          ],
        );

    /// A table's average, printed under it as the report does.
    pw.Widget average(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3, bottom: 6),
          child: pw.Row(children: [
            pw.Text(label, style: a.text(isBold: true, size: 7)),
            pw.SizedBox(width: 6),
            FsaForm.box(value, a, width: 70),
          ]),
        );

    /// A table heading inside an injector block, ruled like the paper's.
    pw.Widget caption(String v) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            border: pw.Border.all(width: 0.6, color: PdfColors.grey800),
          ),
          child: pw.Text(v, style: a.text(isBold: true, size: 7)),
        );

    /// One injector: the injection-rate table on the left, the
    /// determination on the right, each with its own average, as the
    /// inspectors' paper sheet pairs them.
    pw.Widget injectorBlock(QuidInjectorBlock block) {
      final quidHeading = block.setPercent.trim().isEmpty
          ? 'QUID (%)'
          : 'QUID ${block.setPercent.trim()}%';
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 11,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  caption('INJECTOR NAME:  ${block.name}'),
                  if (block.injection.isEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('No carcasses weighed on this injector.',
                          style: a.text(size: 7.5)),
                    )
                  else
                    table(
                      const [
                        'SAMPLE NO',
                        'BEFORE (g)',
                        'AFTER (g)',
                        'GAIN (g)',
                        'INJECTION RATE (%)',
                      ],
                      [
                        // Samples 1 to 5 within the injector (Ethan,
                        // 2026-10-04), not the carcass's number in the set.
                        for (final (i, c) in block.injection.indexed)
                          [
                            '${i + 1}',
                            c.beforeMassG,
                            c.afterMassG,
                            c.gainG,
                            c.ratePercent,
                          ],
                      ],
                    ),
                  average('AVERAGE:', block.averageRatePercent),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 9,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  caption('DETERMINATION OF QUID'),
                  if (block.determination.isEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text('No determination on this injector.',
                          style: a.text(size: 7.5)),
                    )
                  else
                    table(
                      [
                        'SAMPLE #',
                        'INITIAL MASS (g)',
                        'FINAL MASS (g)',
                        quidHeading,
                      ],
                      [
                        for (final (i, c) in block.determination.indexed)
                          [
                            '${i + 1}',
                            c.initialMassG,
                            c.finalMassG,
                            c.calculatedPercent,
                          ],
                      ],
                    ),
                  average('AVERAGE:', block.averageQuidPercent),
                  if (block.verdict.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Text(block.verdict,
                          style: a.text(
                              isBold: block.passes == false, size: 7)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final blocks = <pw.Widget>[
      FsaForm.heading(
          isWaterChilled ? 'Water Chilling:' : 'Air Chilling:', a),
      if (chilling.isEmpty)
        pw.Text('No carcasses weighed.', style: a.text(size: 7.5))
      else ...[
        table(
          [
            'CARCASS NUMBER',
            'INITIAL MASS (g)',
            'FINAL MASS (g)',
            // The threshold the method is read against is part of the
            // column heading on the Agency's sheet, on both methods.
            //
            // Water chilling is read against absorbed moisture, not
            // against QUID (Neo Noe, 2026-10-19): Reg. 4(2) allows less
            // than 7% pick-up whatever the product's allowable QUID is.
            // The sheet used to print the QUID figure over this column,
            // which on a portion line read as though 15% were allowed.
            if (isWaterChilled)
              '> $waterChillLimitPercent% ABSORBED MOISTURE '
                  '(PICK UP) [Reg. 4(2)]'
            else
              '> $allowableQuidPercent% PICK UP',
          ],
          [
            for (final c in chilling)
              [c.number, c.initialMassG, c.finalMassG, c.percent],
          ],
        ),
        average('AVERAGE PICK UP:', averagePickupPercent),
        // Stated on the sheet rather than left to the office to compare
        // two numbers, as the QUID determination below already is.
        if (isWaterChilled && waterChillWithinLimit != null)
          average('ABSORBED MOISTURE WITHIN THE PERMISSIBLE LIMIT '
              '(< $waterChillLimitPercent%):',
              waterChillWithinLimit ? 'YES' : 'NO'),
      ],
      if (iterationNumber.trim().isNotEmpty)
        average('ITERATION NUMBER:', iterationNumber),
      if (injectors.isNotEmpty) ...[
        // Each injector on a page of its own (Ethan, 2026-10-04): its
        // injection rates and its QUID, sample by sample.
        for (final (idx, block) in injectors.indexed) ...[
          if (idx > 0) pw.NewPage(),
          FsaForm.heading(
              'Injectors and Determination of QUID \u2014 ${block.name}', a),
          injectorBlock(block),
        ],
        if (injectors.any((b) => b.determination.isNotEmpty)) ...[
          pw.SizedBox(height: 4),
          average('AVERAGE DETERMINATION OF QUID (%):', averageQuidPercent),
          if (withinPermissibleLimit.isNotEmpty)
            average('WITHIN THE PERMISSIBLE LIMIT:', withinPermissibleLimit),
        ],
      ],
      // The masses behind that average, added up over the carcasses. An
      // average with no masses under it cannot be checked afterwards.
      if ([quidInitialMassG, quidAfterMassG, quidGainMassG]
          .any((v) => v.trim().isNotEmpty))
        table(
          const [
            'TOTAL INITIAL MASS (g)',
            'TOTAL AFTER MASS (g)',
            'TOTAL GAIN MASS (g)',
          ],
          [
            [quidInitialMassG, quidAfterMassG, quidGainMassG],
          ],
        ),
      if (verificationRecords.isNotEmpty) ...[
        FsaForm.heading('Verification of Records', a),
        table(
          const [
            'DATE',
            'NAME/DOCUMENT NUMBER',
            'VERIFIED',
            'DEVIATION(S)',
            'DEVIATION COMMENT',
            'PHOTOGRAPHED',
          ],
          [
            for (final r in verificationRecords)
              [
                r.date,
                r.name,
                r.verified,
                r.deviationPresent,
                r.comment,
                r.photographed,
              ],
          ],
        ),
        pw.SizedBox(height: 6),
      ] else if ([
        verificationDate,
        documentName,
        documentDeviationComment,
      ].any((v) => v.trim().isNotEmpty)) ...[
        FsaForm.heading('Verification of Records', a),
        FsaForm.field('Date', verificationDate, a,
            labelWidth: 150, boxWidth: 150),
        FsaForm.field('Name/Document Number', documentName, a,
            labelWidth: 150, boxWidth: 260),
        FsaForm.field('Document Verified', documentVerified, a,
            labelWidth: 150, boxWidth: 80),
        FsaForm.field('Deviation(s) Present', documentDeviationPresent, a,
            labelWidth: 150, boxWidth: 80),
        if (documentDeviationComment.trim().isNotEmpty)
          FsaForm.field('Deviation Comment', documentDeviationComment, a,
              labelWidth: 150, boxWidth: 380),
      ],
      // The rejection, on the sheet the office files: what failed, the
      // remarks served, the date to correct by and what was rejected.
      if ([
        rejectionReason,
        rejectionRemarks,
        rejectionCorrectBy,
        rejectionAction,
      ].any((v) => v.trim().isNotEmpty)) ...[
        FsaForm.heading('Rejection', a),
        if (rejectionReason.trim().isNotEmpty)
          FsaForm.field('Reason', rejectionReason, a,
              labelWidth: 150, boxWidth: 380),
        if (rejectionRemarks.trim().isNotEmpty)
          FsaForm.field('Remarks', rejectionRemarks, a,
              labelWidth: 150, boxWidth: 380),
        FsaForm.field('Correct by/on Date', rejectionCorrectBy, a,
            labelWidth: 150, boxWidth: 150),
        FsaForm.field('Batch No. and/or Quantity Rejected', rejectionAction, a,
            labelWidth: 150, boxWidth: 380),
      ],
    ];

    doc.addPage(
      pw.MultiPage(
        pageTheme: FsaForm.letterhead(a, PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.fromLTRB(22, 20, 22, 14)),
        header: (context) => context.pageNumber == 1
            ? FsaForm.header(a, control)
            : pw.SizedBox(),
        build: (context) => [
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    FsaForm.field('Date of Inspection:', dateOfInspection, a,
                        labelWidth: 118, boxWidth: 140),
                    FsaForm.field(
                        'Reason for Inspection:', reasonForInspection, a,
                        labelWidth: 118, boxWidth: 140),
                    FsaForm.field('Abattoir/Repacker/Importer/Retailer',
                        facilityName, a,
                        labelWidth: 118, boxWidth: 140),
                    FsaForm.field('Product', productName, a,
                        labelWidth: 118, boxWidth: 140),
                    FsaForm.field(
                        'Water chilling', isWaterChilled ? 'YES' : 'NO', a,
                        labelWidth: 118, boxWidth: 60),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    FsaForm.field('Registration Number', registrationNumber, a,
                        labelWidth: 108, boxWidth: 140),
                    FsaForm.field('Product Type', portionType, a,
                        labelWidth: 108, boxWidth: 140),
                    FsaForm.field(
                        'Allowable QUID (%)', allowableQuidPercent, a,
                        labelWidth: 108, boxWidth: 140),
                    FsaForm.field(
                        'Air chilling', isWaterChilled ? 'NO' : 'YES', a,
                        labelWidth: 108, boxWidth: 60),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          ...blocks,
          // Same closing flow as every other report (Ethan, 2026-10-08):
          // COMMENTS AND REMARKS, then SIGNATURE CONTROLS.
          FsaForm.heading('COMMENTS AND REMARKS', a),
          pw.Text('Comments (if found)', style: a.text(isBold: true, size: 7)),
          FsaForm.ruledLines(comments.isEmpty ? const [] : [comments], a),
          pw.SizedBox(height: 5),
          pw.Text('Remarks', style: a.text(isBold: true, size: 7)),
          FsaForm.ruledLines(remarks.isEmpty ? const [] : [remarks], a),
          pw.SizedBox(height: 10),
          FsaForm.heading('SIGNATURE CONTROLS', a),
          FsaForm.signedBlock(
            a,
            inspectorName: inspectorName,
            authorisedPersonName: authorisedPersonName,
            inspectorSignature: inspectorSignature,
            authorisedPersonSignature: authorisedSignature,
          ),
        ],
        footer: (context) => FsaForm.pageFooter(
            a, context.pageNumber, context.pagesCount, at: generatedAt),
      ),
    );

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    return out;
  }
}
