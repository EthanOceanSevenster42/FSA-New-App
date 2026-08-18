import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import 'egg_inspection_summary_page.dart';
import 'summary_widgets.dart';

/// Read-only view of one issued direction, including a way through to the
/// inspection it was raised from.
class EggDirectionSummaryPage extends StatefulWidget {
  const EggDirectionSummaryPage({
    super.key,
    required this.repository,
    required this.directionUuid,
  });

  final EggsRepository repository;
  final String directionUuid;

  @override
  State<EggDirectionSummaryPage> createState() =>
      _EggDirectionSummaryPageState();
}

class _Data {
  _Data({
    required this.direction,
    required this.remarks,
    required this.sourceInspection,
  });

  final EggDirection direction;
  final List<String> remarks;

  /// The inspection this direction was raised from, when it is on the device.
  final EggInspection? sourceInspection;
}

class _EggDirectionSummaryPageState extends State<EggDirectionSummaryPage> {
  late Future<_Data?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data?> _load() async {
    final repo = widget.repository;
    final direction = await repo.directionByUuid(widget.directionUuid);
    if (direction == null) return null;

    return _Data(
      direction: direction,
      remarks: await repo.directionRemarkNames(direction.remarkIds),
      sourceInspection: direction.inspectionUuid == null
          ? null
          : await repo.inspectionByUuid(direction.inspectionUuid!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Direction summary',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<_Data?>(
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
                  'This direction is no longer on the device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return _body(data);
        },
      ),
    );
  }

  Widget _body(_Data d) {
    final direction = d.direction;

    // Each part runs to its own deadline, so each is judged overdue on its
    // own. A notice can be met on labelling and overdue on quality.
    final qualityBy = direction.qualityCorrectBy?.toLocal();
    final labelBy = direction.labelCorrectBy?.toLocal();
    bool passed(DateTime? date) =>
        date != null && !direction.isUploaded && date.isBefore(DateTime.now());
    final qualityOverdue = direction.qualityPart && passed(qualityBy);
    final labelOverdue = direction.labellingPart && passed(labelBy);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SummaryHeader(
          title: direction.clientName.isEmpty
              ? '(no client recorded)'
              : direction.clientName,
          subtitle: formatDateTime(direction.issuedAt.toLocal()),
          uploaded: direction.isUploaded,
          status: direction.status,
        ),
        const SizedBox(height: 18),

        SummarySection(
          title: 'Direction',
          children: [
            SummaryField(
              label: 'Covers',
              value: directionParts(direction),
              emphasise: true,
            ),
            SummaryField(
                label: 'Number', value: orDash(direction.directionNumber)),
            if (direction.qualityPart)
              SummaryField(
                label: 'Quality correct by',
                value: qualityBy == null ? '—' : formatDate(qualityBy),
                warn: qualityOverdue,
                note: qualityOverdue
                    ? 'The correction date has passed.'
                    : null,
              ),
            if (direction.labellingPart)
              SummaryField(
                label: 'Labelling correct by',
                value: labelBy == null ? '—' : formatDate(labelBy),
                warn: labelOverdue,
                note: labelOverdue ? 'The correction date has passed.' : null,
              ),
            SummaryField(
              label: 'Quantity removed',
              // Null means nothing was removed; zero would be a measurement.
              value: direction.quantityRemoved == null
                  ? 'None removed'
                  : direction.quantityRemoved!.toStringAsFixed(0),
            ),
          ],
        ),

        SummarySection(
          title: 'Client',
          children: [
            SummaryField(label: 'Name', value: orDash(direction.clientName)),
            SummaryField(
                label: 'Producer', value: orDash(direction.producerSupplier)),
          ],
        ),

        SummarySection(
          title: 'Remarks',
          children: d.remarks.isEmpty
              ? const [SummaryEmpty(text: 'No standard remarks were ticked.')]
              : [for (final r in d.remarks) SummaryBullet(text: r)],
        ),

        if (direction.additionalRemarks.isNotEmpty)
          SummarySection(
            title: 'Additional remarks',
            children: [
              Text(
                direction.additionalRemarks,
                style: TextStyle(
                    fontSize: 13.5, color: AppColors.ink, height: 1.4),
              ),
            ],
          ),

        _sourceSection(d),

        SummarySection(
          title: 'Record',
          children: [
            SummaryField(
                label: 'Reference', value: direction.clientUuid, mono: true),
            SummaryField(
              label: 'Location',
              value: direction.latitude == null || direction.longitude == null
                  ? 'Not captured'
                  : '${direction.latitude!.toStringAsFixed(5)}, '
                      '${direction.longitude!.toStringAsFixed(5)}',
            ),
            SummaryField(
              label: 'Upload',
              value: direction.isUploaded
                  ? 'Sent to the server'
                  : 'Waiting to send',
            ),
          ],
        ),
      ],
    );
  }

  Widget _sourceSection(_Data d) {
    final uuid = d.direction.inspectionUuid;
    if (uuid == null) {
      return const SummarySection(
        title: 'Source inspection',
        children: [
          SummaryEmpty(text: 'Issued on its own, not from an inspection.'),
        ],
      );
    }
    final source = d.sourceInspection;
    if (source == null) {
      return const SummarySection(
        title: 'Source inspection',
        children: [
          SummaryEmpty(
            text: 'Raised from an inspection that is not on this device.',
          ),
        ],
      );
    }
    return SummarySection(
      title: 'Source inspection',
      children: [
        SummaryField(
          label: 'Captured',
          value: formatDateTime(source.inspectedAt.toLocal()),
        ),
        SummaryField(label: 'Batch', value: orDash(source.batchNumber)),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EggInspectionSummaryPage(
                  repository: widget.repository,
                  inspectionUuid: uuid,
                ),
              ),
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Open the inspection'),
          ),
        ),
      ],
    );
  }
}
