import 'dart:convert';

/// FSA's Compositional Requirements Checklist for certain raw processed meat
/// products (SOP-APS-RAW-003), against Regulation 5 of R.2410 of
/// 26 August 2022 under the Agricultural Product Standards Act, 119 of 1990.
///
/// The paper form is a table of seven permissible-ingredient requirements,
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

  /// The eight requirements, in the order and wording of the form. It had
  /// nine; "Contain colourants" and "Contain other foodstuffs" were removed
  /// (Ethan, 2026-09-30), leaving seven. Mechanically deboned meat was
  /// added back as a row of its own (Neo Noe, 2026-10-19): the manual
  /// checklist carried it, and some products — boerewors among them — may
  /// not contain MDM at all, which cannot be recorded if the form has
  /// nowhere to write it.
  static const items = <String>[
    'Manufactured from either meat of a single domesticated animal, bird or '
        'wild game species or from a mixture of two or more of such species',
    'Contained in an edible casing',
    'Contain no added ingredients (other than water, food additives, vinegar, '
        'spices, herbs and/or salt, cereal, or starch and/or vegetable protein)',
    'Spice',
    'Water',
    'Contain edible offal',
    'Food stuff',
    'Mechanically deboned meat (MDM)',
    'Total Meat Content',
  ];

  /// Where "Total Meat Content" sits in [items].
  static const totalMeatIndex = 8;

  /// Records saved while the checklist had nine rows keep all nine; these
  /// are the two since removed, dropped as such a record is read so every
  /// other row — Total Meat Content last — stays with its own answer.
  static const _nineRows = 9;
  static const _removedFromNine = {6, 7};

  /// What a record captured before the MDM row held: seven ingredients and
  /// Total Meat Content, eight in all. Its last row is the total, which now
  /// sits one lower, so reading such a record straight through would file
  /// its total against MDM. The total is moved down and the MDM row left
  /// blank, which is what it was: never asked.
  static const _eightRows = 8;

  /// The shape a record is written in now, stamped on it so it is never
  /// mistaken for one of the older shapes it happens to be the same length
  /// as. Records from before the stamp carry none and are read by length.
  static const _version = 2;

  /// The row whose contribution is meat: row 1, the meat the product is
  /// made from. The other ingredients — spice, water, food stuff and the
  /// rest — are the remaining rows (Ethan, 2026-10-05). Total Meat Content
  /// has no box of its own; it is only the result.
  static const meatRows = {0};

  /// The rows that make up "all other ingredients": every row but the meat
  /// one and Total Meat Content itself.
  static List<int> get otherRows => [
        for (var i = 0; i < items.length; i++)
          if (i != totalMeatIndex && !meatRows.contains(i)) i,
      ];

  static double? _grams(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    return v == null || v < 0 ? null : v;
  }

  /// The meat: row 1. Null until it is a number.
  static double? meatOf(List<CompositionAnswer> answers) {
    if (answers.length <= totalMeatIndex) return null;
    double? sum = 0;
    for (final i in meatRows) {
      final g = _grams(answers[i].contributionGrams);
      sum = sum == null || g == null ? null : sum + g;
    }
    return sum;
  }

  /// All the other ingredients: every row but the meat and the total added
  /// up, mechanically deboned meat among them — MDM is not meat for the
  /// purpose of total meat content. Null until each is a number.
  static double? otherOf(List<CompositionAnswer> answers) {
    if (answers.length <= totalMeatIndex) return null;
    double? sum = 0;
    for (final i in otherRows) {
      final g = _grams(answers[i].contributionGrams);
      sum = sum == null || g == null ? null : sum + g;
    }
    return sum;
  }

  /// Total meat content (Ethan, 2026-10-01): meat ÷ (meat + all other
  /// ingredients) × 100 — the meat as a share of the whole product, worked
  /// out from the checklist rather than from a second box the inspector
  /// added up by hand. Null until every amount is a number and there is
  /// something to divide by.
  static double? totalMeatPercent(List<CompositionAnswer> answers) {
    final meat = meatOf(answers);
    final other = otherOf(answers);
    if (meat == null || other == null) return null;
    final whole = meat + other;
    if (whole <= 0) return null;
    return meat / whole * 100;
  }

  /// The calculation as the document shows it: "Meat 0.8 kg ÷ (0.8 kg +
  /// 0.2 kg other ingredients) × 100 = 80.0%". Null until it can be worked
  /// out.
  static String? calculationText(List<CompositionAnswer> answers,
      {String unit = kg}) {
    final percent = totalMeatPercent(answers);
    if (percent == null) return null;
    final meat = _amount(meatOf(answers)!);
    final other = _amount(otherOf(answers)!);
    return 'Meat $meat $unit ÷ ($meat $unit + $other $unit other '
        'ingredients) × 100 = ${percentText(percent)}';
  }

  /// An amount as written: "85", "0.85" — no run of float noise.
  static String _amount(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// The unit the amounts are typed in: kg (Ethan, 2026-10-01).
  static const kg = 'kg';

  /// What a record captured before the change to kg typed them in.
  static const grams = 'g';

  /// The unit [json]'s amounts are in: as the record says, grams for one
  /// holding amounts from before it said, kg for one with none yet.
  static String unitOf(String json) {
    if (json.trim().isEmpty) return kg;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map && decoded['unit'] is String) {
        return decoded['unit'] as String;
      }
    } on FormatException {
      return kg;
    }
    final typed = decode(json).any((a) =>
        a.contributionGrams.trim().isNotEmpty || a.meatGrams.trim().isNotEmpty);
    return typed ? grams : kg;
  }

  /// "80.0%", as it is shown and printed.
  static String percentText(double percent) => '${percent.toStringAsFixed(1)}%';

  /// A blank answer for every row.
  static List<CompositionAnswer> blank() =>
      List.generate(items.length, (_) => const CompositionAnswer());

  /// The stored form: a JSON list of one object per row. Anything unreadable, or
  /// the empty string of a record captured before the checklist existed,
  /// reads as blank rather than failing the record.
  static List<CompositionAnswer> decode(String json) {
    if (json.trim().isEmpty) return blank();
    try {
      final decoded = jsonDecode(json);
      // Stored as the rows with the one remark beside them; a record from
      // before the remark moved to the bottom is the bare list of rows.
      final rows = decoded is Map ? decoded['rows'] : decoded;
      if (rows is! List) return blank();
      // Which shape of the checklist this record was written against.
      // Row counts alone no longer tell them apart: the nine-row form and
      // the current one are both nine rows long, so a record written since
      // the MDM row says so (Ethan, 2026-10-20).
      final version = decoded is Map ? decoded['v'] : null;
      final raw = version == _version
          ? rows
          : switch (rows.length) {
              _nineRows => [
                  for (var i = 0; i < rows.length; i++)
                    if (!_removedFromNine.contains(i)) rows[i],
                ],
              _eightRows => [...rows.take(_eightRows - 1), null, rows.last],
              _ => rows,
            };
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

  /// The rows, and the checklist's one remark — written at the bottom
  /// rather than on every row (Ethan, 2026-09-30).
  static String encode(List<CompositionAnswer> answers,
          {String remarks = '', String unit = kg}) =>
      jsonEncode({
        'v': _version,
        'unit': unit,
        'rows': [
          for (final a in answers)
            {
              'deviation': a.deviation,
              'grams': a.contributionGrams,
              'remarks': a.remarks,
              if (a.meatGrams.isNotEmpty) 'meat': a.meatGrams,
              if (a.otherGrams.isNotEmpty) 'other': a.otherGrams,
            },
        ],
        'remarks': remarks,
      });

  /// The checklist's one remark, or empty — as for a record from before
  /// there was one.
  static String remarksOf(String json) {
    if (json.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(json);
      return decoded is Map ? (decoded['remarks'] ?? '').toString() : '';
    } on FormatException {
      return '';
    }
  }

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

  /// Total Meat Content only: the meat, in grams as typed. [otherGrams] is
  /// what records from before the other ingredients were added up from the
  /// rows held; nothing reads it now.
  final String meatGrams;
  final String otherGrams;

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
