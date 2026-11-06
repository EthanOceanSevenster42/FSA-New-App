import 'package:drift/drift.dart';

import '../../../core/data/local_database.dart';

/// A scheduled follow-up: the date a facility was given to rectify a
/// deviation, which is when the inspector should return. Drawn from the
/// "correct by" dates captured on the inspections and the directions served.
class FollowUp {
  const FollowUp({
    required this.date,
    required this.facility,
    required this.detail,
    this.address = '',
    this.phone = '',
    this.inspectedOn,
    this.done = false,
  });

  /// The day the facility must have rectified by — the follow-up date.
  final DateTime date;

  /// The client/facility to return to.
  final String facility;

  /// Where the facility is — shown so the inspector knows where to go back to,
  /// and used to pre-fill a new visit started from the calendar.
  final String address;

  /// The facility's phone, used to pre-fill a new visit.
  final String phone;

  /// What the follow-up is for — the commodity, and labelling vs quality
  /// where the record distinguishes them.
  final String detail;

  /// The day the inspection that raised this follow-up was done, so the
  /// calendar can say "inspected on X → return by Y". Null when not known.
  final DateTime? inspectedOn;

  /// True once a later completed-and-signed visit exists for this facility —
  /// the return visit happened, so the follow-up is done.
  final bool done;

  FollowUp copyWith({bool? done, String? address, String? phone}) => FollowUp(
        date: date,
        facility: facility,
        detail: detail,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        inspectedOn: inspectedOn,
        done: done ?? this.done,
      );
}

/// Gathers every follow-up the handset knows about, across all commodities,
/// so the calendar can show which client to return to and when.
class FollowUpRepository {
  FollowUpRepository(this.database);

  final LocalDatabase database;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Every follow-up with a date, sorted earliest first.
  Future<List<FollowUp>> all() async {
    final out = <FollowUp>[];

    String facilityOf(String facility, String client) =>
        facility.trim().isNotEmpty
            ? facility.trim()
            : (client.trim().isNotEmpty ? client.trim() : 'Facility not named');

    // Poultry and egg directions carry no address of their own, so look it up
    // from their inspection by the shared client uuid.
    final poultryAddr = {
      for (final i in await database.select(database.poultryInspections).get())
        i.clientUuid: i.facilityAddress,
    };
    final eggAddr = {
      for (final i in await database.select(database.eggInspections).get())
        i.clientUuid: i.facilityAddress,
    };

    // Raw Processed Meat — the correct-by lives on the inspection.
    for (final r in await (database.select(database.rawRmpInspections)
          ..where((t) => t.correctByDate.isNotNull()))
        .get()) {
      out.add(FollowUp(
        date: _day(r.correctByDate!),
        facility: facilityOf(r.facilityName, ''),
        address: r.facilityAddress,
        phone: r.facilityTelephone,
        detail: 'Raw Processed Meat',
        inspectedOn: _day(r.inspectedAt),
      ));
    }

    // Processed Meat.
    for (final r in await (database.select(database.pmpInspections)
          ..where((t) => t.correctByDate.isNotNull()))
        .get()) {
      out.add(FollowUp(
        date: _day(r.correctByDate!),
        facility: facilityOf(r.facilityName, ''),
        address: r.facilityAddress,
        phone: r.facilityTelephone,
        detail: 'Processed Meat',
        inspectedOn: _day(r.inspectedAt),
      ));
    }

    // Poultry QUID weighing.
    for (final r in await (database.select(database.poultryQuidInspections)
          ..where((t) => t.correctByDate.isNotNull()))
        .get()) {
      out.add(FollowUp(
        date: _day(r.correctByDate!),
        facility: facilityOf(r.facilityName, r.clientName),
        address: r.facilityAddress,
        phone: r.facilityTelephone,
        detail: 'Poultry (QUID)',
        inspectedOn: _day(r.inspectedAt),
      ));
    }

    // Poultry — the correct-by lives on the direction served.
    for (final r in await (database.select(database.poultryDirections)
          ..where((t) => t.correctByDate.isNotNull()))
        .get()) {
      out.add(FollowUp(
        date: _day(r.correctByDate!),
        facility: facilityOf(r.facilityName, r.clientName),
        address: poultryAddr[r.clientUuid] ?? '',
        detail: 'Poultry',
        inspectedOn: _day(r.issuedAt),
      ));
    }

    // Eggs — labelling and quality keep separate correct-by dates.
    for (final r in await (database.select(database.eggDirections)
          ..where((t) =>
              t.labelCorrectBy.isNotNull() | t.qualityCorrectBy.isNotNull()))
        .get()) {
      if (r.labelCorrectBy != null) {
        out.add(FollowUp(
          date: _day(r.labelCorrectBy!),
          facility: facilityOf('', r.clientName),
          address: eggAddr[r.clientUuid] ?? '',
          detail: 'Eggs (labelling)',
          inspectedOn: _day(r.issuedAt),
        ));
      }
      if (r.qualityCorrectBy != null) {
        out.add(FollowUp(
          date: _day(r.qualityCorrectBy!),
          facility: facilityOf('', r.clientName),
          address: eggAddr[r.clientUuid] ?? '',
          detail: 'Eggs (quality)',
          inspectedOn: _day(r.issuedAt),
        ));
      }
    }

    // The address and phone live on the StoreVisit, not always copied onto the
    // commodity inspection — so fall back to the visit (by facility name) when
    // the follow-up's own are blank. And a follow-up is "done" once a later
    // completed-and-signed visit exists for the same facility.
    final completedByFacility = <String, List<DateTime>>{};
    final visitAddr = <String, String>{};
    final visitPhone = <String, String>{};
    for (final v in await database.select(database.storeVisits).get()) {
      final key = v.facilityName.trim().toLowerCase();
      if (v.completedAt != null) {
        completedByFacility.putIfAbsent(key, () => []).add(_day(v.completedAt!));
      }
      if (v.facilityAddress.trim().isNotEmpty) {
        visitAddr[key] = v.facilityAddress.trim();
      }
      if (v.facilityPhone.trim().isNotEmpty) {
        visitPhone[key] = v.facilityPhone.trim();
      }
    }

    final resolved = [
      for (final f in out)
        f.copyWith(
          address: f.address.trim().isNotEmpty
              ? f.address
              : (visitAddr[f.facility.trim().toLowerCase()] ?? ''),
          phone: f.phone.trim().isNotEmpty
              ? f.phone
              : (visitPhone[f.facility.trim().toLowerCase()] ?? ''),
          done: (completedByFacility[f.facility.trim().toLowerCase()] ??
                  const [])
              .any((c) => f.inspectedOn != null && c.isAfter(f.inspectedOn!)),
        ),
    ];
    resolved.sort((a, b) => a.date.compareTo(b.date));
    return resolved;
  }
}
