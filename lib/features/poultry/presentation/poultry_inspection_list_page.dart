import 'package:flutter/material.dart';

import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import 'poultry_inspection_form.dart';
import 'poultry_inspection_summary_page.dart';
import 'poultry_label_checklist_form.dart';
import 'poultry_quid_continue_page.dart';

/// Poultry Inspection Management.
///
/// Lists every kind of poultry record — grading, label/container and QUID —
/// the way the original's single management screen does. Listing only grading
/// here left completed label and QUID checklists with no way to be sent at
/// all: captured, finished, and stranded on the handset.
///
/// Filters by a span of dates rather than a single day, matching Egg
/// Inspection Management: a round is rarely one day's work. Both ends default
/// to today, so opening the page shows today's records.
class PoultryInspectionListPage extends StatefulWidget {
  const PoultryInspectionListPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<PoultryInspectionListPage> createState() =>
      _PoultryInspectionListPageState();
}

enum _Kind { grading, label, quid }

/// One record of any kind, reduced to what the list needs.
class _Row {
  _Row({
    required this.kind,
    required this.uuid,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.isUploaded,
    required this.hasPendingEvidence,
    required this.inspectedAt,
  });

  final _Kind kind;
  final String uuid;
  final String title;
  final String subtitle;
  final String status;
  final bool isUploaded;

  /// Photographs or signatures still to send. Keeps Send visible after the
  /// record itself has gone up, so a failed attachment upload has a retry.
  final bool hasPendingEvidence;
  final DateTime inspectedAt;

  bool get isCompleted => status == 'completed';
  bool get needsSend => isCompleted && (!isUploaded || hasPendingEvidence);

  String get kindLabel => switch (kind) {
        _Kind.grading => 'Grading',
        _Kind.label => 'Label/Container',
        _Kind.quid => 'QUID',
      };
}

class _PoultryInspectionListPageState extends State<PoultryInspectionListPage> {
  late Future<List<_Row>> _rows;

  DateTimeRange _range = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );

  final _uploading = <String>{};
  String? _token;

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isSingleDay => _sameDay(_range.start, _range.end);

  bool _withinRange(DateTime value) => PoultryCaptureRepository.withinDays(
        value,
        _range.start,
        _range.end,
      );

  Future<List<_Row>> _load() async {
    _token = await widget.repository.storedToken();
    final capture = widget.captureRepository;
    final user = widget.user.userName;
    final rows = <_Row>[];

    for (final i in await widget.repository.savedInspections(user)) {
      if (!_withinRange(i.inspectedAt.toLocal())) continue;
      rows.add(_Row(
        kind: _Kind.grading,
        uuid: i.clientUuid,
        title: i.facilityName.isEmpty ? '(no facility)' : i.facilityName,
        subtitle: i.productDetails.isEmpty
            ? 'Sample ${i.sampleNumber.isEmpty ? "—" : i.sampleNumber}'
            : i.productDetails,
        status: i.status,
        isUploaded: i.isUploaded,
        hasPendingEvidence: await capture.hasPendingEvidenceFor(i.clientUuid),
        inspectedAt: i.inspectedAt,
      ));
    }

    for (final i in await capture.labelInspections(user)) {
      if (!_withinRange(i.inspectedAt.toLocal())) continue;
      rows.add(_Row(
        kind: _Kind.label,
        uuid: i.clientUuid,
        title: i.facilityName.isEmpty ? '(no facility)' : i.facilityName,
        subtitle: i.productDetails.isEmpty
            ? 'Sample ${i.sampleNumber.isEmpty ? "—" : i.sampleNumber}'
            : i.productDetails,
        status: i.status,
        isUploaded: i.isUploaded,
        hasPendingEvidence: await capture.hasPendingEvidenceFor(i.clientUuid),
        inspectedAt: i.inspectedAt,
      ));
    }

    for (final i in await capture.quidInspections(user)) {
      if (!_withinRange(i.inspectedAt.toLocal())) continue;
      rows.add(_Row(
        kind: _Kind.quid,
        uuid: i.clientUuid,
        title: i.facilityName.isEmpty ? '(no facility)' : i.facilityName,
        subtitle: i.injectorName.isEmpty
            ? (i.productDetails.isEmpty ? 'QUID checklist' : i.productDetails)
            : 'Injector ${i.injectorName}',
        status: i.status,
        isUploaded: i.isUploaded,
        hasPendingEvidence: await capture.hasPendingEvidenceFor(i.clientUuid),
        inspectedAt: i.inspectedAt,
      ));
    }

    rows.sort((a, b) => b.inspectedAt.compareTo(a.inspectedAt));
    return rows;
  }

  // Block body, not an arrow: an arrow returns the assigned Future, and
  // setState asserts when its callback returns one.
  void _refresh() => setState(() {
        _rows = _load();
      });

  String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get _dateLabel => _isSingleDay
      ? _day(_range.start)
      : '${_day(_range.start)} - ${_day(_range.end)}';

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime.now(),
      helpText: 'Select dates to view',
    );
    if (picked != null) {
      setState(() => _range = picked);
      _refresh();
    }
  }

  Future<void> _send(_Row row) async {
    final token = _token;
    if (token == null) {
      _toast(
        'This device has never signed in online, so there is no credential to '
        'upload with. Sign in once with signal, then send.',
      );
      return;
    }
    setState(() => _uploading.add(row.uuid));
    try {
      final capture = widget.captureRepository;
      if (!row.isUploaded) {
        switch (row.kind) {
          case _Kind.grading:
            final record = await widget.repository.inspectionByUuid(row.uuid);
            if (record != null) {
              await widget.repository.upload(record, token: token);
            }
          case _Kind.label:
            final record = await capture.labelInspectionByUuid(row.uuid);
            if (record != null) {
              await capture.uploadLabelInspection(record, token: token);
            }
          case _Kind.quid:
            final record = await capture.quidInspectionByUuid(row.uuid);
            if (record != null) {
              await capture.uploadQuidInspection(record, token: token);
            }
        }
      }
      // The photographs and signatures go with the record — a direction is
      // written from the evidence, so a record without it is half a record.
      await capture.uploadEvidenceFor(row.uuid, token: token);
      if (!mounted) return;
      _toast('${row.kindLabel} inspection sent.');
    } on Object catch (e) {
      if (!mounted) return;
      _toast('Send failed. $e');
    } finally {
      if (mounted) {
        setState(() => _uploading.remove(row.uuid));
        _refresh();
      }
    }
  }

  Future<void> _open(_Row row) async {
    switch (row.kind) {
      case _Kind.grading:
        if (row.isCompleted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PoultryInspectionSummaryPage(
                repository: widget.repository,
                inspectionUuid: row.uuid,
              ),
            ),
          );
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute<bool>(
              builder: (_) => PoultryInspectionForm(
                repository: widget.repository,
                captureRepository: widget.captureRepository,
                inspectorName: widget.user.userName,
                existingUuid: row.uuid,
              ),
            ),
          );
        }
      case _Kind.label:
        // The label form restores a saved record, so it serves as both the
        // resume path and the read-back for a completed checklist.
        await Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) => PoultryLabelChecklistForm(
              repository: widget.repository,
              captureRepository: widget.captureRepository,
              inspectorName: widget.user.userName,
              existingUuid: row.uuid,
            ),
          ),
        );
      case _Kind.quid:
        final record =
            await widget.captureRepository.quidInspectionByUuid(row.uuid);
        if (record == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<bool>(
            builder: (_) => PoultryQuidWeighingForm(
              repository: widget.repository,
              captureRepository: widget.captureRepository,
              inspection: record,
            ),
          ),
        );
    }
    if (mounted) _refresh();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Poultry Inspection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<List<_Row>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <_Row>[];
          final completed = rows.where((r) => r.isCompleted).length;
          final uploaded = rows.where((r) => r.isUploaded).length;
          final pending = rows.length - uploaded;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _DateSelector(label: _dateLabel, onTap: _pickDates),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Count(
                      label: 'Completed',
                      value: completed,
                      colour: AppColors.brandTeal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Count(
                      label: 'Pending',
                      value: pending,
                      colour: AppColors.noticeForeground,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Count(
                      label: 'Uploaded',
                      value: uploaded,
                      colour: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'INSPECTION LIST',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    _isSingleDay
                        ? 'No inspections captured on the selected date.'
                        : 'No inspections captured between the selected dates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                )
              else
                for (final row in rows) ...[
                  _RecordCard(
                    row: row,
                    uploading: _uploading.contains(row.uuid),
                    onSend: () => _send(row),
                    onOpen: () => _open(row),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 20, color: AppColors.brandTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Between dates',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    required this.colour,
  });

  final String label;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colour.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: colour,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ],
        ),
      );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.row,
    required this.uploading,
    required this.onSend,
    required this.onOpen,
  });

  final _Row row;
  final bool uploading;
  final VoidCallback onSend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final captured = row.inspectedAt.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Which checklist this is — three kinds share the list, and a
              // card that does not say which invites sending the wrong one.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandTeal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  row.kindLabel,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brandTeal,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: row.isUploaded
                      ? const Color(0xFFEAF5EB)
                      : AppColors.noticeBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  row.isUploaded
                      ? (row.hasPendingEvidence
                          ? 'Attachments pending'
                          : 'Uploaded')
                      : 'Pending',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: row.isUploaded && !row.hasPendingEvidence
                        ? const Color(0xFF2E7D32)
                        : AppColors.noticeForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.title,
            style:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
          ),
          const SizedBox(height: 2),
          Text(
            '${row.subtitle}   •   '
            '${captured.hour.toString().padLeft(2, '0')}:'
            '${captured.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          if (!row.isCompleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Unfinished — resume it to complete it.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.noticeForeground,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: Icon(
                      row.isCompleted
                          ? Icons.visibility_outlined
                          : Icons.edit_outlined,
                      size: 18,
                    ),
                    label: Text(row.isCompleted ? 'View' : 'Resume'),
                  ),
                ),
              ),
              // Send only once completed: uploading a draft puts it on the
              // server, from where every device downloads it back as work
              // nobody can discard.
              if (row.needsSend) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: uploading ? null : onSend,
                      icon: uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(uploading ? 'Sending…' : 'Send'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
