import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../eggs/presentation/summary_widgets.dart';
import '../../poultry/domain/quid_determination.dart';
import '../../poultry/domain/quid_flow.dart';
import '../../seizures/data/seizure_repository.dart';
import '../../seizures/presentation/record_seizure.dart';
import 'record_documents_section.dart';

/// A captured poultry, Processed Meat or Raw Processed Meat inspection,
/// read-only: the particulars, what the checklist found, the sampling, and
/// the photographs and signatures held against it.
///
/// One page for the three because they are the same shape — a facility, a
/// product, a tick-list and the shared evidence store — and three screens
/// that differ only in which rows they name would drift apart.
class CommodityInspectionViewPage extends StatefulWidget {
  const CommodityInspectionViewPage({
    super.key,
    required this.database,
    required this.kind,
    required this.uuid,
    required this.title,
    required this.uploaded,
    required this.status,
    this.onEdit,
  });

  final LocalDatabase database;

  /// 'poultry' | 'pmp' | 'rawrmp' | 'poultry_label'
  final String kind;
  final String uuid;
  final String title;
  final bool uploaded;
  final String status;

  /// Reopens this record for correction, then returns true if anything was
  /// saved. Supplied by the page that knows how to build the commodity's
  /// own form; absent where a record is only ever read.
  final Future<bool> Function()? onEdit;

  @override
  State<CommodityInspectionViewPage> createState() =>
      _CommodityInspectionViewPageState();
}

class _CommodityInspectionViewPageState
    extends State<CommodityInspectionViewPage> {
  /// Label/value rows, built per commodity.
  List<(String, String)> _rows = const [];

  /// The direction this inspection raised, if it raised one: what was
  /// served on the client is part of the record, not a separate errand.
  List<(String, String)> _directionRows = const [];
  List<String> _directionRemarks = const [];
  List<String> _directionFindings = const [];
  bool _hasDirection = false;

  /// The seizure served off this inspection, when there was one.
  Seizure? _seizure;

  List<PoultryPhoto> _photos = const [];
  List<PoultrySignature> _signatures = const [];
  bool _loading = true;
  bool _missing = false;

  /// True while the form is being opened, so the button cannot be pressed
  /// twice into two copies of the same record.
  bool _editing = false;

  Future<void> _edit() async {
    final open = widget.onEdit;
    if (open == null || _editing) return;
    setState(() => _editing = true);
    try {
      final saved = await open();
      if (!mounted) return;
      // Reloaded either way: an inspector who backed out should not be left
      // looking at a page that might not match the record any more.
      await _load();
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Correction saved. Run Server Sync to send it to '
              'the office.'),
          duration: Duration(seconds: 6),
        ));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _dmy(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _yesNo(bool value) => value ? 'Yes' : 'No';

  static int _idCount(String csv) =>
      csv.split(',').where((p) => int.tryParse(p.trim()) != null).length;

  static Set<int> _ids(String csv) => {
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      };

  /// The rows of a present section that were left unticked — the findings
  /// the direction was raised for, by name.
  ///
  /// Poultry's list has no sections, so an empty [present] means every row
  /// applies.
  Future<List<String>> _deviationsOf(
    String checklistTable,
    Set<String> present,
    Set<int> ticked,
  ) async {
    final rows = await widget.database
        .customSelect('SELECT id, section, description FROM $checklistTable '
            'WHERE is_active = 1 ORDER BY sort_order')
        .get();
    final found = <String>[];
    for (final row in rows) {
      final id = row.data['id'] as int?;
      final section = row.data['section'] as String? ?? '';
      if (id == null || ticked.contains(id)) continue;
      if (present.isNotEmpty && !present.contains(section)) continue;
      found.add(row.data['description'] as String? ?? 'Item $id');
    }
    return found;
  }

  Future<String> _nameOf(String table, int? id) async {
    if (id == null) return '';
    final rows = await widget.database.customSelect(
        'SELECT name FROM $table WHERE id = ?',
        variables: [Variable<int>(id)]).get();
    return rows.isEmpty ? '' : (rows.first.data['name'] as String? ?? '');
  }

  Future<void> _load() async {
    final database = widget.database;
    final rows = <(String, String)>[];

    switch (widget.kind) {
      case 'rawrmp':
        final r = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (r == null) break;
        // SOP-APS-RAW-003: offered only when the checklist was answered.
        rows.addAll([
          ('Facility', r.facilityName),
          ('Address', r.facilityAddress),
          ('Telephone / cellphone', r.facilityTelephone),
          ('Contact person', r.contactPerson),
          ('Inspected', _dmy(r.inspectedAt)),
          (
            'Location',
            await _nameOf('raw_rmp_inspection_locations', r.locationId)
          ),
          ('Reason', await _nameOf('raw_rmp_inspection_reasons', r.reasonId)),
          (
            'Producer',
            r.producerName.isEmpty ? r.newProducerDetails : r.producerName
          ),
          ('Product', r.productItem.isEmpty ? r.newProductItem : r.productItem),
          ('Batch number', r.batchNumber),
          ('Manufactured/packed', r.manufacturedPackedDate),
          ('Storage', await _nameOf('raw_rmp_storage_types', r.storageTypeId)),
          ('Compliant items', '${_idCount(r.compliantItemIds)} ticked'),
          ('Sample taken', _yesNo(r.isSampled)),
          if (r.isSampled) ('Internal sample no.', r.internalSampleNumber),
          if (r.isSampled)
            (
              'Laboratory',
              await _nameOf('raw_rmp_laboratories', r.laboratoryId)
            ),
          (
            'Distance travelled',
            r.distanceTravelledKm == null ? '' : '${r.distanceTravelledKm} km'
          ),
          ('Comments', r.nonConformanceComments),
        ]);
      case 'pmp':
        final r = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (r == null) break;
        rows.addAll([
          ('Facility', r.facilityName),
          ('Address', r.facilityAddress),
          ('Telephone / cellphone', r.facilityTelephone),
          ('Contact person', r.contactPerson),
          ('Inspected', _dmy(r.inspectedAt)),
          ('Location', await _nameOf('pmp_inspection_locations', r.locationId)),
          ('Reason', await _nameOf('pmp_inspection_reasons', r.reasonId)),
          (
            'Producer',
            r.producerName.isEmpty ? r.newProducerDetails : r.producerName
          ),
          ('Product', r.productItem.isEmpty ? r.newProductItem : r.productItem),
          ('Batch number', r.batchNumber),
          ('Manufactured/packed', r.manufacturedPackedDate),
          ('Storage', await _nameOf('pmp_storage_types', r.storageTypeId)),
          ('Compliant items', '${_idCount(r.compliantItemIds)} ticked'),
          ('Recipe available', _yesNo(r.recipeAvailable)),
          ('Sample taken', _yesNo(r.isSampled)),
          if (r.isSampled) ('Internal sample no.', r.internalSampleNumber),
          if (r.isSampled)
            ('Laboratory', await _nameOf('pmp_laboratories', r.laboratoryId)),
          ('Comments', r.nonConformanceComments),
        ]);
      case 'poultry_label':
        final r = await (database.select(database.poultryLabelInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (r == null) break;
        rows.addAll([
          ('Facility', r.facilityName),
          ('Address', r.facilityAddress),
          ('Telephone / cellphone', r.facilityTelephone),
          ('Contact person', r.contactPerson),
          ('Inspected', _dmy(r.inspectedAt)),
          (
            'Location',
            await _nameOf('poultry_inspection_locations', r.locationId)
          ),
          ('Reason', await _nameOf('poultry_inspection_reasons', r.reasonId)),
          ('Compliant items', '${_idCount(r.compliantItemIds)} ticked'),
        ]);
      case 'quid':
        // Read back on its own terms. Falling to the default looked a QUID
        // uuid up in the grading table, found nothing, and showed the record
        // as missing.
        final r = await (database.select(database.poultryQuidInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (r == null) break;
        final samples = await (database.select(database.poultryQuidSamples)
              ..where((t) => t.inspectionUuid.equals(widget.uuid)))
            .get();
        final injectors = await (database.select(database.poultryQuidInjectors)
              ..where((t) => t.inspectionUuid.equals(widget.uuid)))
            .get();
        final verdicts = quidVerdicts(
          injectors: [
            for (final i in injectors)
              (position: i.position, name: i.name, quidPercent: i.quidPercent),
          ],
          weighings: [
            for (final sample in quidLastRound(samples, (s) => s.iteration))
              (
                assignedInjector: int.tryParse(sample.assignedInjector),
                quidPercent: sample.quidPercent,
              ),
          ],
          isWholeCarcass: r.isWholeCarcass,
        );
        rows.addAll([
          ('Facility', r.facilityName),
          ('Address', r.facilityAddress),
          ('Telephone / cellphone', r.facilityTelephone),
          ('Contact person', r.contactPerson),
          ('Inspected', _dmy(r.inspectedAt)),
          (
            'Location',
            await _nameOf('poultry_inspection_locations', r.locationId)
          ),
          ('Reason', await _nameOf('poultry_inspection_reasons', r.reasonId)),
          ('Registration number', r.companyRegNumber),
          ('Chilling method', r.isWaterChilled ? 'Water' : 'Air'),
          ('Portion type', r.isWholeCarcass ? 'Whole carcass' : 'Cuts'),
          ('Allowable QUID (%)', r.dispensationQuidPercent),
          ('Iteration', r.iterationNumber),
          ('Carcasses weighed', '${samples.length}'),
          ('Average QUID (%)', r.quidPercent),
          // The finding itself, per injector, as the sheet states it.
          for (final v in verdicts)
            (
              v.name.isEmpty ? 'Injector ${v.position}' : v.name,
              v.averagePercent.isEmpty
                  ? 'Nothing weighed'
                  : '${v.averagePercent}% against '
                      '${v.limitPercent.toStringAsFixed(3)}% — ${v.verdict}',
            ),
          ('Records verified', r.documentName),
          ('Comments', r.generalComments),
        ]);
      default:
        final r = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (r == null) break;
        rows.addAll([
          ('Facility', r.facilityName),
          ('Address', r.facilityAddress),
          ('Telephone / cellphone', r.facilityTelephone),
          ('Contact person', r.contactPerson),
          ('Inspected', _dmy(r.inspectedAt)),
          (
            'Location',
            await _nameOf('poultry_inspection_locations', r.locationId)
          ),
          ('Reason', await _nameOf('poultry_inspection_reasons', r.reasonId)),
          ('Producer/trading name', r.producerTradingName),
          ('Meat type', await _nameOf('poultry_meat_types', r.meatTypeId)),
          (
            'Portion type',
            await _nameOf('poultry_portion_types', r.portionTypeId)
          ),
          (
            'Designation class',
            await _nameOf('poultry_designation_classes', r.designationClassId)
          ),
          ('Grade', await _nameOf('poultry_grades', r.gradeId)),
          ('Product details', r.productDetails),
          ('Sample number', r.sampleNumber),
          ('Compliant items', '${_idCount(r.compliantItemIds)} ticked'),
          ('Comments', r.inspectionComments),
        ]);
    }

    await _loadDirection();

    // Photographs and signatures live in the one evidence store, keyed on
    // the record's uuid whichever commodity captured it.
    final photos = await (database.select(database.poultryPhotos)
          ..where((t) => t.recordUuid.equals(widget.uuid)))
        .get();
    final signatures = await (database.select(database.poultrySignatures)
          ..where((t) => t.recordUuid.equals(widget.uuid)))
        .get();

    final seizure =
        await SeizureRepository(database: database).currentForRecord(widget.uuid);
    if (!mounted) return;
    setState(() {
      _seizure = seizure;
      _rows = rows;
      _photos = photos;
      _signatures = signatures;
      _missing = rows.isEmpty;
      _loading = false;
    });
  }

  /// Corrects the seizure's particulars, then reads the record back so the
  /// page — and the sheet built from it — say the new thing.
  Future<void> _editSeizure() async {
    final seizure = await SeizureRepository(database: widget.database)
        .forRecord(widget.uuid);
    if (seizure == null || !mounted) return;
    final saved = await editSeizureParticulars(context,
        database: widget.database, seizure: seizure);
    if (!saved || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Seizure updated. The corrected sheet goes to the '
            'office on the next sync.'),
      ));
  }

  /// The direction raised from this inspection, read back the way it was
  /// served: which remarks were added, which checklist rows were the
  /// findings, by when it must be corrected.
  Future<void> _loadDirection() async {
    final database = widget.database;
    String status = '';
    DateTime? issuedAt;
    String remarks = '';
    String comments = '';
    String checklistTable = '';
    // Which tick-list sections the inspector said were present, and which
    // rows were ticked — everything else in a present section is a finding.
    var present = <String>{};
    var ticked = <int>{};

    switch (widget.kind) {
      case 'rawrmp':
        final d = await (database.select(database.rawRmpDirections)
              ..where((t) => t.sourceInspectionUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (d == null) return;
        status = d.status;
        issuedAt = d.issuedAt;
        remarks = d.remarks;
        comments = d.comments;
        checklistTable = 'raw_rmp_checklist_items';
        final i = await (database.select(database.rawRmpInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (i != null) {
          present = {
            if (i.markingLabelsPresent) 'marking',
            if (i.scaleLabelsPresent) 'scale',
            if (i.containersPresent) 'container',
            if (i.displayFridgePresent) 'fridge',
            if (i.noticeBoardsPresent) 'notice',
          };
          ticked = _ids(i.compliantItemIds);
        }
      case 'pmp':
        final d = await (database.select(database.pmpDirections)
              ..where((t) => t.sourceInspectionUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (d == null) return;
        status = d.status;
        issuedAt = d.issuedAt;
        remarks = d.remarks;
        comments = d.comments;
        checklistTable = 'pmp_checklist_items';
        final i = await (database.select(database.pmpInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (i != null) {
          present = {
            if (i.markingLabelsPresent) 'marking',
            if (i.scaleLabelsPresent) 'scale',
            if (i.containersPresent) 'container',
            if (i.displayFridgePresent) 'fridge',
            if (i.noticeBoardsPresent) 'notice',
          };
          ticked = _ids(i.compliantItemIds);
        }
      default:
        // Poultry directions are keyed on the record itself rather than
        // carrying a source link.
        final d = await (database.select(database.poultryDirections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (d == null) return;
        status = d.status;
        issuedAt = d.issuedAt;
        remarks = d.remarks;
        comments = d.comments;
        checklistTable = 'poultry_checklist_items';
        final i = await (database.select(database.poultryInspections)
              ..where((t) => t.clientUuid.equals(widget.uuid)))
            .getSingleOrNull();
        if (i != null) ticked = _ids(i.compliantItemIds);
    }

    final rows = <(String, String)>[
      ('Issued', _dmy(issuedAt)),
      (
        'Status',
        status == 'completed' ? 'Issued to the client' : 'Draft',
      ),
      if (comments.trim().isNotEmpty) ('Comments', comments.trim()),
    ];

    // The deviations are read off the inspection rather than off the
    // direction's numbers. A direction stores its findings the way the
    // original serves them — as positions *within each section* — so the
    // same number means a different row in a different section, and reading
    // them back by number lists the first rows over and over. The
    // inspection knows exactly which rows were left unticked.
    final descriptions = await _deviationsOf(checklistTable, present, ticked);

    if (!mounted) return;
    setState(() {
      _hasDirection = true;
      _directionRows = rows;
      _directionRemarks = remarks
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      _directionFindings = descriptions;
    });
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// A titled list that uses the whole width: a heading, then one line per
  /// entry. [numbered] counts them, as a served direction numbers its
  /// findings.
  Widget _list(String title, List<String> lines, {bool numbered = false}) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      numbered ? '${i + 1}.' : '•',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      lines[i],
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Uses the Egg summary components for commodity records opened from a
  /// grouped inspection. This deliberately changes presentation only: the
  /// rows, evidence and direction data above are untouched.
  Widget _summaryScaffold(BuildContext context) {
    String valueFor(String label) {
      for (final (rowLabel, value) in _rows) {
        if (rowLabel == label && value.trim().isNotEmpty) return value;
      }
      return '';
    }

    List<Widget> fields(List<(String, String)> rows) => [
          for (final (label, value) in rows)
            if (value.trim().isNotEmpty)
              SummaryField(label: label, value: value),
        ];

    List<Widget> bullets(String title, List<String> lines,
            {bool numbered = false}) =>
        [
          if (lines.isNotEmpty) ...[
            Text(title,
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 6),
            for (var i = 0; i < lines.length; i++)
              SummaryBullet(
                text: numbered ? '${i + 1}. ${lines[i]}' : lines[i],
              ),
          ],
        ];

    String signatureCaption(PoultrySignature signature) {
      final name = signature.signedName.trim();
      final role = switch (signature.role) {
        'client' => 'Store / Client',
        'inspector' => 'Inspector',
        _ => signature.role,
      };
      return name.isEmpty ? role : '$role — $name';
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          SummaryHeader(
            title: valueFor('Facility').isEmpty
                ? widget.title
                : valueFor('Facility'),
            subtitle: valueFor('Inspected').isEmpty
                ? 'Inspection record'
                : valueFor('Inspected'),
            uploaded: widget.uploaded,
            status: widget.status,
          ),
          const SizedBox(height: 18),
          SummarySection(
            title: 'Inspection details',
            children: fields(_rows),
          ),
          if (_hasDirection)
            SummarySection(
              title: 'Rejection served',
              accent: AppColors.brandRed,
              children: [
                ...fields(_directionRows),
                ...bullets('Remarks served', _directionRemarks),
                ...bullets('Deviations', _directionFindings, numbered: true),
              ],
            ),
          // The seizure, beside the rejection it stands with.
          if (_seizure != null)
            SummarySection(
              title: 'Seizure served',
              accent: AppColors.brandRed,
              children: [
                ...fields(SeizureRepository.rowsFor(_seizure!)),
                // Only where the record itself can be corrected — never on
                // a copy brought down from the server.
                if (widget.onEdit != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _editSeizure,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('EDIT SEIZURE PARTICULARS'),
                      ),
                    ),
                  ),
              ],
            ),
          if (widget.onEdit != null) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _editing ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(_editing ? 'OPENING…' : 'EDIT THIS INSPECTION'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.uploaded
                  ? 'The office has this record. A correction is sent to '
                      'them again on the next Server Sync, and replaces what '
                      'they hold — it does not make a second inspection.'
                  : 'This record has not been sent yet; a correction simply '
                      'goes with it.',
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
            const SizedBox(height: 14),
          ],
          RecordDocumentsSection(
            database: widget.database,
            kind: widget.kind,
            uuid: widget.uuid,
            padding: const EdgeInsets.only(top: 4, bottom: 14),
          ),
          SummarySection(
            title: 'Photos',
            children: _photos.isEmpty
                ? const [SummaryEmpty(text: 'No photographs on this record.')]
                : [
                    // Side by side, as many across as the screen takes.
                    // Stacked one under another, two photographs pushed the
                    // signatures a page down and left the width of the page
                    // empty beside them.
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final photo in _photos)
                          _image(photo.filePath, photo.kind),
                      ],
                    ),
                  ],
          ),
          SummarySection(
            title: 'Signatures',
            children: _signatures.isEmpty
                ? const [SummaryEmpty(text: 'No signatures on this record.')]
                : [
                    for (final signature in _signatures)
                      _image(
                        signature.filePath,
                        signatureCaption(signature),
                        signature: true,
                      ),
                  ],
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && !_missing) return _summaryScaffold(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ContentWidth(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _missing
                  ? const Center(child: Text('This record no longer exists.'))
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        _section('INSPECTION DETAILS'),
                        for (final (label, value) in _rows) _row(label, value),
                        if (_hasDirection) ...[
                          _section('REJECTION SERVED'),
                          for (final (label, value) in _directionRows)
                            _row(label, value),
                          // Lists run the width of the page. Squeezed into the
                          // value column beside a label they wrap after three
                          // words, with an empty gutter alongside.
                          _list('Remarks served', _directionRemarks),
                          _list('Deviations', _directionFindings,
                              numbered: true),
                        ],
                        RecordDocumentsSection(
                          database: widget.database,
                          kind: widget.kind,
                          uuid: widget.uuid,
                          padding: const EdgeInsets.only(bottom: 10),
                        ),
                        // Side by side, and as many across as the screen
                        // takes. Stacked one under another, two photographs
                        // pushed the signatures a page and a half down and
                        // left the width of the page empty beside them.
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            for (final photo in _photos)
                              _image(photo.filePath, photo.kind),
                          ],
                        ),
                        _section('SIGNATURES'),
                        if (_signatures.isEmpty)
                          Text('No signatures on this record.',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.muted)),
                        for (final signature in _signatures)
                          _image(
                            signature.filePath,
                            signature.role == 'client'
                                ? 'Store / Client'
                                    '${signature.signedName.isEmpty ? '' : ' — '
                                        '${signature.signedName}'}'
                                : signature.role == 'inspector'
                                    ? 'Inspector'
                                        '${signature.signedName.isEmpty ? '' : ' — '
                                            '${signature.signedName}'}'
                                    : signature.role,
                            signature: true,
                          ),
                      ],
                    )),
    );
  }

  Widget _image(String path, String caption, {bool signature = false}) {
    final file = File(path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        // A photograph is a fixed tile so several sit in a row; a signature
        // still runs the width of the page.
        width: signature ? double.infinity : 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (file.existsSync())
              Container(
                // A signature is read, not glanced at: it takes the width of
                // the page so the strokes are the size they were signed at,
                // rather than a thumbnail the width of the pad's own margins.
                width: signature ? double.infinity : null,
                height: signature ? 150 : null,
                padding: signature ? const EdgeInsets.all(8) : null,
                decoration: signature
                    ? BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      )
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: signature
                      ? Image.file(file, fit: BoxFit.contain)
                      : Image.file(file, height: 180, fit: BoxFit.cover),
                ),
              )
            else
              Text(
                signature ? 'Signature image missing' : 'Photo file missing',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
