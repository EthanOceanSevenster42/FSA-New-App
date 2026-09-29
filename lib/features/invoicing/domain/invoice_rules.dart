/// The Agency's tariff: every rate and fee the Request for Invoice bills.
///
/// Edited on the web (the server admin's "RFI tariff") and brought down on
/// every sync (Ethan, 2026-09-29); the figures below are the published
/// tariff the app falls back on until it has synced once.
class InvoiceTariff {
  const InvoiceTariff({
    required this.normalHour,
    required this.overtimeHour,
    required this.sundayHour,
    required this.perKilometre,
    required this.minimumChargeableHours,
    required this.pmpFat,
    required this.pmpProtein,
    required this.pmpCalcium,
    required this.pmpPhysical,
    required this.rawFat,
    required this.rawProtein,
    required this.rawSoya,
    required this.rawStarch,
    required this.rawDna,
    required this.rawCalcium,
    required this.vatRate,
  });

  /// Inspection of Poultry Meat, Processed Meat Products and Certain Raw
  /// Processed Meat Products.
  final double normalHour;
  final double overtimeHour;
  final double sundayHour;
  final double perKilometre;

  /// "Where hourly rates are applicable, a minimum of one hour will be
  /// charged. Thereafter time will be charged in half hour segments."
  final double minimumChargeableHours;

  /// Laboratory — Processed Meat Products.
  final double pmpFat;
  final double pmpProtein;
  final double pmpCalcium;
  final double pmpPhysical;

  /// Laboratory — Certain Raw Processed Meat Products.
  final double rawFat;
  final double rawProtein;
  final double rawSoya;
  final double rawStarch;
  final double rawDna;
  final double rawCalcium;

  /// Shown on the form as an exclusion, never added to the total.
  final double vatRate;

  /// Reads the server's tariff. A figure missing, unreadable or not
  /// positive keeps [fallback]'s, so a half-filled record cannot bill
  /// nothing for an hour's work.
  factory InvoiceTariff.fromJson(Map<String, Object?> json,
      {InvoiceTariff fallback = InvoiceRates.defaults}) {
    double read(String key, double otherwise) {
      final value = json[key];
      final number = value is num ? value.toDouble() : double.tryParse('$value');
      return number == null || number.isNaN || number < 0 ? otherwise : number;
    }

    return InvoiceTariff(
      normalHour: read('normal_hour', fallback.normalHour),
      overtimeHour: read('overtime_hour', fallback.overtimeHour),
      sundayHour: read('sunday_hour', fallback.sundayHour),
      perKilometre: read('per_kilometre', fallback.perKilometre),
      minimumChargeableHours:
          read('minimum_chargeable_hours', fallback.minimumChargeableHours),
      pmpFat: read('pmp_fat', fallback.pmpFat),
      pmpProtein: read('pmp_protein', fallback.pmpProtein),
      pmpCalcium: read('pmp_calcium', fallback.pmpCalcium),
      pmpPhysical: read('pmp_physical', fallback.pmpPhysical),
      rawFat: read('raw_fat', fallback.rawFat),
      rawProtein: read('raw_protein', fallback.rawProtein),
      rawSoya: read('raw_soya', fallback.rawSoya),
      rawStarch: read('raw_starch', fallback.rawStarch),
      rawDna: read('raw_dna', fallback.rawDna),
      rawCalcium: read('raw_calcium', fallback.rawCalcium),
      vatRate: read('vat_rate', fallback.vatRate),
    );
  }

  Map<String, double> toJson() => {
        'normal_hour': normalHour,
        'overtime_hour': overtimeHour,
        'sunday_hour': sundayHour,
        'per_kilometre': perKilometre,
        'minimum_chargeable_hours': minimumChargeableHours,
        'pmp_fat': pmpFat,
        'pmp_protein': pmpProtein,
        'pmp_calcium': pmpCalcium,
        'pmp_physical': pmpPhysical,
        'raw_fat': rawFat,
        'raw_protein': rawProtein,
        'raw_soya': rawSoya,
        'raw_starch': rawStarch,
        'raw_dna': rawDna,
        'raw_calcium': rawCalcium,
        'vat_rate': vatRate,
      };

  @override
  bool operator ==(Object other) =>
      other is InvoiceTariff && '${other.toJson()}' == '${toJson()}';

  @override
  int get hashCode => '${toJson()}'.hashCode;
}

/// The tariff this tablet bills with right now, and the arithmetic the
/// Request for Invoice form (SOP-APS-002 V8) does with it.
///
/// The amounts a form produces are stored on the record, so a form always
/// re-prints with the figures it was signed with.
abstract final class InvoiceRates {
  /// The published tariff, until the server's has been brought down.
  static const defaults = InvoiceTariff(
    normalHour: 540.60,
    overtimeHour: 601.02,
    sundayHour: 720.80,
    perKilometre: 6.50,
    minimumChargeableHours: 1.0,
    pmpFat: 875.56,
    pmpProtein: 533.18,
    pmpCalcium: 401.74,
    pmpPhysical: 212.00,
    rawFat: 875.56,
    rawProtein: 533.18,
    rawSoya: 1764.90,
    rawStarch: 1560.32,
    rawDna: 2761.30,
    rawCalcium: 401.74,
    vatRate: 0.15,
  );

  static InvoiceTariff _current = defaults;

  /// The tariff in force on this tablet.
  static InvoiceTariff get current => _current;

  /// Puts [tariff] in force — from the server on sync, or from the copy
  /// kept on the device when the app starts.
  static void use(InvoiceTariff tariff) => _current = tariff;

  static double get normalHour => _current.normalHour;
  static double get overtimeHour => _current.overtimeHour;
  static double get sundayHour => _current.sundayHour;
  static double get perKilometre => _current.perKilometre;
  static double get minimumChargeableHours => _current.minimumChargeableHours;
  static double get pmpFat => _current.pmpFat;
  static double get pmpProtein => _current.pmpProtein;
  static double get pmpCalcium => _current.pmpCalcium;
  static double get pmpPhysical => _current.pmpPhysical;
  static double get rawFat => _current.rawFat;
  static double get rawProtein => _current.rawProtein;
  static double get rawSoya => _current.rawSoya;
  static double get rawStarch => _current.rawStarch;
  static double get rawDna => _current.rawDna;
  static double get rawCalcium => _current.rawCalcium;
  static double get vatRate => _current.vatRate;
}

/// What the form totals to, given what the inspector entered.
class InvoiceTotals {
  const InvoiceTotals({
    required this.normal,
    required this.overtime,
    required this.sunday,
    required this.travel,
    required this.inspection,
    required this.pmpLab,
    required this.rawLab,
    required this.grand,
  });

  final double normal;
  final double overtime;
  final double sunday;
  final double travel;

  /// The first table's total: hours at each rate plus the kilometres.
  final double inspection;
  final double pmpLab;
  final double rawLab;

  /// Everything, excluding VAT — what "Total Invoice Amount" carries.
  final double grand;
}

abstract final class InvoiceRules {
  /// Hours as the tariff charges them, not as the clock ran: under an hour
  /// is charged as one, and beyond that in half-hour segments, "or part
  /// thereof" — so 1.1 hours is charged as 1.5.
  static double chargeableHours(double hours) {
    if (hours <= 0) return 0;
    if (hours <= InvoiceRates.minimumChargeableHours) {
      return InvoiceRates.minimumChargeableHours;
    }
    // Round up to the next half hour.
    return (hours * 2).ceil() / 2;
  }

  /// Each band rounded up to the half hour, with the one-hour minimum applied
  /// to the visit as a whole rather than to every band it touches.
  ///
  /// A 75-minute visit that runs from 15:30 to 16:45 is half an hour of normal
  /// time and three quarters of overtime. Charging the minimum per band would
  /// bill it as two full hours (R1 141.62); the tariff's "minimum of one hour"
  /// is a floor on the inspection, so it bills as 0.5 normal + 1.0 overtime.
  /// Only when the whole visit is under an hour is a band topped up — the one
  /// the visit actually had time in.
  static ({double normal, double overtime, double sunday}) chargeableBands({
    required double normal,
    required double overtime,
    required double sunday,
  }) {
    double halfHours(double hours) => hours <= 0 ? 0 : (hours * 2).ceil() / 2;
    var n = halfHours(normal);
    var o = halfHours(overtime);
    var su = halfHours(sunday);
    final total = n + o + su;
    if (total > 0 && total < InvoiceRates.minimumChargeableHours) {
      final shortfall = InvoiceRates.minimumChargeableHours - total;
      if (n > 0) {
        n += shortfall;
      } else if (o > 0) {
        o += shortfall;
      } else {
        su += shortfall;
      }
    }
    return (normal: n, overtime: o, sunday: su);
  }

  /// The commodities whose time the hourly rate is charged for.
  ///
  /// The heading over the time table names poultry too, but the Agency does
  /// not bill the hour for the poultry or the eggs: those are inspected on
  /// the same visit and appear on the form — ticked, and named under Product
  /// Name — while only the raw and processed-meat work is charged for
  /// (FSA, 2026-09-08). Kilometres are unaffected: the drive is one drive.
  static const chargeableKinds = {'rawrmp', 'pmp'};

  /// The stretch of a visit the hour is charged for.
  ///
  /// A visit works through its commodities one after the next and each
  /// inspection records when it was opened, so reading those starts in
  /// order gives every inspection the stretch of the visit it occupied —
  /// the first also carries the visit's own opening, the last runs to the
  /// sign-off. Adding up only the chargeable stretches leaves the egg and
  /// poultry time out of the bill.
  ///
  /// The window comes back starting where the first chargeable inspection
  /// did and running for as long as those stretches added up to, so the
  /// times printed on the form are the times its money was worked out from
  /// even when an egg inspection sat between two chargeable ones.
  ///
  /// [billable] is false when the visit held nothing chargeable at all — an
  /// eggs-only visit, say. The window is then the visit as it ran, for the
  /// record, and no hours are charged against it. A visit whose members
  /// carry no times at all falls back to the visit itself, which is what
  /// was billed before inspections were timed.
  static ({DateTime start, DateTime end, bool billable}) chargeableWindow({
    required Iterable<({String kind, DateTime? inspectedAt})> members,
    required DateTime visitStarted,
    required DateTime visitEnded,
  }) {
    final dated = [
      for (final m in members)
        if (m.inspectedAt != null) (kind: m.kind, at: m.inspectedAt!),
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (dated.isEmpty) {
      return (start: visitStarted, end: visitEnded, billable: true);
    }

    var charged = Duration.zero;
    DateTime? start;
    for (var i = 0; i < dated.length; i++) {
      // The first stretch reaches back to the visit's own start, so a visit
      // of one commodity bills exactly what it always did.
      final from = i == 0 && visitStarted.isBefore(dated[i].at)
          ? visitStarted
          : dated[i].at;
      final to = i + 1 < dated.length ? dated[i + 1].at : visitEnded;
      if (!chargeableKinds.contains(dated[i].kind)) continue;
      start ??= from;
      if (to.isAfter(from)) charged += to.difference(from);
    }
    if (start == null) {
      return (start: visitStarted, end: visitEnded, billable: false);
    }
    // A chargeable inspection was opened, so the hour is owed whatever the
    // clock says: a minute on site is a minute the Agency attended for, and
    // the tariff's minimum is an hour (FSA, 2026-09-08). Without this floor
    // an inspection opened and signed off inside the same second measures
    // as no time at all and would invoice for the kilometres only.
    final billed = charged < minimumBilledSpan ? minimumBilledSpan : charged;
    return (start: start, end: start.add(billed), billable: true);
  }

  /// The shortest stretch a chargeable inspection can be credited with. It
  /// is not the amount charged — the one-hour minimum does that — only
  /// enough that the visit reads as having taken time at all.
  static const minimumBilledSpan = Duration(minutes: 1);

  /// Hours between two "HH:mm" entries, or null when either is unreadable.
  /// A finish before the start is treated as running past midnight, which is
  /// how a late inspection reads on the form.
  static double? hoursBetween(String started, String ended) {
    final from = _minutes(started);
    final to = _minutes(ended);
    if (from == null || to == null) return null;
    final span = to >= from ? to - from : (24 * 60) - from + to;
    return span / 60;
  }

  static int? _minutes(String value) {
    final match =
        RegExp(r'^\s*(\d{1,2})\s*[:.]?\s*(\d{2})\s*$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// "HH:mm", as the form writes a time.
  static String clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// Splits a visit across the tariff's three bands.
  ///
  /// Sunday is charged at the Sunday rate throughout. On any other day the
  /// part that falls inside 08:00–16:00 is normal time and the rest is
  /// overtime. Public holidays are not in the split: the app has no
  /// calendar of them, and the inspector can move the hours by hand on a
  /// form that is theirs to correct.
  static ({double normal, double overtime, double sunday}) splitHours(
    DateTime start,
    DateTime end,
  ) {
    final finish = end.isAfter(start) ? end : start;
    final total = finish.difference(start).inMinutes / 60;
    if (total <= 0) return (normal: 0, overtime: 0, sunday: 0);
    if (start.weekday == DateTime.sunday) {
      return (normal: 0, overtime: 0, sunday: total);
    }
    final dayStart = DateTime(start.year, start.month, start.day, 8);
    final dayEnd = DateTime(start.year, start.month, start.day, 16);
    final overlapFrom = start.isAfter(dayStart) ? start : dayStart;
    final overlapTo = finish.isBefore(dayEnd) ? finish : dayEnd;
    final normal = overlapTo.isAfter(overlapFrom)
        ? overlapTo.difference(overlapFrom).inMinutes / 60
        : 0.0;
    return (normal: normal, overtime: total - normal, sunday: 0);
  }

  /// Whether the journey is billed.
  ///
  /// Only certain raw processed meat and processed meat work carries a
  /// kilometre charge. The distance is still recorded and still printed for
  /// every visit — the office wants to see how far the inspector drove
  /// whatever was inspected — but it is only charged for on those two.
  static bool travelIsChargeable({
    required bool rawRmp,
    required bool pmp,
  }) =>
      rawRmp || pmp;

  static InvoiceTotals totals({
    required double normalHours,
    required double overtimeHours,
    required double sundayHours,
    required double kilometres,

    /// False leaves the kilometres on the form and the charge at nought.
    required bool chargeTravel,
    required int pmpFatTests,
    required int pmpProteinTests,
    required int pmpCalciumTests,
    required int pmpPhysicalTests,
    required int rawFatTests,
    required int rawProteinTests,
    required int rawSoyaTests,
    required int rawStarchTests,
    required int rawDnaTests,
    required int rawCalciumTests,
  }) {
    final bands = chargeableBands(
      normal: normalHours,
      overtime: overtimeHours,
      sunday: sundayHours,
    );
    final normal = bands.normal * InvoiceRates.normalHour;
    final overtime = bands.overtime * InvoiceRates.overtimeHour;
    final sunday = bands.sunday * InvoiceRates.sundayHour;
    final travel = chargeTravel ? kilometres * InvoiceRates.perKilometre : 0.0;

    final pmpLab = pmpFatTests * InvoiceRates.pmpFat +
        pmpProteinTests * InvoiceRates.pmpProtein +
        pmpCalciumTests * InvoiceRates.pmpCalcium +
        pmpPhysicalTests * InvoiceRates.pmpPhysical;

    final rawLab = rawFatTests * InvoiceRates.rawFat +
        rawProteinTests * InvoiceRates.rawProtein +
        rawSoyaTests * InvoiceRates.rawSoya +
        rawStarchTests * InvoiceRates.rawStarch +
        rawDnaTests * InvoiceRates.rawDna +
        rawCalciumTests * InvoiceRates.rawCalcium;

    final inspection = normal + overtime + sunday + travel;
    return InvoiceTotals(
      normal: normal,
      overtime: overtime,
      sunday: sunday,
      travel: travel,
      inspection: inspection,
      pmpLab: pmpLab,
      rawLab: rawLab,
      grand: inspection + pmpLab + rawLab,
    );
  }

  /// "R1 234.56" — the form's own notation: a space between thousands, two
  /// decimals, as every printed rate on it is written.
  static String rand(double amount) {
    final fixed = amount.toStringAsFixed(2);
    final parts = fixed.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return 'R$buffer.${parts.last}';
  }
}
