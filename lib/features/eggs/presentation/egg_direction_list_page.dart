import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import '../data/eggs_sync_service.dart';
import 'admin_status_actions.dart';
import 'egg_direction_form.dart';
import 'egg_direction_summary_page.dart';
import 'summary_widgets.dart';

/// Egg Direction Management.
///
/// Pick a date, see the Completed / Pending / Uploaded counts for that period,
/// then open, send or raise a direction.
class EggDirectionListPage extends StatefulWidget {
  const EggDirectionListPage({
    super.key,
    required this.repository,
    required this.user,
    this.syncService,
  });

  final EggsRepository repository;
  final SessionUser user;
  final EggsSyncService? syncService;

  @override
  State<EggDirectionListPage> createState() => _EggDirectionListPageState();
}

class _EggDirectionListPageState extends State<EggDirectionListPage> {
  late Future<List<EggDirection>> _items;

  /// Inclusive at both ends, compared by calendar day. Matches Egg
  /// Inspection Management, so the two pages filter the same way.
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );
  final _uploading = <String>{};
  String? _token;
  bool _busy = false;

  StreamSubscription<SyncReport>? _syncWatch;

  @override
  void dispose() {
    _syncWatch?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Redraws as records go up, rather than only on reopening the page.
    _syncWatch = widget.syncService?.onSync.listen((_) {
      if (mounted) _refresh();
    });
    _items = _load();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// By calendar day, so a record issued at 16:40 on the closing day counts.
  bool _withinRange(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    final start =
        DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool get _isSingleDay => _sameDay(_range.start, _range.end);

  Future<List<EggDirection>> _load() async {
    _token = await widget.repository.storedToken();
    final all = await widget.repository.savedDirections();
    return all.where((d) => _withinRange(d.issuedAt.toLocal())).toList();
  }

  // Block body, not an arrow: an arrow returns the assigned Future, and
  // setState asserts when its callback returns one.
  void _refresh() => setState(() {
        _items = _load();
      });

  Future<void> _newDirection() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggDirectionForm(
          repository: widget.repository,
          inspectorName: widget.user.userName,
          syncService: widget.syncService,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _view(EggDirection direction) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggDirectionSummaryPage(
          repository: widget.repository,
          directionUuid: direction.clientUuid,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
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
      message: 'Every rejection issued $_scopeWording will be marked as not '
          'yet sent, so it uploads again next time you send. Nothing is '
          'deleted.',
      confirmLabel: 'Re-queue',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final changed = await widget.repository
        .markDirectionsPendingBetween(_range.start, _range.end);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(changed == 0
        ? 'Nothing changed — every rejection for $_dateLabel was already '
            'waiting to send.'
        : '$changed ${changed == 1 ? "rejection" : "rejections"} re-queued.');
    // Start a pass now, so the status moves while they are looking
    // at it rather than up to two minutes later.
    unawaited(widget.syncService?.syncNow() ?? Future<void>.value());
    _refresh();
  }

  Future<void> _markSent() async {
    final ok = await confirmStatusChange(
      context,
      title: 'Mark $_dateLabel as sent?',
      message: 'Every rejection issued $_scopeWording will be treated as '
          'already on the server and will not be uploaded. Only do this when '
          'you know the server has them.',
      confirmLabel: 'Mark as sent',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final changed = await widget.repository
        .markDirectionsUploadedBetween(_range.start, _range.end);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(changed == 0
        ? 'Nothing changed — every rejection for $_dateLabel was already '
            'marked as sent.'
        : '$changed ${changed == 1 ? "rejection" : "rejections"} marked as '
            'sent.');
    _refresh();
  }

  Future<void> _send(EggDirection direction) async {
    final token = _token;
    if (token == null) {
      _toast(
        'This device has never signed in online, so there is no credential to '
        'upload with. Sign in once with signal, then send.',
      );
      return;
    }
    setState(() => _uploading.add(direction.clientUuid));
    try {
      await widget.repository.uploadDirection(direction, token: token);
      if (!mounted) return;
      _toast('Rejection sent.');
    } on Object catch (e) {
      if (!mounted) return;
      _toast('Send failed. $e');
    } finally {
      if (mounted) {
        setState(() => _uploading.remove(direction.clientUuid));
        _refresh();
      }
    }
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
          'Egg Rejection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDirection,
        // Serving a rejection is the one destructive thing an inspector
        // does to a consignment, and it carries the app's red everywhere it
        // is shown — the same red the DEVIATION side of every checklist
        // slide already uses. In teal it read like any other action.
        backgroundColor: AppColors.brandRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New rejection'),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<EggDirection>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <EggDirection>[];
          final completed = rows.where((d) => d.status == 'completed').length;
          final uploaded = rows.where((d) => d.isUploaded).length;
          final pending = rows.length - uploaded;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _DateSelector(
                label: _dateLabel,
                onTap: () async {
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
                },
              ),
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
              Text(
                'REJECTIONS FOR SELECTED PERIOD',
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
                        ? 'No rejections issued on the selected date.'
                        : 'No rejections issued between the selected dates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                )
              else
                for (final d in rows) ...[
                  _DirectionCard(
                    direction: d,
                    inspectorName: widget.user.userName,
                    uploading: _uploading.contains(d.clientUuid),
                    onSend: () => _send(d),
                    onView: () => _view(d),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      )),
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

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.direction,
    required this.inspectorName,
    required this.uploading,
    required this.onSend,
    required this.onView,
  });

  final EggDirection direction;
  final String inspectorName;
  final VoidCallback onView;
  final bool uploading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final d = direction;
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
                  d.clientName.isEmpty ? '(no client)' : d.clientName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: d.isUploaded
                      ? const Color(0xFFEAF5EB)
                      : AppColors.noticeBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  d.isUploaded ? 'Uploaded' : 'Pending',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: d.isUploaded
                        ? const Color(0xFF2E7D32)
                        : AppColors.noticeForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row('Issued', formatTime(d.issuedAt.toLocal())),
          if (d.status != 'completed')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Unfinished — resume it from the Eggs menu to complete it.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.noticeForeground,
                ),
              ),
            ),
          _row('Covers', directionParts(d)),
          _row('Number', d.directionNumber.isEmpty ? '—' : d.directionNumber),
          _row('Producer',
              d.producerSupplier.isEmpty ? '—' : d.producerSupplier),
          if (d.qualityPart)
            _row(
              'Quality correct by',
              d.qualityCorrectBy == null
                  ? '—'
                  : '${d.qualityCorrectBy!.toLocal()}'.split(' ').first,
            ),
          if (d.labellingPart)
            _row(
              'Labelling correct by',
              d.labelCorrectBy == null
                  ? '—'
                  : '${d.labelCorrectBy!.toLocal()}'.split(' ').first,
            ),
          _row('Inspector', inspectorName),
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
              // Send is not offered on an unfinished notice: uploading one puts it on
              // the server, from where every device downloads it back as a draft.
              if (!d.isUploaded && d.status == 'completed') ...[
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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13.5)),
            ),
          ],
        ),
      );
}
