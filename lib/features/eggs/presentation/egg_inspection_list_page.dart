import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import '../data/eggs_sync_service.dart';
import 'admin_status_actions.dart';
import 'egg_inspection_summary_page.dart';
import 'summary_widgets.dart';

/// Egg Inspection Management.
///
/// Pick a span of dates, see the Completed / Pending / Uploaded counts for that
/// period, then open or send any record in the list.
///
/// A range rather than a single day: a round is rarely one day's work, and
/// reviewing a week meant stepping through it a day at a time with no way to
/// see the totals. Both ends default to today, so opening the page still shows
/// today's records.
///
/// "Send" reports what actually happened rather than assuming success, and a
/// row cannot be sent when the device has never been online — there is no
/// token to authenticate with.
class EggInspectionListPage extends StatefulWidget {
  const EggInspectionListPage({
    super.key,
    required this.repository,
    required this.user,
    this.syncService,
  });

  final EggsRepository repository;
  final SessionUser user;

  /// Watched so the list changes as records go up, rather than only when the
  /// page is left and reopened.
  final EggsSyncService? syncService;

  @override
  State<EggInspectionListPage> createState() => _EggInspectionListPageState();
}

class _Row {
  _Row({
    required this.inspection,
    required this.sizeSummary,
    required this.gradeName,
  });

  final EggInspection inspection;
  final String sizeSummary;
  final String gradeName;
}

class _EggInspectionListPageState extends State<EggInspectionListPage> {
  late Future<List<_Row>> _rows;
  /// Inclusive at both ends, compared by calendar day.
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );
  final _uploading = <String>{};
  String? _token;
  bool _busy = false;
  StreamSubscription<SyncReport>? _syncWatch;

  @override
  void initState() {
    super.initState();
    _rows = _load();
    // Every completed pass redraws the list, so "Pending" becomes "Uploaded"
    // in front of the inspector instead of the next time they open the page.
    _syncWatch = widget.syncService?.onSync.listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _syncWatch?.cancel();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// By calendar day, so a record captured at 16:40 on the closing day counts.
  bool _withinRange(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    final start =
        DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool get _isSingleDay => _sameDay(_range.start, _range.end);

  Future<List<_Row>> _load() async {
    _token = await widget.repository.storedToken();
    final grades = await widget.repository.grades();
    final sizes = await widget.repository.sizeBands();
    final gradeNames = {for (final g in grades) g.id: g.name};
    final sizeNames = {for (final s in sizes) s.id: s.name};

    final all = await widget.repository.savedInspections();
    final inRange =
        all.where((i) => _withinRange(i.inspectedAt.toLocal())).toList();

    final rows = <_Row>[];
    for (final inspection in inRange) {
      final samples = await widget.repository.samplesFor(inspection.clientUuid);
      // A consignment can span size bands, so show the distinct set rather
      // than pretending it is a single value.
      final present = <String>{
        for (final s in samples)
          if (s.sizeId != null) sizeNames[s.sizeId!] ?? '?',
      };
      rows.add(
        _Row(
          inspection: inspection,
          sizeSummary: present.isEmpty ? '—' : present.join(', '),
          gradeName: gradeNames[inspection.determinedGradeId] ?? 'ungraded',
        ),
      );
    }
    return rows;
  }

  // Block body, not an arrow: an arrow returns the assigned Future, and
  // setState asserts when its callback returns one.
  void _refresh() => setState(() {
        _rows = _load();
      });

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

  Future<void> _send(EggInspection inspection) async {
    final token = _token;
    if (token == null) {
      _toast(
        'This device has never signed in online, so there is no credential to '
        'upload with. Sign in once with signal, then send.',
      );
      return;
    }
    setState(() => _uploading.add(inspection.clientUuid));
    try {
      await widget.repository.upload(inspection, token: token);
      if (!mounted) return;
      _toast('Inspection sent.');
    } on Object catch (e) {
      if (!mounted) return;
      _toast('Send failed. $e');
    } finally {
      if (mounted) {
        setState(() => _uploading.remove(inspection.clientUuid));
        _refresh();
      }
    }
  }

  Future<void> _sendAll(List<_Row> rows) async {
    final pending = rows.where((r) => !r.inspection.isUploaded).toList();
    for (final row in pending) {
      await _send(row.inspection);
    }
  }

  Future<void> _view(EggInspection inspection) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggInspectionSummaryPage(
          repository: widget.repository,
          inspectionUuid: inspection.clientUuid,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// One date when both ends are the same day, so the ordinary case does not
  /// read as "18/08/2026 - 18/08/2026".
  String get _dateLabel => _isSingleDay
      ? _day(_range.start)
      : '${_day(_range.start)} - ${_day(_range.end)}';

  /// Names what a bulk correction will actually touch, rather than always
  /// implying a single day.
  String get _scopeWording =>
      _isSingleDay ? 'on this date' : 'between these dates';

  Future<void> _requeue() async {
    final ok = await confirmStatusChange(
      context,
      title: 'Re-queue $_dateLabel?',
      message: 'Every inspection captured $_scopeWording will be marked as '
          'not yet sent, so it uploads again next time you send. Nothing is '
          'deleted.',
      confirmLabel: 'Re-queue',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final changed = await widget.repository
        .markInspectionsPendingBetween(_range.start, _range.end);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(changed == 0
        ? 'Nothing changed — every inspection for $_dateLabel was already '
            'waiting to send.'
        : '$changed ${changed == 1 ? "inspection" : "inspections"} re-queued.');
    // Start a pass now, so the status moves while they are looking
    // at it rather than up to two minutes later.
    unawaited(widget.syncService?.syncNow() ?? Future<void>.value());
    _refresh();
  }

  Future<void> _markSent() async {
    final ok = await confirmStatusChange(
      context,
      title: 'Mark $_dateLabel as sent?',
      message: 'Every inspection captured $_scopeWording will be treated as '
          'already on the server and will not be uploaded. Only do this when '
          'you know the server has them.',
      confirmLabel: 'Mark as sent',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final changed = await widget.repository
        .markInspectionsUploadedBetween(_range.start, _range.end);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(changed == 0
        ? 'Nothing changed — every inspection for $_dateLabel was already '
            'marked as sent.'
        : '$changed ${changed == 1 ? "inspection" : "inspections"} marked as '
            'sent.');
    _refresh();
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
          'Egg Inspection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
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
          final completed =
              rows.where((r) => r.inspection.status == 'completed').length;
          final uploaded = rows.where((r) => r.inspection.isUploaded).length;
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
              if (widget.user.isSystemAdministrator)
                AdminStatusActions(
                  dateLabel: _dateLabel,
                  busy: _busy || _uploading.isNotEmpty,
                  onRequeue: _requeue,
                  onMarkSent: _markSent,
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'COMPLETED INSPECTION LIST',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (pending > 0)
                    TextButton.icon(
                      onPressed: _uploading.isEmpty
                          ? () => _sendAll(rows)
                          : null,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text('Send all ($pending)'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    _isSingleDay
                        ? 'No inspections captured on the selected date.'
                        : 'No inspections captured between the selected '
                            'dates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                )
              else
                for (final row in rows) ...[
                  _InspectionCard(
                    row: row,
                    uploading: _uploading.contains(row.inspection.clientUuid),
                    onSend: () => _send(row.inspection),
                    onView: () => _view(row.inspection),
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

  /// Already formatted - one date, or two separated by a dash.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({
    required this.row,
    required this.uploading,
    required this.onSend,
    required this.onView,
  });

  final _Row row;
  final bool uploading;
  final VoidCallback onSend;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final i = row.inspection;
    final captured = formatTime(i.inspectedAt.toLocal());
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
              Expanded(
                child: Text(
                  i.clientName.isEmpty ? '(no client)' : i.clientName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: i.isUploaded
                      ? const Color(0xFFEAF5EB)
                      : AppColors.noticeBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  i.isUploaded ? 'Uploaded' : 'Pending',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: i.isUploaded
                        ? const Color(0xFF2E7D32)
                        : AppColors.noticeForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _field('Producer',
              i.producerSupplier.isEmpty ? '—' : i.producerSupplier),
          _field('Size', row.sizeSummary),
          _field('Grade', row.gradeName),
          _field('Eggs', '${i.sampleSize ?? 0}'),
          _field('Captured', captured),
          if (i.status != 'completed')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Unfinished — resume it from the Eggs menu to complete it.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.noticeForeground,
                ),
              ),
            ),
          if (i.gradeOverridden)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Grade overridden by inspector',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandRed,
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
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                ),
              ),
              // Send is not offered on an unfinished inspection. Uploading a
              // draft put it on the server, from where every device downloaded
              // it back as an unfinished inspection nobody could discard.
              if (!i.isUploaded && i.status == 'completed') ...[
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

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
}
