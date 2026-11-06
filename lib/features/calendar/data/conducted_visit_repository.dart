import 'package:drift/drift.dart';

import '../../../core/data/local_database.dart';
import '../../visits/data/visit_repository.dart';

/// An inspection that was actually carried out — a store visit signed off.
///
/// The calendar's third kind of entry, and the only one that is a record of
/// something that happened rather than something owed or intended. It sits
/// on the day the visit was signed off, which is the day the inspector was
/// at the premises.
class ConductedVisit {
  const ConductedVisit({
    required this.uuid,
    required this.date,
    required this.facility,
    required this.completedAt,
    this.address = '',
    this.commodities = const [],
    this.isOccurrenceReport = false,
  });

  final String uuid;

  /// The day it was signed off, at midnight, so it keys the grid.
  final DateTime date;

  /// The same moment with its time, for "signed off at 14:20".
  final DateTime completedAt;

  final String facility;
  final String address;

  /// What was captured under the visit, named the way the inspector would
  /// say it. Empty on an occurrence report, which has no inspections.
  final List<String> commodities;

  final bool isOccurrenceReport;
}

/// Reads the visits already done, for the calendar to show alongside what
/// is planned and what is due back.
class ConductedVisitRepository {
  ConductedVisitRepository(this.database, this.visits);

  final LocalDatabase database;

  /// Used only for [VisitRepository.membersForVisits], which fetches the
  /// commodities of the whole set in one query per table rather than six
  /// per visit.
  final VisitRepository visits;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// One name per commodity, in a fixed order so two visits covering the
  /// same ground read the same way. A visit commonly holds two poultry
  /// records or a grading and its labelling sheet; the calendar wants the
  /// commodities, not the count.
  static const _names = {
    'egg': 'Eggs',
    'poultry': 'Poultry',
    'poultry_label': 'Poultry',
    'quid': 'Poultry (QUID)',
    'rawrmp': 'Raw Processed Meat',
    'pmp': 'Processed Meat',
  };

  static List<String> _commoditiesOf(List<VisitMember> members) {
    final seen = <String>{};
    for (final m in members) {
      final name = _names[m.kind];
      if (name != null) seen.add(name);
    }
    return [
      for (final name in _names.values)
        if (seen.remove(name)) name,
    ];
  }

  /// Whose work to show.
  ///
  /// The same tolerant reading of ownership the planning and inspection
  /// tables use: a visit captured before anyone was signed in has no owner
  /// and belongs to whoever is holding the handset. Matched without case,
  /// so `Lwandile.D` at sign-in still finds work saved as `lwandile.d`.
  Expression<bool> _ownedBy(GeneratedColumn<String> column, String? owner) =>
      owner == null || owner.trim().isEmpty
          ? column.isNull() | column.equals('')
          : column.isNull() |
              column.equals('') |
              column.lower().equals(owner.trim().toLowerCase());

  /// Every signed-off visit on the handset, most recent first.
  ///
  /// Signed off, not merely started: a visit still being captured is not an
  /// inspection that was conducted, and putting it on the calendar as one
  /// would say work was done that nobody has finished.
  Future<List<ConductedVisit>> all(String? inspector) async {
    final rows = await (database.select(database.storeVisits)
          ..where((t) =>
              t.completedAt.isNotNull() &
              _ownedBy(t.inspectorUsername, inspector))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.completedAt, mode: OrderingMode.desc),
          ]))
        .get();
    if (rows.isEmpty) return const [];

    final members = await visits.membersForVisits([for (final r in rows) r.uuid]);

    return [
      for (final r in rows)
        ConductedVisit(
          uuid: r.uuid,
          date: _day(r.completedAt!),
          completedAt: r.completedAt!,
          facility: r.facilityName.trim().isEmpty
              ? 'Facility not named'
              : r.facilityName.trim(),
          address: r.facilityAddress.trim(),
          isOccurrenceReport: r.isOccurrenceReport,
          commodities: _commoditiesOf(members[r.uuid] ?? const []),
        ),
    ];
  }
}
