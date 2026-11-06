import 'package:drift/drift.dart';

/// A visit an inspector intends to make — their own plan for the week.
///
/// The calendar already shows where the inspector *must* go back to: the
/// "correct by" dates read off the records. That is the half the system
/// knows. The other half lives in a notebook — the depots to call on
/// Tuesday, the abattoir across town to fit in on the way back — and the
/// office never sees it until the work is done. A row here is that second
/// half written down on the same calendar.
///
/// It is deliberately a plan, not an inspection. Nothing is filed from it
/// and nothing is sent anywhere; it holds only what the inspector needs in
/// order to arrive — who, where, what for — and enough to start the real
/// inspection pre-filled when the day comes. [startedVisitUuid] is the
/// store visit that was opened from it, which is what makes a plan read as
/// done rather than merely past.
class PlannedVisits extends Table {
  TextColumn get uuid => text()();

  /// Whose plan it is. A plan is personal, so a handset shared between two
  /// inspectors does not show one the other's week. Rows written before a
  /// session was stored carry an empty string and are shown to everyone,
  /// the same reading of ownership the inspection tables use.
  TextColumn get inspectorUsername => text().withDefault(const Constant(''))();

  /// The day it is planned for, at midnight. The day only: an inspector
  /// planning six stops cannot say which hour each will fall in, and a
  /// made-up time on the calendar is worse than none.
  DateTimeColumn get plannedFor => dateTime()();

  TextColumn get facilityName => text().withDefault(const Constant(''))();
  TextColumn get facilityAddress => text().withDefault(const Constant(''))();
  TextColumn get facilityPhone => text().withDefault(const Constant(''))();

  /// What the visit is for, as a comma-separated list.
  ///
  /// More than one, because a visit is more than one: the grouped
  /// inspection the handset captures holds every commodity found at the
  /// premises, so a single call can be raw processed meat and eggs
  /// together. A plan that could name only one would be wrong about most
  /// of the week.
  TextColumn get commodity => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// The store visit opened from this plan, empty until it is started.
  TextColumn get startedVisitUuid => text().withDefault(const Constant(''))();

  /// The office put this visit on the calendar, rather than the inspector
  /// planning it themselves.
  ///
  /// It changes what the app lets them do with it. They open the
  /// inspection from it the same way, but cannot move, edit or delete it:
  /// somebody at the office is relying on this call being made, and a plan
  /// that could be quietly dropped would not be worth scheduling. Their
  /// own plans stay entirely their own.
  BoolColumn get scheduledByOffice =>
      boolean().withDefault(const Constant(false))();

  /// Who at the office scheduled it, so the card can say whose instruction
  /// it is rather than just "the office". Blank on a plan the inspector
  /// made.
  TextColumn get scheduledBy => text().withDefault(const Constant(''))();

  /// Removed by the inspector.
  ///
  /// Kept as a mark rather than deleting the row, because the office has
  /// a copy: the handset has to be able to say "this one is gone", and a
  /// row that simply stopped being mentioned says nothing — an inspector
  /// with a second handset would otherwise have each one deleting the
  /// other's week on every sync. Hidden everywhere in the app; it exists
  /// only to carry the news up once.
  BoolColumn get removed => boolean().withDefault(const Constant(false))();

  /// True once the server has this row as it currently stands. Cleared by
  /// every edit, so a plan changed offline goes up again.
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {uuid};
}
