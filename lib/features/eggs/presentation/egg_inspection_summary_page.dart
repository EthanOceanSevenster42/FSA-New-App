import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/restricted_particulars_picker.dart';
import '../data/eggs_repository.dart';
import 'summary_widgets.dart';

/// Read-only view of one captured inspection.
///
/// Everything recorded against the record, in the order an inspector reads it
/// back: who and where, what the consignment was, what each egg measured, and
/// what the deviations added up to.
class EggInspectionSummaryPage extends StatefulWidget {
  const EggInspectionSummaryPage({
    super.key,
    required this.repository,
    required this.inspectionUuid,
  });

  final EggsRepository repository;
  final String inspectionUuid;

  @override
  State<EggInspectionSummaryPage> createState() =>
      _EggInspectionSummaryPageState();
}

class _Data {
  _Data({
    required this.inspection,
    required this.samples,
    required this.tally,
    required this.photos,
    required this.gradeName,
    required this.sizeNames,
    required this.reasonName,
    required this.traySizeName,
    required this.facilityTypeName,
    required this.failedRequirements,
    required this.restrictedParticulars,
  });

  final EggInspection inspection;
  final List<EggSample> samples;
  final List<DeviationTally> tally;
  final List<EggPhoto> photos;
  final String gradeName;
  final Map<int, String> sizeNames;
  final String reasonName;
  final String traySizeName;
  final String facilityTypeName;
  final List<String> failedRequirements;
  final List<String> restrictedParticulars;
}

class _EggInspectionSummaryPageState extends State<EggInspectionSummaryPage> {
  late Future<_Data?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data?> _load() async {
    final repo = widget.repository;
    final inspection = await repo.inspectionByUuid(widget.inspectionUuid);
    if (inspection == null) return null;

    final grades = await repo.grades();
    final sizes = await repo.sizeBands();
    final reasons = await repo.reasons();
    final trays = await repo.traySizes();
    final facilityTypes = await repo.facilityTypes();

    String nameOf<T>(
        Iterable<T> items, bool Function(T) match, String Function(T) label) {
      for (final item in items) {
        if (match(item)) return label(item);
      }
      return '—';
    }

    return _Data(
      inspection: inspection,
      samples: await repo.samplesFor(widget.inspectionUuid),
      tally: await repo.deviationTally(widget.inspectionUuid),
      photos: await repo.photosFor(widget.inspectionUuid),
      // An inspection with no grade is genuinely ungraded — not "Grade A".
      gradeName: inspection.determinedGradeId == null
          ? 'Not graded'
          : nameOf(grades, (g) => g.id == inspection.determinedGradeId,
              (g) => g.name),
      sizeNames: {for (final s in sizes) s.id: s.name},
      reasonName: inspection.reasonId == null
          ? '—'
          : nameOf(reasons, (r) => r.id == inspection.reasonId, (r) => r.name),
      traySizeName: inspection.traySizeId == null
          ? '—'
          : nameOf(trays, (t) => t.id == inspection.traySizeId, (t) => t.name),
      facilityTypeName: inspection.facilityTypeId == null
          ? '—'
          : nameOf(facilityTypes, (f) => f.id == inspection.facilityTypeId,
              (f) => f.name),
      failedRequirements:
          await repo.requirementNames(inspection.failedRequirementIds),
      restrictedParticulars: [
        ...await repo
            .restrictedParticularNames(inspection.restrictedParticularIds),
        ...TypedParticulars.unpack(inspection.restrictedParticularsText),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Inspection summary',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_Data?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'This inspection is no longer on the device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return _body(data);
        },
      )),
    );
  }

  Widget _body(_Data d) {
    final i = d.inspection;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SummaryHeader(
          title: i.clientName.isEmpty ? '(no client recorded)' : i.clientName,
          subtitle: formatDateTime(i.inspectedAt.toLocal()),
          uploaded: i.isUploaded,
          status: i.status,
        ),
        const SizedBox(height: 18),
        SummarySection(
          title: 'Result',
          children: [
            SummaryField(label: 'Grade', value: d.gradeName, emphasise: true),
            SummaryField(label: 'Eggs sampled', value: '${d.samples.length}'),
            if (i.sampleSize != null && i.sampleSize != d.samples.length)
              SummaryField(
                label: 'Sample size set',
                value: '${i.sampleSize}',
                note: 'Fewer eggs were captured than the sample size entered.',
              ),
            if (i.gradeOverridden)
              SummaryField(
                label: 'Overridden',
                value: i.overrideReason.isEmpty
                    ? 'Grade changed by the inspector; no reason recorded.'
                    : i.overrideReason,
                warn: true,
              ),
          ],
        ),
        SummarySection(
          title: 'Facility',
          children: [
            SummaryField(label: 'Name', value: orDash(i.facilityName)),
            SummaryField(label: 'Type', value: d.facilityTypeName),
            SummaryField(label: 'Address', value: orDash(i.facilityAddress)),
            SummaryField(
                label: 'Telephone / cellphone', value: orDash(i.facilityPhone)),
            SummaryField(label: 'Reason', value: d.reasonName),
          ],
        ),
        SummarySection(
          title: 'Client',
          children: [
            SummaryField(label: 'Name', value: orDash(i.clientName)),
            SummaryField(label: 'Address', value: orDash(i.clientAddress)),
            SummaryField(
                label: 'Contact', value: orDash(i.clientContactPerson)),
            SummaryField(
                label: 'Telephone / cellphone',
                value: orDash(i.clientContactNumber)),
            SummaryField(label: 'Email', value: orDash(i.clientEmail)),
            SummaryField(
                label: 'Representative', value: orDash(i.representativeName)),
          ],
        ),
        SummarySection(
          title: 'Consignment',
          children: [
            SummaryField(label: 'Producer', value: orDash(i.producerSupplier)),
            SummaryField(label: 'Batch', value: orDash(i.batchNumber)),
            SummaryField(
              label: 'Best before',
              value: i.bestBefore == null
                  ? '—'
                  : formatDate(i.bestBefore!.toLocal()),
            ),
            SummaryField(label: 'Tray size', value: d.traySizeName),
            if (i.pasteurisedPresent)
              const SummaryField(
                  label: 'Pasteurised', value: 'Present in consignment'),
            if (i.haughNotRequired)
              const SummaryField(
                label: 'Haugh unit',
                value: 'Not required for this consignment',
              ),
          ],
        ),
        _samplesSection(d),
        _deviationSection(d),
        if (d.failedRequirements.isNotEmpty)
          SummarySection(
            title: 'Labelling and packing failures',
            children: [
              for (final r in d.failedRequirements) SummaryBullet(text: r),
            ],
          ),
        SummarySection(
          title: 'Restricted particulars',
          children: d.restrictedParticulars.isEmpty
              ? const [SummaryEmpty(text: 'None recorded.')]
              : [
                  for (final r in d.restrictedParticulars)
                    SummaryBullet(text: r),
                ],
        ),
        if (i.nonConformanceComments.isNotEmpty)
          SummarySection(
            title: 'Comments',
            children: [
              if (i.nonConformanceComments.isNotEmpty)
                SummaryField(
                    label: 'Non-conformance', value: i.nonConformanceComments),
            ],
          ),
        _photoSection(d),
        SummarySection(
          title: 'Record',
          children: [
            SummaryField(label: 'Reference', value: i.clientUuid, mono: true),
            SummaryField(
              label: 'Upload',
              value: i.isUploaded ? 'Sent to the server' : 'Waiting to send',
            ),
          ],
        ),
      ],
    );
  }

  Widget _samplesSection(_Data d) {
    if (d.samples.isEmpty) {
      return const SummarySection(
        title: 'Eggs',
        children: [SummaryEmpty(text: 'No individual eggs were recorded.')],
      );
    }

    final withHaugh = d.samples.where((s) => s.haughUnit != null).toList();
    final average = withHaugh.isEmpty
        ? null
        : withHaugh.map((s) => s.haughUnit!).reduce((a, b) => a + b) /
            withHaugh.length;

    return SummarySection(
      title: 'Eggs (${d.samples.length})',
      children: [
        if (average != null)
          SummaryField(
            label: 'Average Haugh',
            // Averaged over the eggs that actually have a reading, so the
            // figure is not diluted by eggs that were never measured.
            value: '${average.toStringAsFixed(1)}  '
                '(${withHaugh.length} of ${d.samples.length} measured)',
          ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 52,
            columnSpacing: 20,
            headingTextStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: AppColors.muted,
              letterSpacing: 0.6,
            ),
            dataTextStyle: TextStyle(fontSize: 13, color: AppColors.ink),
            columns: const [
              DataColumn(label: Text('EGG')),
              DataColumn(label: Text('MASS (g)')),
              DataColumn(label: Text('SIZE')),
              DataColumn(label: Text('ALBUMEN (mm)')),
              DataColumn(label: Text('HAUGH')),
              DataColumn(label: Text('DEV.')),
            ],
            rows: [
              for (final s in d.samples)
                DataRow(
                  cells: [
                    DataCell(Text('${s.eggNumber}')),
                    DataCell(Text(s.massG?.toStringAsFixed(1) ?? '—')),
                    DataCell(Text(
                      s.sizeId == null
                          ? 'Unclassified'
                          : d.sizeNames[s.sizeId!] ?? '—',
                    )),
                    DataCell(
                        Text(s.albumenHeightMm?.toStringAsFixed(1) ?? '—')),
                    DataCell(Text(s.haughUnit?.toStringAsFixed(1) ?? '—')),
                    DataCell(Text('${_deviationCount(s)}')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static int _deviationCount(EggSample s) => s.deviationIds
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .length;

  Widget _deviationSection(_Data d) {
    if (d.tally.isEmpty) {
      return const SummarySection(
        title: 'Deviations',
        children: [SummaryEmpty(text: 'No deviations were recorded.')],
      );
    }
    return SummarySection(
      title: 'Deviations',
      children: [
        for (final t in d.tally)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.description,
                        style: TextStyle(fontSize: 13.5, color: AppColors.ink),
                      ),
                      if (t.category.isNotEmpty)
                        Text(
                          t.category,
                          style:
                              TextStyle(fontSize: 11.5, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    // Spelled out, because a bare number next to a deviation
                    // reads as a severity score rather than a count.
                    t.eggsAffected == 1 ? '1 egg' : '${t.eggsAffected} eggs',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// What each photograph is evidence of, in words rather than a code.
  static String photoKindLabel(String kind) => switch (kind) {
        'label' => 'Label',
        'egg' => 'Egg sample',
        'deviation' => 'Deviation',
        'numbering' => 'Numbering',
        _ => kind.isEmpty ? 'Photo' : kind,
      };

  Widget _photoSection(_Data d) {
    if (d.photos.isEmpty) {
      return const SummarySection(
        title: 'Photos',
        children: [SummaryEmpty(text: 'No photos were attached.')],
      );
    }

    // Grouped by what they show, so "three photos" becomes "a label, and two
    // of the deviation" — which is what an inspector needs to know.
    final byKind = <String, List<EggPhoto>>{};
    for (final photo in d.photos) {
      byKind.putIfAbsent(photo.kind, () => []).add(photo);
    }

    return SummarySection(
      title: 'Photos (${d.photos.length})',
      children: [
        for (final entry in byKind.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${photoKindLabel(entry.key)} · '
              '${entry.value.length} '
              '${entry.value.length == 1 ? 'photo' : 'photos'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppColors.muted,
              ),
            ),
          ),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entry.value.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _PhotoTile(
                photo: entry.value[i],
                onTap: () => _openViewer(entry.value, i),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  void _openViewer(List<EggPhoto> photos, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoViewer(photos: photos, initialIndex: index),
      ),
    );
  }
}

/// One thumbnail, with what it shows and when it was taken.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final EggPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final at = photo.capturedAt.toLocal();
    final time = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: PhotoImage(
                path: photo.filePath,
                width: 110,
                height: 100,
                // Decoded at roughly the size it is drawn: a full-resolution
                // bitmap per thumbnail would exhaust memory on a cheap handset.
                cacheWidth: 330,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            photo.caption.trim().isEmpty ? time : photo.caption.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Renders a photograph whether it is a file on this handset or a URL on the
/// server.
///
/// A record captured here points at a local file; one downloaded from another
/// inspector's phone points at the server. The summary should not care which.
class PhotoImage extends StatelessWidget {
  const PhotoImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });

  final String path;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;

  bool get _isRemote =>
      path.startsWith('http://') || path.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isRemote) {
      return Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => _unavailable('Could not be downloaded'),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                width: width,
                height: height,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      // The row exists but the file does not — deleted, or the record came
      // from a handset whose photos were never uploaded.
      return _unavailable('Not on this device');
    }
    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
    );
  }

  Widget _unavailable(String message) => Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.3),
        ),
      );
}

/// Full-screen view of the captured photographs, swipeable between them.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});

  final List<EggPhoto> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_index];
    final at = photo.capturedAt.toLocal();
    return Scaffold(
      // Black behind a photograph, so nothing competes with the evidence.
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _EggInspectionSummaryPageState.photoKindLabel(photo.kind),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        actions: [
          if (widget.photos.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_index + 1} of ${widget.photos.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: ContentWidth(
          child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                // Pinch to zoom: a label or a hairline crack has to be
                // readable, and the thumbnail never will be.
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: PhotoImage(
                    path: widget.photos[i].filePath,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo.caption.trim().isNotEmpty) ...[
                  Text(
                    photo.caption.trim(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14.5, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  'Taken ${formatDateTime(at)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                Text(
                  photo.isUploaded
                      ? 'Uploaded to the server'
                      : 'Waiting to upload',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }
}
