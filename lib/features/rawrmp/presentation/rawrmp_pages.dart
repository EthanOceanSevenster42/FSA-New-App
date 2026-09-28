import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../data/rawrmp_repository.dart';
import 'rawrmp_inspection_form.dart';
import 'rawrmp_summary_pages.dart';
import '../domain/raw_record_kind.dart';

/// Certain Raw Processed Meat Products landing page.
///
/// The original's menu, in its order: New Inspection, Inspection Management,
/// Direction Management, Pending Courier Samples. There is no Product
/// Precheck on this commodity — the original does not offer one — and its
/// "Seizure Management" is commented out there and absent here too.
class RawRmpMenuPage extends StatefulWidget {
  const RawRmpMenuPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final RawRmpRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<RawRmpMenuPage> createState() => _RawRmpMenuPageState();
}

class _RawRmpMenuPageState extends State<RawRmpMenuPage> {
  late Future<int> _rules;

  @override
  void initState() {
    super.initState();
    _rules = _prepare();
  }

  Future<int> _prepare() async {
    await widget.repository.loadBundledRulesIfEmpty();
    final items = await widget.repository.checklistItems();
    // Best-effort refresh; failure must not block the menu.
    unawaited(widget.repository.syncReference().catchError((_) => 0));
    return items.length;
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<bool>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Certain Raw Processed Meat Products',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<int>(
        future: _rules,
        builder: (context, snap) {
          final ready = (snap.data ?? 0) > 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              _Tile(
                title: 'New Inspection',
                subtitle: 'Labels, containers, sampling and the laboratory',
                icon: Icons.assignment_outlined,
                onTap: ready
                    ? () => _open(RawRmpInspectionForm(
                          repository: widget.repository,
                          captureRepository: widget.captureRepository,
                          inspectorName: widget.user.userName,
                          recordKind: RawRecordKind.inspection,
                        ))
                    : null,
              ),
              _Tile(
                title: 'New Compositional Checklist',
                subtitle: 'Regulation 5 compositional requirements',
                icon: Icons.science_outlined,
                onTap: ready
                    ? () => _open(RawRmpInspectionForm(
                          repository: widget.repository,
                          captureRepository: widget.captureRepository,
                          inspectorName: widget.user.userName,
                          recordKind: RawRecordKind.composition,
                        ))
                    : null,
              ),
              _Tile(
                title: 'Inspection Management',
                subtitle: 'Review, resume and send captured inspections',
                icon: Icons.fact_check_outlined,
                onTap: () => _open(RawRmpInspectionListPage(
                  repository: widget.repository,
                  captureRepository: widget.captureRepository,
                  user: widget.user,
                )),
              ),
              _Tile(
                title: 'Rejection Management',
                subtitle: 'Review and send issued rejections',
                icon: Icons.gavel_outlined,
                onTap: () => _open(RawRmpDirectionManagementPage(
                  repository: widget.repository,
                  captureRepository: widget.captureRepository,
                  user: widget.user,
                )),
                accent: AppColors.brandRed,
              ),
              _Tile(
                title: 'Pending Courier Samples',
                subtitle: 'Capture waybill numbers for couriered samples',
                icon: Icons.local_shipping_outlined,
                onTap: () => _open(RawRmpPendingCourierPage(
                  repository: widget.repository,
                  user: widget.user,
                )),
              ),
            ],
          );
        },
      )),
    );
  }
}

/// Pending Courier Samples.
///
/// A couriered sample is not finished until its waybill number is captured —
/// the original gives that gap its own screen ("RawRMP Pending Couriered
/// Samples"), and so does this. Saving a waybill marks the record as needing
/// upload again, so the register's copy carries it too.
class RawRmpPendingCourierPage extends StatefulWidget {
  const RawRmpPendingCourierPage({
    super.key,
    required this.repository,
    required this.user,
  });

  final RawRmpRepository repository;
  final SessionUser user;

  @override
  State<RawRmpPendingCourierPage> createState() =>
      _RawRmpPendingCourierPageState();
}

class _RawRmpPendingCourierPageState extends State<RawRmpPendingCourierPage> {
  late Future<List<RawRmpInspection>> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.repository.pendingCourier(widget.user.userName);
  }

  void _refresh() => setState(() {
        _rows = widget.repository.pendingCourier(widget.user.userName);
      });

  Future<void> _captureWaybill(RawRmpInspection inspection) async {
    final controller = TextEditingController();
    final waybill = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Waybill number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Waybill',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (waybill == null || waybill.isEmpty) return;

    await widget.repository.setWaybill(inspection.clientUuid, waybill);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Waybill saved. Send the inspection again from Inspection '
          'Management so the register carries it.',
        ),
        backgroundColor: AppColors.ink,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Pending Courier Samples',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<RawRmpInspection>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <RawRmpInspection>[];
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No couriered samples are waiting for a waybill.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              for (final row in rows) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.facilityName.isEmpty
                            ? '(no facility)'
                            : row.facilityName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (row.productItem.isNotEmpty) row.productItem,
                          if (row.internalSampleNumber.isNotEmpty)
                            'Sample ${row.internalSampleNumber}',
                        ].join('   •   '),
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _captureWaybill(row),
                          icon: const Icon(Icons.local_shipping_outlined,
                              size: 18),
                          label: const Text('Capture waybill'),
                        ),
                      ),
                    ],
                  ),
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

/// RawRMP Inspection Management — the between-dates register.
class RawRmpInspectionListPage extends StatefulWidget {
  const RawRmpInspectionListPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final RawRmpRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<RawRmpInspectionListPage> createState() =>
      _RawRmpInspectionListPageState();
}

class _RawRmpInspectionListPageState extends State<RawRmpInspectionListPage> {
  late Future<List<RawRmpInspection>> _rows;

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

  Future<List<RawRmpInspection>> _load() async {
    _token = await widget.repository.storedToken();
    final all = await widget.repository.savedInspections(widget.user.userName);
    return [
      for (final i in all)
        if (PoultryCaptureRepository.withinDays(
          i.inspectedAt.toLocal(),
          _range.start,
          _range.end,
        ))
          i,
    ];
  }

  void _refresh() => setState(() {
        _rows = _load();
      });

  String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
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

  Future<void> _send(RawRmpInspection inspection) async {
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
      if (!inspection.isUploaded) {
        await widget.repository.upload(inspection, token: token);
      }
      // The photographs and signatures go with the record.
      await widget.captureRepository
          .uploadEvidenceFor(inspection.clientUuid, token: token);
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

  Future<void> _open(RawRmpInspection inspection) async {
    // A completed record opens as its read-only summary — the original's
    // View button leads to the summary page, not back into the capture form.
    if (inspection.status == 'completed') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RawRmpInspectionSummaryPage(
            inspection: inspection,
            repository: widget.repository,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => RawRmpInspectionForm(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          inspectorName: widget.user.userName,
          existingUuid: inspection.clientUuid,
        ),
      ),
    );
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
          'Certain Raw Processed Meat Product Inspection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<RawRmpInspection>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <RawRmpInspection>[];
          final completed = rows.where((r) => r.status == 'completed').length;
          final uploaded = rows.where((r) => r.isUploaded).length;

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
                      value: rows.length - uploaded,
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
                  _InspectionCard(
                    inspection: row,
                    uploading: _uploading.contains(row.clientUuid),
                    onSend: () => _send(row),
                    onOpen: () => _open(row),
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

/// RawRMP Direction Management, matching its neighbours: a between-dates
/// register. Directions are raised by the inspection form, as in the
/// original; here they are reviewed and sent.
class RawRmpDirectionManagementPage extends StatefulWidget {
  const RawRmpDirectionManagementPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final RawRmpRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<RawRmpDirectionManagementPage> createState() =>
      _RawRmpDirectionManagementPageState();
}

class _RawRmpDirectionManagementPageState
    extends State<RawRmpDirectionManagementPage> {
  late Future<List<RawRmpDirection>> _rows;

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

  Future<List<RawRmpDirection>> _load() async {
    _token = await widget.repository.storedToken();
    final all = await widget.repository.directions(widget.user.userName);
    return [
      for (final d in all)
        if (PoultryCaptureRepository.withinDays(
          d.issuedAt.toLocal(),
          _range.start,
          _range.end,
        ))
          d,
    ];
  }

  void _refresh() => setState(() {
        _rows = _load();
      });

  String _day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String get _dateLabel => _sameDay(_range.start, _range.end)
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

  Future<void> _send(RawRmpDirection direction) async {
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
          'Certain Raw Processed Meat Product Rejection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<RawRmpDirection>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <RawRmpDirection>[];
          final uploaded = rows.where((r) => r.isUploaded).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _DateSelector(label: _dateLabel, onTap: _pickDates),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Count(
                      label: 'Issued',
                      value: rows.length,
                      colour: AppColors.brandTeal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Count(
                      label: 'Pending',
                      value: rows.length - uploaded,
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
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'No rejections issued in this period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                )
              else
                for (final row in rows) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.facilityName.isEmpty
                              ? '(no facility)'
                              : row.facilityName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        if (row.remarks.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              row.remarks,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => RawRmpDirectionSummaryPage(
                                  direction: row,
                                  repository: widget.repository,
                                  captureRepository: widget.captureRepository,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 18,
                            ),
                            label: const Text('View'),
                          ),
                        ),
                        if (!row.isUploaded) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: _uploading.contains(row.clientUuid)
                                  ? null
                                  : () => _send(row),
                              icon: const Icon(Icons.cloud_upload_outlined,
                                  size: 18),
                              label: Text(
                                _uploading.contains(row.clientUuid)
                                    ? 'Sending…'
                                    : 'Send',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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

// ---------------------------------------------------------------------------
// Shared card widgets
// ---------------------------------------------------------------------------

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  /// Overrides the icon's colour. Rejections carry the app's red, the same
  /// red the DEVIATION side of every checklist slide uses.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: enabled ? AppColors.surfaceAlt : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: enabled
                      ? (accent ?? AppColors.brandTeal)
                      : AppColors.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: enabled ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style:
                            TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (enabled) Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
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

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({
    required this.inspection,
    required this.uploading,
    required this.onSend,
    required this.onOpen,
  });

  final RawRmpInspection inspection;
  final bool uploading;
  final VoidCallback onSend;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final i = inspection;
    final completed = i.status == 'completed';
    final captured = i.inspectedAt.toLocal();
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
                  i.facilityName.isEmpty ? '(no facility)' : i.facilityName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(height: 4),
          Text(
            [
              if (i.productItem.isNotEmpty) i.productItem,
              if (i.isSampled) 'Sampled',
              if (i.isSampled && i.isCouriered && i.waybill.isEmpty)
                'Waybill outstanding',
              '${captured.hour.toString().padLeft(2, '0')}:'
                  '${captured.minute.toString().padLeft(2, '0')}',
            ].join('   •   '),
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          if (!completed)
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
                      completed
                          ? Icons.visibility_outlined
                          : Icons.edit_outlined,
                      size: 18,
                    ),
                    label: Text(completed ? 'View' : 'Resume'),
                  ),
                ),
              ),
              if (completed && !i.isUploaded) ...[
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
