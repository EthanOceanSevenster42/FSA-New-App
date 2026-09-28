import 'fsa_form_pdf.dart';

/// The Agency's compliance forms, with the document-control values printed
/// on each one.
///
/// These are transcribed from the office system's own report definitions
/// (`FSA-WEB/Reports/*.rdl`), which is what the Agency scans and files
/// today, and from the blank forms the Agency supplied for the two the
/// office system does not produce. A handset document that disagreed with
/// the office's copy of the same form would be a different document, so
/// they live in one place and are asserted in tests.
abstract final class FsaDocuments {
  /// SOP-APS-EGGS-003 — the per-egg weights, Haugh readings and deviations.
  static const eggWeighing = FsaDocControl(
    docNo: 'SOP-APS-EGGS-003',
    title: 'EGG WEIGHING CHECKLIST',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-EGGS-003 — the marking and labelling checklist for eggs. The
  /// Agency gives the weighing and labelling checklists the same number.
  static const eggLabelling = FsaDocControl(
    docNo: 'SOP-APS-EGGS-003',
    title: 'EGG LABELING CHECKLIST',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-PM-001 — poultry meat QUID determination.
  static const poultryQuid = FsaDocControl(
    docNo: 'SOP-APS-PM-001',
    title: 'POULTRY MEAT QUID DETERMINATION CHECKLIST AS PER THE REGULATION '
        'NO. R.946 OF 27 MARCH 1992, AS AMENDED',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-PM-002 — poultry meat labelling verification.
  static const poultryLabelling = FsaDocControl(
    docNo: 'SOP-APS-PM-002',
    title: 'POULTRY MEAT LABELLING VERIFICATION CHECKLIST AS PER THE '
        'REGULATION NO. R.946 OF 27 MARCH 1992, AS AMENDED',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-PM-003 — classification and grading of poultry meat.
  static const poultryGrading = FsaDocControl(
    docNo: 'SOP-APS-PM-003',
    title: 'CLASSIFICATION & GRADING OF POULTRY MEAT CHECKLIST AS PER THE '
        'REGULATION NO. R.946 OF 27 MARCH 1992, AS AMENDED',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-RAW-001 — certain raw processed meat container and labelling.
  static const rawLabelling = FsaDocControl(
    docNo: 'SOP-APS-RAW-001',
    title: 'CERTAIN RAW PROCESSED MEAT PRODUCTS CONTAINER AND LABELLING '
        'VERIFICATION CHECKLIST AS PER THE REGULATION NO. R2410 OF '
        '26 AUGUST 2022',
    issueDate: '1 October 2022',
    effectiveDate: '1 October 2022',
    revisionDate: '31 July 2025',
    revision: 'V1',
  );

  /// SOP-APS-RAW-002 — certain raw processed meat sampling.
  static const rawSampling = FsaDocControl(
    docNo: 'SOP-APS-RAW-002',
    title: 'CERTAIN RAW PROCESSED MEAT PRODUCTS SAMPLING CHECKLIST AS PER '
        'THE REGULATION NO. R2410 OF 26 AUGUST 2022',
    issueDate: '1 October 2022',
    effectiveDate: '1 October 2022',
    revisionDate: '31 July 2025',
    revision: 'V1',
  );

  /// SOP-APS-RAW-003 — the compositional requirements checklist. Not in the
  /// office system: the Agency supplied the blank form (2026-08-28).
  static const rawComposition = FsaDocControl(
    docNo: 'SOP-APS-RAW-003',
    title: 'CERTAIN RAW PROCESSED MEAT PRODUCTS SPECIFIC COMPOSITIONAL '
        'REQUIREMENTS CHECKLIST AS PER THE REGULATION NO. R.2410 OF '
        '26 AUGUST 2022',
    issueDate: '1 January 2024',
    effectiveDate: '1 January 2024',
    revisionDate: '31 July 2025',
    revision: 'V1',
  );

  /// SOP-APS-001 — the direction (rejection) served on a facility.
  ///
  /// One document number across the commodities, as the office's own
  /// direction reports use: the regulation in the title is what changes.
  static const rawDirection = FsaDocControl(
    docNo: 'SOP-APS-001',
    title: 'CERTAIN RAW PROCESSED MEAT PRODUCTS REJECTION AS PER THE '
        'REGULATION NO. R.2410 OF 26 AUGUST 2022',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V4',
  );

  /// SOP-APS-001 — processed meat direction.
  static const pmpDirection = FsaDocControl(
    docNo: 'SOP-APS-001',
    title: 'PROCESSED MEAT PRODUCTS REJECTION AS PER THE REGULATION NO. '
        'R.1283 OF 4 OCTOBER 2019',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V4',
  );

  /// SOP-APS-001 — poultry meat direction.
  static const poultryDirection = FsaDocControl(
    docNo: 'SOP-APS-001',
    title: 'POULTRY MEAT REJECTION AS PER THE REGULATION NO. R.946 OF '
        '27 MARCH 1992, AS AMENDED',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V4',
  );

  /// SOP-APS-001 — egg direction.
  static const eggDirection = FsaDocControl(
    docNo: 'SOP-APS-001',
    title: 'EGG REJECTION AS PER THE REGULATION NO. R.541 OF 30 JUNE 2017',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V4',
  );

  /// SOP-APS-PMP-001 — processed meat container and labelling.
  static const pmpLabelling = FsaDocControl(
    docNo: 'SOP-APS-PMP-001',
    title: 'PROCESSED MEAT PRODUCTS CONTAINER AND LABELLING VERIFICATION '
        'CHECKLIST AS PER THE REGULATION NO. R1283 OF 4 OCTOBER 2019',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V5',
  );

  /// SOP-APS-PMP-002 — processed meat sampling.
  static const pmpSampling = FsaDocControl(
    docNo: 'SOP-APS-PMP-002',
    title: 'PROCESSED MEAT PRODUCTS SAMPLING CHECKLIST AS PER THE '
        'REGULATION NO. R1283 OF 4 OCTOBER 2019',
    issueDate: '1 September 2021',
    effectiveDate: '1 September 2021',
    revisionDate: '1 January 2023',
    revision: 'V4',
  );

  /// Every form above, for the tests that assert the catalogue against the
  /// office system's report definitions.
  static const all = <FsaDocControl>[
    eggWeighing,
    eggLabelling,
    poultryQuid,
    poultryLabelling,
    rawDirection,
    pmpDirection,
    poultryDirection,
    eggDirection,
    poultryGrading,
    rawLabelling,
    rawSampling,
    rawComposition,
    pmpLabelling,
    pmpSampling,
  ];
}
