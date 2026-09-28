import 'dart:convert';

/// FSA's Compositional Requirements Checklist for certain raw processed meat
/// products (SOP-APS-RAW-003), against Regulation 5 of R.2410 of
/// 26 August 2022 under the Agricultural Product Standards Act, 119 of 1990.
///
/// The paper form is a table of nine permissible-ingredient requirements,
/// each answered as a deviation YES/NO with a contribution in grams and a
/// remark. This is that table as data, stored on the raw inspection as JSON
/// and printed by [CompositionChecklistPdf].
abstract final class CompositionChecklist {
  static const docNo = 'SOP-APS-RAW-003';
  static const revision = 'V1';
  static const regulation =
      'CERTAIN RAW PROCESSED MEAT PRODUCTS SPECIFIC COMPOSITIONAL REQUIREMENTS '
      'CHECKLIST AS PER THE REGULATION NO. R.2410 OF 26 AUGUST 2022';
  static const act = 'AGRICULTURAL PRODUCT STANDARDS ACT, 119 OF 1990';

  /// The nine requirements, in the order and wording of the form.
  static const items = <String>[
    'Manufactured from either meat of a single domesticated animal, bird or '
        'wild game species or from a mixture of two or more of such species',
    'Contained in an edible casing',
    'Contain no added ingredients (other than water, food additives, vinegar, '
        'spices, herbs and/or salt, cereal, or starch and/or vegetable protein)',
    'Contain no added colourants, food additives, foodtuffs, water, edible '
        'offal or inedible offal',
    'Contain mechanically recovered meat',
    'Contain edible offal',
    'Contain colourants',
    'Contain other foodstuffs',
    'Total Meat Content',
  ];

  /// Where "Total Meat Content" sits in [items].
  static const totalMeatIndex = 8;

  /// Total meat content as a percentage of the product (Ethan, 2026-09-24,
  /// from an inspector who worked it by hand): the meat, over the meat and
  /// all the other ingredients together, × 100. Null until both are
  /// numbers and there is something to divide by.
  ///
  /// Meat ÷ the other ingredients alone would read 400% for 80 g of meat in
  /// 100 g of product, so the meat is counted in the whole it is part of.
  static double? totalMeatPercent(String meatGrams, String otherGrams) {
    final meat = double.tryParse(meatGrams.trim().replaceAll(',', '.'));
    final other = double.tryParse(otherGrams.trim().replaceAll(',', '.'));
    if (meat == null || other == null || meat < 0 || other < 0) return null;
    final whole = meat + other;
    if (whole <= 0) return null;
    return meat / whole * 100;
  }

  /// "80.0%", as it is shown and printed.
  static String percentText(double percent) => '${percent.toStringAsFixed(1)}%';

  /// Nine blank answers.
  static List<CompositionAnswer> blank() =>
      List.generate(items.length, (_) => const CompositionAnswer());

  /// The stored form: a JSON list of nine objects. Anything unreadable, or
  /// the empty string of a record captured before the checklist existed,
  /// reads as blank rather than failing the record.
  static List<CompositionAnswer> decode(String json) {
    if (json.trim().isEmpty) return blank();
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return blank();
      final answers = blank();
      for (var i = 0; i < answers.length && i < raw.length; i++) {
        final row = raw[i];
        if (row is! Map) continue;
        answers[i] = CompositionAnswer(
          deviation: switch (row['deviation']) {
            true => true,
            false => false,
            _ => null,
          },
          // `percent` is what records captured before the contribution moved
          // to grams stored it under. Their numbers are percentages and are
          // read back as they were written — relabelling the field does not
          // convert what is already on a record.
          contributionGrams: (row['grams'] ?? row['percent'] ?? '').toString(),
          remarks: (row['remarks'] ?? '').toString(),
          meatGrams: (row['meat'] ?? '').toString(),
          otherGrams: (row['other'] ?? '').toString(),
        );
      }
      return answers;
    } on FormatException {
      return blank();
    }
  }

  static String encode(List<CompositionAnswer> answers) => jsonEncode([
        for (final a in answers)
          {
            'deviation': a.deviation,
            'grams': a.contributionGrams,
            'remarks': a.remarks,
            if (a.meatGrams.isNotEmpty) 'meat': a.meatGrams,
            if (a.otherGrams.isNotEmpty) 'other': a.otherGrams,
          },
      ]);

  /// Whether anything at all was answered — an untouched checklist is not
  /// printed as a page of blanks.
  static bool isAnswered(List<CompositionAnswer> answers) =>
      answers.any((a) => !a.isBlank);
}

/// One row of the checklist: the deviation answer (null = not answered),
/// the contribution in grams as typed, and the remark.
class CompositionAnswer {
  const CompositionAnswer({
    this.deviation,
    this.contributionGrams = '',
    this.remarks = '',
    this.meatGrams = '',
    this.otherGrams = '',
  });

  final bool? deviation;

  /// What this ingredient contributes, in grams, as the inspector typed it.
  /// Held as text rather than a number: a half-typed "12." is a state the
  /// field has to be able to be in, and the record keeps what was written.
  final String contributionGrams;
  final String remarks;

  /// Total Meat Content only: the meat, and all the other ingredients, in
  /// grams as typed. The percentage is worked out from them.
  final String meatGrams;
  final String otherGrams;

  /// The worked-out total meat content, when both amounts are given.
  double? get totalMeatPercent =>
      CompositionChecklist.totalMeatPercent(meatGrams, otherGrams);

  bool get isBlank =>
      deviation == null &&
      contributionGrams.trim().isEmpty &&
      remarks.trim().isEmpty &&
      meatGrams.trim().isEmpty &&
      otherGrams.trim().isEmpty;

  CompositionAnswer copyWith({
    bool? deviation,
    bool clearDeviation = false,
    String? contributionGrams,
    String? remarks,
    String? meatGrams,
    String? otherGrams,
  }) =>
      CompositionAnswer(
        deviation: clearDeviation ? null : (deviation ?? this.deviation),
        contributionGrams: contributionGrams ?? this.contributionGrams,
        remarks: remarks ?? this.remarks,
        meatGrams: meatGrams ?? this.meatGrams,
        otherGrams: otherGrams ?? this.otherGrams,
      );
}
