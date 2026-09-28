import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import '../../eggs/presentation/egg_inspection_summary_page.dart'
    show PhotoImage;
import '../../eggs/presentation/summary_widgets.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../data/rawrmp_repository.dart';

/// Read-only report views for Certain Raw Processed Meat Products records,
/// mirroring the original's RawRMPInspectionSummaryViewPage and
/// RawRMPDirectionSummaryViewPage: the same rows, the "-" fallbacks, the
/// "Not Specific" sample-size stand-in (the original's entry for it is a
/// hidden legacy control, so the record always says so), "Not Applicable"
/// for the testing category of an unsampled consignment, and the
/// direction's duplicated "Facility Name" header over the producer — the
/// original's own label bug, shipped as found.
class RawRmpInspectionSummaryPage extends StatefulWidget {
  const RawRmpInspectionSummaryPage({
    super.key,
    required this.inspection,
    required this.repository,
  });

  final RawRmpInspection inspection;
  final RawRmpRepository repository;

  @override
  State<RawRmpInspectionSummaryPage> createState() =>
      _RawRmpInspectionSummaryPageState();
}

class _RawRmpInspectionSummaryPageState
    extends State<RawRmpInspectionSummaryPage> {
  late Future<String> _category;

  @override
  void initState() {
    super.initState();
    _category = _loadCategory();
  }

  Future<String> _loadCategory() async {
    final i = widget.inspection;
    if (!i.isSampled) return 'Not Applicable';
    final categories = await widget.repository.sampleCategories();
    final ids = {
      for (final s in i.sampleCategoryIds.split(','))
        if (int.tryParse(s.trim()) != null) int.parse(s.trim()),
      if (i.sampleCategoryIds.trim().isEmpty && i.sampleCategoryId != null)
        i.sampleCategoryId!,
    };
    final names = [
      for (final c in categories)
        if (ids.contains(c.id)) c.name,
    ];
    return names.isEmpty ? 'Not Applicable' : names.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.inspection;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Certain Raw Processed Meat Product Inspection Summary',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<String>(
        future: _category,
        builder: (context, snap) {
          final category = snap.data ?? 'Not Applicable';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              SummarySection(
                title: 'Record',
                children: [
                  SummaryField(
                    label: 'Internal Record #',
                    value: i.clientUuid,
                    mono: true,
                  ),
                  SummaryField(
                    label: 'Facility Name',
                    value: orDash(i.facilityName),
                  ),
                  const SummaryField(label: 'New Facility Name', value: '-'),
                  SummaryField(
                    label: 'Producer Name',
                    value: orDash(i.producerName),
                  ),
                  SummaryField(
                    label: 'New Producer Name',
                    value: i.newProducerDetails.trim().isEmpty
                        ? '-'
                        : i.newProducerDetails,
                  ),
                  SummaryField(
                    label: 'Product Item',
                    value: orDash(
                      i.newProductItem.trim().isEmpty
                          ? i.productItem
                          : i.newProductItem,
                    ),
                  ),
                  SummaryField(
                    label: 'Manufactured/Packed Date',
                    value: orDash(i.manufacturedPackedDate),
                  ),
                  SummaryField(
                    label: 'Batch Number',
                    value: orDash(i.batchNumber),
                  ),
                  // The original's entry for this is a hidden legacy control,
                  // so its save writes "Not Specific" every time.
                  const SummaryField(
                    label: 'Primary Sample Size (g)',
                    value: 'Not Specific',
                  ),
                  SummaryField(
                    label: 'Is Sampled',
                    value: i.isSampled ? 'Yes' : 'No',
                  ),
                  SummaryField(
                    label: 'Lab Testing Category',
                    value: category,
                  ),
                ],
              ),
            ],
          );
        },
      )),
    );
  }
}

class RawRmpDirectionSummaryPage extends StatefulWidget {
  const RawRmpDirectionSummaryPage({
    super.key,
    required this.direction,
    required this.repository,
    required this.captureRepository,
  });

  final RawRmpDirection direction;
  final RawRmpRepository repository;
  final PoultryCaptureRepository captureRepository;

  @override
  State<RawRmpDirectionSummaryPage> createState() =>
      _RawRmpDirectionSummaryPageState();
}

class _RawRmpDirectionSummaryPageState
    extends State<RawRmpDirectionSummaryPage> {
  late Future<_DirectionReport> _report;

  @override
  void initState() {
    super.initState();
    _report = _load();
  }

  List<int> _ids(String csv) => [
        for (final part in csv.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ];

  Future<_DirectionReport> _load() async {
    final d = widget.direction;

    final info = await widget.repository.labelNonConformances();
    final byId = {for (final row in info) row.id: row.description};
    final deviations = [
      for (final id in _ids(d.nonConformanceIds)) byId[id] ?? '',
    ];

    final restrictedRefs = await widget.repository.restrictedParticulars();
    final restrictedById = {for (final r in restrictedRefs) r.id: r.name};
    // Particulars typed in at the inspection are on the inspection, not
    // the direction: the direction only carries the ids it was given.
    final source = d.sourceInspectionUuid == null
        ? null
        : await widget.repository.inspectionByUuid(d.sourceInspectionUuid!);
    final restricted = [
      for (final id in _ids(d.restrictedParticularIds))
        if (restrictedById[id] != null) restrictedById[id]!,
      ...TypedParticulars.unpack(source?.restrictedParticularsText ?? ''),
    ];

    final photos = d.sourceInspectionUuid == null
        ? const <PoultryPhoto>[]
        : await widget.captureRepository.photosFor(d.sourceInspectionUuid!);

    return _DirectionReport(
      deviations: deviations,
      restricted: restricted,
      photoPaths: [for (final p in photos.take(2)) p.filePath],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.direction;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Certain Raw Processed Meat Product Rejection Summary',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_DirectionReport>(
        future: _report,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snap.data ??
              const _DirectionReport(
                deviations: [],
                restricted: [],
                photoPaths: [],
              );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              SummarySection(
                title: 'Record',
                children: [
                  SummaryField(
                    label: 'Internal Record #',
                    value: d.clientUuid,
                    mono: true,
                  ),
                  SummaryField(
                    label: 'Facility Name',
                    value: orDash(d.facilityName),
                  ),
                  SummaryField(
                    label: 'New Facility Name',
                    value: d.newFacilityName.trim().isEmpty
                        ? '-'
                        : d.newFacilityName,
                  ),
                  // The original heads this row "Facility Name" while showing
                  // the producer. The label bug ships as captured.
                  SummaryField(
                    label: 'Facility Name',
                    value: orDash(d.producerName),
                  ),
                  SummaryField(
                    label: 'New Producer Name',
                    value: d.newProducerName.trim().isEmpty
                        ? '-'
                        : d.newProducerName,
                  ),
                  SummaryField(
                    label: 'Manufactured/Packed Date',
                    value: orDash(d.manufacturedPackedDate),
                  ),
                  SummaryField(
                    label: 'Batch Number',
                    value: orDash(d.batchNumber),
                  ),
                  SummaryField(
                    label: 'Primary Sample Size (g)',
                    value: orDash(d.primarySampleSize),
                  ),
                ],
              ),
              SummarySection(
                title: 'Label/Pack Summary Checklist',
                children: [
                  const SummaryField(
                    label: '#',
                    value: 'Deviation(s) is Present',
                  ),
                  if (report.deviations.isEmpty)
                    const SummaryEmpty(text: 'No deviations recorded.')
                  else
                    for (var n = 0; n < report.deviations.length; n++)
                      SummaryField(
                        label: '${n + 1}',
                        value: report.deviations[n],
                      ),
                ],
              ),
              if (report.photoPaths.isNotEmpty)
                SummarySection(
                  title: 'Photographs',
                  children: [
                    for (final path in report.photoPaths)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: PhotoImage(
                            path: path,
                            width: double.infinity,
                            cacheWidth: 1200,
                            fit: BoxFit.fitWidth,
                          ),
                        ),
                      ),
                  ],
                ),
              SummarySection(
                title: 'Restricted Particulars',
                children: [
                  SummaryField(
                    label: 'Restricted Particulars',
                    value: report.restricted.isEmpty
                        ? 'Not present'
                        : report.restricted.join('\n'),
                  ),
                ],
              ),
            ],
          );
        },
      )),
    );
  }
}

class _DirectionReport {
  const _DirectionReport({
    required this.deviations,
    required this.restricted,
    required this.photoPaths,
  });

  final List<String> deviations;
  final List<String> restricted;
  final List<String> photoPaths;
}
