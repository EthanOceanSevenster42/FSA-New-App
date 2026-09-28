/// Everything the Request for Invoice prints, as plain data.
///
/// The form is drawn from a saved record on the handset, but the drawing
/// itself has no business knowing about the database — keeping it to plain
/// values is what lets the Agency's forms be rendered by a command-line
/// tool as well as by the app, and tested without one.
class InvoiceFormData {
  const InvoiceFormData({
    required this.inspectorName,
    required this.siteVisited,
    required this.siteManager,
    required this.productName,
    required this.dateOfVisit,
    this.timeStarted = '',
    this.timeEnded = '',
    this.pmpTicked = false,
    this.rawRmpTicked = false,
    this.eggsTicked = false,
    this.poultryTicked = false,
    this.sampleTakingTicked = false,
    this.normalHours = 0,
    this.overtimeHours = 0,
    this.sundayHours = 0,
    this.kilometres = 0,
    this.pmpFatTests = 0,
    this.pmpProteinTests = 0,
    this.pmpCalciumTests = 0,
    this.pmpPhysicalTests = 0,
    this.rawFatTests = 0,
    this.rawProteinTests = 0,
    this.rawSoyaTests = 0,
    this.rawStarchTests = 0,
    this.rawDnaTests = 0,
    this.rawCalciumTests = 0,
    this.managerSignaturePath = '',
    this.inspectorSignaturePath = '',
    this.signedAt,
  });

  final String inspectorName;
  final String siteVisited;
  final String siteManager;
  final String productName;
  final DateTime dateOfVisit;
  final String timeStarted;
  final String timeEnded;

  /// Which commodities the visit covered.
  final bool pmpTicked;
  final bool rawRmpTicked;
  final bool eggsTicked;
  final bool poultryTicked;
  final bool sampleTakingTicked;

  final double normalHours;
  final double overtimeHours;
  final double sundayHours;
  final double kilometres;

  /// The laboratory determinations the visit is billed for.
  final int pmpFatTests;
  final int pmpProteinTests;
  final int pmpCalciumTests;
  final int pmpPhysicalTests;
  final int rawFatTests;
  final int rawProteinTests;
  final int rawSoyaTests;
  final int rawStarchTests;
  final int rawDnaTests;
  final int rawCalciumTests;

  final String managerSignaturePath;
  final String inspectorSignaturePath;
  final DateTime? signedAt;
}
