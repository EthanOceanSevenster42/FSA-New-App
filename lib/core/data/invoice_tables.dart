import 'package:drift/drift.dart';

/// The Request for Invoice form (SOP-APS-002), completed after a grouped
/// inspection and handed to the office so the visit can be billed.
///
/// One per grouped inspection: the visit is what the client is charged for,
/// however many commodities were inspected under it. Most of the form is
/// already known — who inspected, which site, which commodities, the date —
/// so the screen opens filled in and the inspector supplies only what the
/// app cannot know: the times, the hours claimed, the kilometres, and how
/// many laboratory tests were sent.
///
/// The rates live in code rather than here: they are the Agency's published
/// tariff, they change together, and a record must always be re-printable
/// with the rates that produced its totals — so the amounts are stored, not
/// recomputed from whatever the tariff happens to be later.
class InvoiceRequests extends Table {
  /// The grouped inspection this request bills for.
  TextColumn get visitUuid => text()();

  TextColumn get inspectorName => text().withDefault(const Constant(''))();
  TextColumn get siteVisited => text().withDefault(const Constant(''))();
  TextColumn get siteManager => text().withDefault(const Constant(''))();
  TextColumn get productName => text().withDefault(const Constant(''))();
  DateTimeColumn get dateOfVisit => dateTime()();

  /// "Inspection Time Started/Ended" — HH:mm as typed, because that is what
  /// goes on the form and what the office reconciles against.
  TextColumn get timeStarted => text().withDefault(const Constant(''))();
  TextColumn get timeEnded => text().withDefault(const Constant(''))();

  /// The form's tick boxes. Derived from what the visit actually holds, and
  /// still editable: an inspector may bill differently from what was
  /// captured, and the form is the billing document.
  BoolColumn get pmpTicked => boolean().withDefault(const Constant(false))();
  BoolColumn get rawRmpTicked => boolean().withDefault(const Constant(false))();
  BoolColumn get eggsTicked => boolean().withDefault(const Constant(false))();
  BoolColumn get poultryTicked =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get sampleTakingTicked =>
      boolean().withDefault(const Constant(false))();

  /// Hours claimed at each rate, and the distance travelled.
  RealColumn get normalHours => real().withDefault(const Constant(0))();
  RealColumn get overtimeHours => real().withDefault(const Constant(0))();
  RealColumn get sundayHours => real().withDefault(const Constant(0))();
  RealColumn get kilometres => real().withDefault(const Constant(0))();

  /// Laboratory tests sent — Processed Meat Products.
  IntColumn get pmpFatTests => integer().withDefault(const Constant(0))();
  IntColumn get pmpProteinTests => integer().withDefault(const Constant(0))();
  IntColumn get pmpCalciumTests => integer().withDefault(const Constant(0))();
  IntColumn get pmpPhysicalTests => integer().withDefault(const Constant(0))();

  /// Laboratory tests sent — Certain Raw Processed Meat Products.
  IntColumn get rawFatTests => integer().withDefault(const Constant(0))();
  IntColumn get rawProteinTests => integer().withDefault(const Constant(0))();
  IntColumn get rawSoyaTests => integer().withDefault(const Constant(0))();
  IntColumn get rawStarchTests => integer().withDefault(const Constant(0))();
  IntColumn get rawDnaTests => integer().withDefault(const Constant(0))();
  IntColumn get rawCalciumTests => integer().withDefault(const Constant(0))();

  /// What the totals came to when the form was completed, excluding VAT.
  RealColumn get inspectionTotal => real().withDefault(const Constant(0))();
  RealColumn get pmpLabTotal => real().withDefault(const Constant(0))();
  RealColumn get rawLabTotal => real().withDefault(const Constant(0))();
  RealColumn get grandTotal => real().withDefault(const Constant(0))();

  /// The two signatures the form carries. The grouped inspection already
  /// took both at sign-off, so these are copies of those images rather than
  /// a second act of signing.
  TextColumn get managerSignaturePath =>
      text().withDefault(const Constant(''))();
  TextColumn get inspectorSignaturePath =>
      text().withDefault(const Constant(''))();
  DateTimeColumn get signedAt => dateTime().nullable()();

  /// Where the rendered PDF was written, so it can be opened or shared
  /// again without re-rendering.
  TextColumn get pdfPath => text().withDefault(const Constant(''))();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {visitUuid};
}
