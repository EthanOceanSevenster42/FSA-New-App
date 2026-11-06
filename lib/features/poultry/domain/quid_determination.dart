/// How a QUID inspection is judged.
///
/// The original does the arithmetic in the page's code-behind and the report
/// does it again in SQL, which is how the two came to disagree. It lives here
/// once so the screen the inspector reads and the sheet the office files
/// cannot say different things about the same weighings.
///
/// Source: `ContinuePoultryInjectionInspectionPage.DoCurrentSampleQUIDPercen`
/// `tageCalulation` and `DoOverallInjectorQUIDPercentageCalculationsV2` in the
/// original application, with the limits from its `Constants`.
library;

/// The minimum carcasses an injector needs before its average means anything
/// — `MinSampleSetSize` in the original.
const int quidMinimumSampleSet = 5;

/// How far over the set percentage an injector may run before it is a
/// non-conformance. The regulation allows more on portions than on whole
/// carcasses, because a cut absorbs more.
///
/// Whole carcasses 1%, portions 2.5% — a 15% injector may run to 17.5%
/// (Ethan, 2026-11-05, reversing the 1.5% set on Neo Noe's review of
/// 2026-10-19).
const double quidWholeCarcassTolerance = 1.0;
const double quidCutPortionTolerance = 2.5;

/// The regulated maxima, used where the plant has no dispensation of its
/// own: 10% on whole carcasses and 15% on portions (Ethan, confirmed
/// 2026-10-08). Same as the legacy `Constants`, and consistent with the
/// tolerances above giving portions the larger allowance (a cut absorbs more).
const double quidWholeCarcassMaximum = 10.0;
const double quidCutPortionMaximum = 15.0;

/// What water chilling may add to a carcass: the regulation calls it
/// absorbed moisture and allows less than 7% pick-up — Regulation 4(2) of
/// the Poultry Consolidated Regulations, page 4 (Neo Noe, 2026-10-19).
///
/// A separate limit from QUID, and not the one the sheet used to be read
/// against: it printed the allowable QUID (10% or 15%) over the pick-up
/// column, so a chiller running at 12% passed on a portion line.
const double quidWaterChillMaximumPickup = 7.0;

/// Whether an average water-chilling pick-up is within Reg. 4(2).
///
/// Null while nothing has been weighed — "not measured" and "absorbed
/// nothing" are different findings, as everywhere else on this sheet.
bool? quidWaterChillWithinLimit(String averagePickupPercent) {
  final average = quidNumber(averagePickupPercent);
  if (average == null) return null;
  return average < quidWaterChillMaximumPickup;
}

/// A percentage as the regulation takes it: the gain over the mass at the END
/// of the step, not the start.
///
/// Empty rather than zero when either mass is missing — "not weighed" and
/// "gained nothing" are different findings.
String quidPercentOf(double? initial, double? finalMass) {
  if (initial == null || finalMass == null || finalMass <= 0) return '';
  return (((finalMass - initial) / finalMass) * 100).toStringAsFixed(3);
}

/// Parses a figure that may carry a stray percent sign.
double? quidNumber(String? text) {
  if (text == null) return null;
  return double.tryParse(text.replaceAll('%', '').trim());
}

/// The mean of the figures that are actually present.
///
/// Carcasses still being weighed are skipped rather than counted as zero,
/// which would drag the average down mid-inspection.
String quidMean(Iterable<String> figures) {
  final values = [
    for (final f in figures)
      if (quidNumber(f) != null) quidNumber(f)!,
  ];
  if (values.isEmpty) return '';
  return (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(3);
}

/// What one injector produced, and whether that passes.
class QuidInjectorVerdict {
  const QuidInjectorVerdict({
    required this.position,
    required this.name,
    required this.setPercent,
    required this.averagePercent,
    required this.sampleCount,
    required this.limitPercent,
  });

  final int position;
  final String name;

  /// What the plant says the injector is set to.
  final String setPercent;

  /// The mean QUID of the carcasses this injector ran.
  final String averagePercent;
  final int sampleCount;

  /// The set percentage plus the tolerance for the portion type, or the
  /// regulated maximum where the injector carries no setting.
  final double limitPercent;

  bool get hasSufficientSamples => sampleCount >= quidMinimumSampleSet;

  /// Null until there are enough carcasses to judge on, or while nothing has
  /// been weighed. The original greys the figure out in exactly that case
  /// rather than passing or failing it.
  bool? get passes {
    final average = quidNumber(averagePercent);
    if (average == null || !hasSufficientSamples) return null;
    return average <= limitPercent;
  }

  String get verdict => switch (passes) {
        true => 'PASS',
        false => 'FAIL',
        null => sampleCount == 0
            ? ''
            : 'Min. $quidMinimumSampleSet carcasses ($sampleCount weighed)',
      };
}

/// One carcass, as far as the judgement is concerned.
typedef QuidWeighing = ({int? assignedInjector, String quidPercent});

/// One injector on the set-up.
typedef QuidInjectorSetup = ({int position, String name, String quidPercent});

/// Judges every injector on the set-up against the carcasses assigned to it.
List<QuidInjectorVerdict> quidVerdicts({
  required List<QuidInjectorSetup> injectors,
  required List<QuidWeighing> weighings,
  required bool isWholeCarcass,
}) {
  final tolerance =
      isWholeCarcass ? quidWholeCarcassTolerance : quidCutPortionTolerance;
  final regulated =
      isWholeCarcass ? quidWholeCarcassMaximum : quidCutPortionMaximum;
  return [
    for (final injector in injectors)
      () {
        final mine = [
          for (final w in weighings)
            if (w.assignedInjector == injector.position &&
                quidNumber(w.quidPercent) != null)
              w.quidPercent,
        ];
        final set = quidNumber(injector.quidPercent);
        return QuidInjectorVerdict(
          position: injector.position,
          name: injector.name,
          setPercent: injector.quidPercent,
          averagePercent: quidMean(mine),
          sampleCount: mine.length,
          limitPercent: set == null ? regulated : set + tolerance,
        );
      }(),
  ];
}
