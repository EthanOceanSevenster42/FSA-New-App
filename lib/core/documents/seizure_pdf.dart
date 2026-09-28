import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fsa_form_pdf.dart';

/// One line of the seizure's product table.
class SeizedProduct {
  const SeizedProduct({
    required this.productName,
    required this.productClass,
    required this.quantity,
    required this.regulation,
    required this.natureOfDeviation,
    this.correctiveAction = 'Immediate',
    this.remarks = '',
  });

  final String productName;
  final String productClass;
  final String quantity;
  final String regulation;
  final String natureOfDeviation;
  final String correctiveAction;
  final String remarks;
}

/// The seizure served on a client — the Department of Agriculture's
/// standard "Seizure" form, FSA-SOP-APS-001 Annexure E.
///
/// Reproduced from the sheet the inspectors carry (the Checkers Blueberry
/// Square seizure of 7 September 2026 was the worked example): the client's
/// particulars, the paragraph citing sections 3(1), 4A, 7 and 8 of the Act,
/// the product table, the Issued and Acknowledgement of receipt blocks, and
/// the Executive Officer's authorisation block — left blank, since an
/// immediate seizure needs none beforehand.
///
/// The paper form carries the national coat of arms; the handset has no
/// copy of it, so the Department's name is set in type beside the Agency's
/// mark, which is who serves it as assignee.
abstract final class SeizurePdf {
  static Future<File> write({
    required File out,
    required String clientName,
    required String clientAddress,
    required String clientTelephone,
    required String clientFax,
    required String clientEmail,
    required String inspectionPoint,
    required List<SeizedProduct> products,
    required DateTime issuedAt,
    required String issuedPlace,
    required String inspectorName,
    required String receiverName,
    required String receiverIdNumber,
    required String receiverDesignation,
    String assigneeName = 'Food Safety Agency (Pty) Ltd',
    String inspectorDesignation = 'APS Inspector',
    String inspectorSignaturePath = '',
    String receiverSignaturePath = '',
    DateTime? receivedAt,
    String receivedPlace = '',
  }) async {
    final a = await FsaForm.assets();
    final inspectorSignature = await FsaForm.image(inspectorSignaturePath);
    final receiverSignature = await FsaForm.image(receiverSignaturePath);
    final doc = pw.Document();

    String two(int v) => v.toString().padLeft(2, '0');
    String date(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';
    String time(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
    final received = receivedAt ?? issuedAt;

    pw.Widget label(String v) => FsaForm.cell(v, a, isBold: true, size: 7);
    pw.Widget value(String v) => FsaForm.cell(v, a, size: 7.5);

    // The client block: two label/value pairs to a row, ruled, as the form.
    final particulars = pw.Table(
      border: FsaForm.border(),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(children: [
          label('Client Name'),
          value(clientName),
          label('Inspection Point'),
          value(inspectionPoint),
        ]),
        pw.TableRow(children: [
          label('Client postal/physical address'),
          value(clientAddress),
          label('Office Fax number'),
          value(clientFax),
        ]),
        pw.TableRow(children: [
          label('Office telephone or Cell number'),
          value(clientTelephone),
          label('E-mail address'),
          value(clientEmail),
        ]),
      ],
    );

    pw.Widget head(String v) => pw.Container(
          color: FsaForm.grey,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Text(v, style: a.text(isBold: true, size: 6.5)),
        );
    pw.Widget body(String v) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          constraints: const pw.BoxConstraints(minHeight: 30),
          child: pw.Text(v, style: a.text(size: 7)),
        );
    // Three ruled rows at least, as the printed form has, so a seizure of
    // one product still looks like the sheet the client knows.
    final rows = [
      ...products,
      for (var i = products.length; i < 3; i++)
        const SeizedProduct(
          productName: '',
          productClass: '',
          quantity: '',
          regulation: '',
          natureOfDeviation: '',
          correctiveAction: '',
        ),
    ];
    final productTable = pw.Table(
      border: FsaForm.border(),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(2.6),
        5: pw.FlexColumnWidth(1.7),
        6: pw.FlexColumnWidth(2.0),
      },
      children: [
        pw.TableRow(children: [
          head('Product name'),
          head('Product class'),
          head('Quantity'),
          head('Applicable regulation'),
          head('Nature of deviation'),
          head('Corrective actions: Period and kind of treatment as per '
              'section 8(3) of the Act'),
          head('Remarks/comments'),
        ]),
        for (final p in rows)
          pw.TableRow(children: [
            body(p.productName),
            body(p.productClass),
            body(p.quantity),
            body(p.regulation),
            body(p.natureOfDeviation),
            body(p.correctiveAction),
            body(p.remarks),
          ]),
      ],
    );

    pw.Widget line(String caption, String v, {double captionWidth = 70}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.SizedBox(
                width: captionWidth,
                child: pw.Text(caption, style: a.text(isBold: true, size: 7)),
              ),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.only(left: 2, bottom: 1),
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
                  child: pw.Text(v, style: a.text(size: 7.5)),
                ),
              ),
            ],
          ),
        );

    pw.Widget signed(String caption, pw.MemoryImage? signature) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 70,
              child: pw.Text(caption, style: a.text(isBold: true, size: 7)),
            ),
            pw.Expanded(
                child: FsaForm.signatureLine(a,
                    signature: signature, width: 200)),
          ],
        );

    pw.Widget block(String title, List<pw.Widget> lines) => pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                  child:
                      pw.Text(title, style: a.text(isBold: true, size: 8))),
              pw.SizedBox(height: 4),
              ...lines,
            ],
          ),
        );

    final issued = block('Issued', [
      pw.Row(children: [
        pw.Expanded(child: line('Date:', date(issuedAt), captionWidth: 30)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: line('Time:', time(issuedAt), captionWidth: 30)),
      ]),
      line('Place:', issuedPlace, captionWidth: 30),
      line('Inspector Name:', inspectorName),
      line('Designation:', inspectorDesignation),
      pw.SizedBox(height: 4),
      signed('Signature:', inspectorSignature),
    ]);

    final acknowledgement = block('Acknowledgement of receipt', [
      pw.Row(children: [
        pw.Expanded(child: line('Date:', date(received), captionWidth: 30)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: line('Time:', time(received), captionWidth: 30)),
      ]),
      line('Place:', receivedPlace.isEmpty ? issuedPlace : receivedPlace,
          captionWidth: 30),
      line(
          'Name and ID no:',
          [receiverName, receiverIdNumber]
              .where((s) => s.trim().isNotEmpty)
              .join('   ')),
      line('Designation:', receiverDesignation),
      pw.SizedBox(height: 4),
      signed('Signature:', receiverSignature),
    ]);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 16),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 150,
                  height: 44,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(a.logo, fit: pw.BoxFit.contain),
                ),
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('agriculture', style: a.text(size: 13)),
                    pw.Container(height: 0.8, width: 150,
                        color: PdfColors.black),
                    pw.Text('Department:', style: a.text(size: 6.5)),
                    pw.Text('Agriculture', style: a.text(size: 6.5)),
                    pw.Text('REPUBLIC OF SOUTH AFRICA',
                        style: a.text(isBold: true, size: 6.5)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(
                child: pw.Text('SEIZURE',
                    style: a.text(isBold: true, size: 12))),
            pw.SizedBox(height: 8),
            pw.Text('Particulars of the Client or Owner of the consignment',
                style: a.text(isBold: true, size: 8.5)),
            pw.SizedBox(height: 4),
            particulars,
            pw.SizedBox(height: 8),
            pw.RichText(
              text: pw.TextSpan(
                style: a.text(size: 7.5),
                children: [
                  const pw.TextSpan(
                      text: 'The products listed and described below and '
                          'which have been marked or pointed out by me '
                          'physically, are being sold / imported in '
                          'contravention of '),
                  pw.TextSpan(
                      text: 'Sections 3 (1) and 4A',
                      style: a.text(isBold: true, size: 7.5)),
                  const pw.TextSpan(
                      text: ' of the Agricultural Product Standards Act, '
                          '1990 (Act 119 of 1990) as amended, read in '
                          'conjunction with the relevant regulations '
                          'regarding the sale of products. The product is '
                          'therefore seized by the Executive Officer or '
                          'Assignee ('),
                  pw.TextSpan(
                      text: assigneeName,
                      style: a.text(isBold: true, size: 7.5)),
                  const pw.TextSpan(
                      text: ') in terms of sections 7 and 8 of the Act '
                          'forthwith.'),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            productTable,
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: issued),
                pw.SizedBox(width: 10),
                pw.Expanded(child: acknowledgement),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text(
                'Authorization by the Executive Officer or a delegated '
                'official in terms of section 8(3) of the Act',
                style: a.text(isBold: true, size: 8)),
            pw.SizedBox(height: 4),
            line('Name of the authorizing official:', '', captionWidth: 130),
            line('Designation:', '', captionWidth: 130),
            line('Date:', '', captionWidth: 130),
            pw.Spacer(),
            FsaForm.footer(a),
          ],
        ),
      ),
    );

    await out.parent.create(recursive: true);
    await out.writeAsBytes(await doc.save());
    return out;
  }
}
