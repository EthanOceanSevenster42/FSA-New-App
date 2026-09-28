import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/data/local_database.dart';
import '../../../core/services/photo_storage.dart';
import '../../visits/data/visit_repository.dart';
import '../domain/invoice_rules.dart';
import '../domain/invoice_form_data.dart';
import 'invoice_pdf.dart';

/// Owns the Request for Invoice form: one per grouped inspection, opened
/// already filled in with everything the inspection already knows.
class InvoiceRepository {
  InvoiceRepository(this.database, this.visits);

  final LocalDatabase database;
  final VisitRepository visits;

  Future<InvoiceRequest?> byVisit(String visitUuid) =>
      (database.select(database.invoiceRequests)
            ..where((t) => t.visitUuid.equals(visitUuid)))
          .getSingleOrNull();

  /// The form as it should open: a saved one if the inspector has been here
  /// before, otherwise a fresh one built from the visit — who inspected,
  /// which site, which commodities, and the signatures already taken.
  Future<InvoiceRequestsCompanion> prefill(StoreVisit visit) async {
    final saved = await byVisit(visit.uuid);
    if (saved != null) return saved.toCompanion(true);

    final members = await visits.members(visit.uuid);
    final kinds = {for (final m in members) m.kind};
    final rawTests = await _rawTests(visit.uuid);
    final pmpTests = await _pmpTests(visit.uuid);
    // Eggs and poultry are inspected on the visit and shown on the form,
    // but their time is not charged for — only the raw and processed-meat
    // stretches are, and the form's own start and finish are those.
    final window = InvoiceRules.chargeableWindow(
      members: [
        for (final m in members) (kind: m.kind, inspectedAt: m.inspectedAt)
      ],
      visitStarted: visit.startedAt,
      visitEnded: visit.completedAt ?? DateTime.now(),
    );
    final hours = window.billable
        ? InvoiceRules.splitHours(window.start, window.end)
        : (normal: 0.0, overtime: 0.0, sunday: 0.0);

    // The signatures the sign-off already took: the form carries the same
    // two, so nobody signs twice for one visit.
    String signaturePath(String role) {
      final matches = Directory(_storagePath)
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.contains('visit_${visit.uuid}_') &&
              f.path.contains('_$role') &&
              f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.length.compareTo(b.path.length));
      return matches.isEmpty ? '' : matches.first.path;
    }

    return InvoiceRequestsCompanion.insert(
      visitUuid: visit.uuid,
      dateOfVisit: visit.startedAt,
      updatedAt: DateTime.now(),
      inspectorName: Value(visit.inspectorUsername),
      siteVisited: Value(visit.facilityName),
      siteManager: Value(visit.managerName.isNotEmpty
          ? visit.managerName
          : visit.contactPerson),
      // Every commodity captured under the visit, named as the form names
      // them — the inspector edits it if the billing wording differs.
      productName: Value([
        if (kinds.contains('egg')) 'Eggs',
        if (kinds.contains('poultry')) 'Poultry Meat',
        if (kinds.contains('poultry_label')) 'Label/Container',
        if (kinds.contains('rawrmp')) 'Certain Raw Processed Meat Products',
        if (kinds.contains('pmp')) 'Processed Meat Products',
      ].join(', ')),
      pmpTicked: Value(kinds.contains('pmp')),
      rawRmpTicked: Value(kinds.contains('rawrmp')),
      eggsTicked: Value(kinds.contains('egg')),
      poultryTicked:
          Value(kinds.contains('poultry') || kinds.contains('poultry_label')),
      sampleTakingTicked: Value(await _anySampleTaken(visit.uuid)),
      // The charged window, worked out above, and split across the
      // tariff's three bands.
      timeStarted: Value(InvoiceRules.clock(window.start)),
      timeEnded: Value(InvoiceRules.clock(window.end)),
      normalHours: Value(hours.normal),
      overtimeHours: Value(hours.overtime),
      sundayHours: Value(hours.sunday),
      // The distance the raw-meat and processed-meat forms recorded, which
      // is the only kilometre figure the capture screens ask for.
      kilometres: Value(await _kilometres(visit.uuid)),
      // The laboratory lines follow from the test category chosen on each
      // sampled raw-meat inspection; the office does not count them again.
      rawFatTests: Value(rawTests.fat),
      rawProteinTests: Value(rawTests.protein),
      rawSoyaTests: Value(rawTests.soya),
      rawStarchTests: Value(rawTests.starch),
      rawDnaTests: Value(rawTests.dna),
      // Processed meat samples bill the same way. The lines existed on the
      // sheet and in the tariff, but nothing ever counted them, so a visit
      // that took two PMP samples invoiced for time and kilometres only.
      pmpFatTests: Value(pmpTests.fat),
      pmpProteinTests: Value(pmpTests.protein),
      managerSignaturePath: Value(signaturePath('manager')),
      inspectorSignaturePath: Value(signaturePath('inspector')),
      signedAt: Value(visit.completedAt),
    );
  }

  String _storagePath = '';

  /// Resolved once, before any prefill: listing the evidence folder needs a
  /// path and PhotoStorage is the only thing that knows it.
  Future<void> ready() async {
    _storagePath = (await PhotoStorage.instance()).path;
  }

  Future<bool> _anySampleTaken(String visitUuid) async {
    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid) & t.isSampled))
        .get();
    if (raw.isNotEmpty) return true;
    final pmp = await (database.select(database.pmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid) & t.isSampled))
        .get();
    return pmp.isNotEmpty;
  }

  /// What each sampled processed-meat inspection sends to the laboratory.
  ///
  /// PMP has no test-category picker — the original has none either — so
  /// there is nothing to read a category off. A sampled processed meat
  /// product goes for its compositional analysis, which is the fat and
  /// protein pair the tariff's first two PMP lines charge for; that is the
  /// same pair raw's Category A bills.
  ///
  /// Calcium (MRM only) and the physical test (coated products) stay at
  /// zero: neither this screen nor the original asks whether they were
  /// requested, so counting them would invoice for tests nobody ordered.
  Future<({int fat, int protein})> _pmpTests(String visitUuid) async {
    final sampled = await (database.select(database.pmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid) & t.isSampled))
        .get();
    return (fat: sampled.length, protein: sampled.length);
  }

  /// What each sampled raw-meat inspection sends to the laboratory, read
  /// off the category the inspector picked on the form:
  ///
  ///  * Category A — meat (protein) and fat content: one fat, one protein;
  ///  * Category B — soya protein and starch: one soya, one starch;
  ///  * Category C — species identification: one DNA;
  ///  * Category D — fat content only: one fat.
  ///
  /// Matched on the category's letter rather than its id, so a re-seeded
  /// directory cannot silently shift the money onto the wrong line.
  Future<({int fat, int protein, int soya, int starch, int dna})> _rawTests(
      String visitUuid) async {
    final sampled = await (database.select(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid) & t.isSampled))
        .get();
    final categories = {
      for (final c
          in await database.select(database.rawRmpSampleCategories).get())
        c.id: c.name,
    };
    var fat = 0, protein = 0, soya = 0, starch = 0, dna = 0;
    for (final row in sampled) {
      final name = categories[row.sampleCategoryId] ?? '';
      final letter = RegExp(r'Category\s+([A-D])', caseSensitive: false)
          .firstMatch(name)
          ?.group(1)
          ?.toUpperCase();
      if (letter == 'A') {
        fat += 1;
        protein += 1;
      } else if (letter == 'B') {
        soya += 1;
        starch += 1;
      } else if (letter == 'C') {
        dna += 1;
      } else if (letter == 'D') {
        fat += 1;
      }
    }
    return (fat: fat, protein: protein, soya: soya, starch: starch, dna: dna);
  }

  /// The kilometres billed for the trip.
  ///
  /// Off the visit, which is where the question is now asked: one journey to
  /// one facility, whatever was inspected there. A visit with no raw
  /// inspection on it had no kilometres at all before, because the only
  /// place the figure was captured was the raw form.
  Future<double> _kilometres(String visitUuid) async {
    final visit = await (database.select(database.storeVisits)
          ..where((t) => t.uuid.equals(visitUuid)))
        .getSingleOrNull();
    final onVisit = visit?.distanceTravelledKm ?? 0;
    if (onVisit > 0) return onVisit;
    // Visits captured before the question moved to the door still carry it
    // on their raw records.
    final raw = await (database.select(database.rawRmpInspections)
          ..where((t) => t.visitUuid.equals(visitUuid)))
        .get();
    for (final row in raw) {
      final km = row.distanceTravelledKm ?? 0;
      if (km > 0) return km;
    }
    return 0;
  }

  Future<void> save(InvoiceRequestsCompanion form) =>
      database.into(database.invoiceRequests).insertOnConflictUpdate(form);

  /// The whole errand behind one call: build the form from the inspection
  /// if it has not been built before, store what it totalled to, and hand
  /// back the record ready to render.
  Future<InvoiceRequest> formFor(StoreVisit visit) async {
    await ready();
    final draft = await prefill(visit);
    final totals = totalsOf(draft);
    final withTotals = draft.copyWith(
      inspectionTotal: Value(totals.inspection),
      pmpLabTotal: Value(totals.pmpLab),
      rawLabTotal: Value(totals.rawLab),
      grandTotal: Value(totals.grand),
      updatedAt: Value(DateTime.now()),
    );
    await save(withTotals);
    return (await byVisit(visit.uuid))!;
  }

  /// Renders the form and remembers where the file went, so it can be opened
  /// or shared again without re-rendering.
  Future<File> renderPdf(InvoiceRequest form) async {
    final storage = await PhotoStorage.instance();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeSite = form.siteVisited
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final file = await InvoicePdf.write(
      _formData(form),
      outputPath: storage.pathFor(
          'request-for-invoice_${safeSite.isEmpty ? 'inspection' : safeSite}'
          '_$stamp.pdf'),
    );
    await (database.update(database.invoiceRequests)
          ..where((t) => t.visitUuid.equals(form.visitUuid)))
        .write(InvoiceRequestsCompanion(pdfPath: Value(file.path)));
    return file;
  }

  /// The totals as the form computes them, for the screen to show live.
  ///
  /// Every field is read through [_or]: a companion built by `insert` leaves
  /// defaulted columns absent, and reading `.value` off an absent one throws
  /// rather than giving the column's default.
  InvoiceTotals totalsOf(InvoiceRequestsCompanion form) => InvoiceRules.totals(
        normalHours: _or(form.normalHours, 0),
        overtimeHours: _or(form.overtimeHours, 0),
        sundayHours: _or(form.sundayHours, 0),
        kilometres: _or(form.kilometres, 0),
        chargeTravel: InvoiceRules.travelIsChargeable(
          rawRmp: _or(form.rawRmpTicked, false),
          pmp: _or(form.pmpTicked, false),
        ),
        pmpFatTests: _or(form.pmpFatTests, 0),
        pmpProteinTests: _or(form.pmpProteinTests, 0),
        pmpCalciumTests: _or(form.pmpCalciumTests, 0),
        pmpPhysicalTests: _or(form.pmpPhysicalTests, 0),
        rawFatTests: _or(form.rawFatTests, 0),
        rawProteinTests: _or(form.rawProteinTests, 0),
        rawSoyaTests: _or(form.rawSoyaTests, 0),
        rawStarchTests: _or(form.rawStarchTests, 0),
        rawDnaTests: _or(form.rawDnaTests, 0),
        rawCalciumTests: _or(form.rawCalciumTests, 0),
      );

  static T _or<T>(Value<T> value, T fallback) =>
      value.present ? value.value : fallback;

  /// The saved row as the plain values the form is drawn from.
  static InvoiceFormData _formData(InvoiceRequest form) => InvoiceFormData(
        inspectorName: form.inspectorName,
        siteVisited: form.siteVisited,
        siteManager: form.siteManager,
        productName: form.productName,
        dateOfVisit: form.dateOfVisit,
        timeStarted: form.timeStarted,
        timeEnded: form.timeEnded,
        pmpTicked: form.pmpTicked,
        rawRmpTicked: form.rawRmpTicked,
        eggsTicked: form.eggsTicked,
        poultryTicked: form.poultryTicked,
        sampleTakingTicked: form.sampleTakingTicked,
        normalHours: form.normalHours,
        overtimeHours: form.overtimeHours,
        sundayHours: form.sundayHours,
        kilometres: form.kilometres,
        pmpFatTests: form.pmpFatTests,
        pmpProteinTests: form.pmpProteinTests,
        pmpCalciumTests: form.pmpCalciumTests,
        pmpPhysicalTests: form.pmpPhysicalTests,
        rawFatTests: form.rawFatTests,
        rawProteinTests: form.rawProteinTests,
        rawSoyaTests: form.rawSoyaTests,
        rawStarchTests: form.rawStarchTests,
        rawDnaTests: form.rawDnaTests,
        rawCalciumTests: form.rawCalciumTests,
        managerSignaturePath: form.managerSignaturePath,
        inspectorSignaturePath: form.inspectorSignaturePath,
        signedAt: form.signedAt,
      );
}
