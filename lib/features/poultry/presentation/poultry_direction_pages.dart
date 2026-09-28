import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import '../domain/poultry_rules.dart';
import '../../../core/widgets/search_picker.dart';
import 'poultry_form_widgets.dart';

/// Poultry Direction Management.
///
/// The original filters by a single date. This filters by a span, matching Egg
/// and Poultry Inspection Management — a round is rarely one day's work, and
/// having one screen behave differently from its neighbours is its own bug.
class PoultryDirectionManagementPage extends StatefulWidget {
  const PoultryDirectionManagementPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<PoultryDirectionManagementPage> createState() =>
      _PoultryDirectionManagementPageState();
}

class _PoultryDirectionManagementPageState
    extends State<PoultryDirectionManagementPage> {
  late Future<List<PoultryDirection>> _rows;

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

  Future<List<PoultryDirection>> _load() async {
    _token = await widget.captureRepository.storedToken();
    final all = await widget.captureRepository.directions(widget.user.userName);
    return all
        .where((d) => PoultryCaptureRepository.withinDays(
              d.issuedAt.toLocal(),
              _range.start,
              _range.end,
            ))
        .toList();
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

  Future<void> _newDirection() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => PoultryDirectionForm(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          inspectorName: widget.user.userName,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _send(PoultryDirection direction) async {
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
      await widget.captureRepository.uploadDirection(direction, token: token);
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
          'Poultry Rejection Management',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDirection,
        // Red, as everything to do with a rejection is.
        backgroundColor: AppColors.brandRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New rejection'),
      ),
      body: ContentWidth(
          child: FutureBuilder<List<PoultryDirection>>(
        future: _rows,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <PoultryDirection>[];
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
              Text(
                'REJECTION LIST',
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
                for (final row in rows) ...[
                  _DirectionCard(
                    direction: row,
                    uploading: _uploading.contains(row.clientUuid),
                    onSend: () => _send(row),
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

/// A direction served on a client.
class PoultryDirectionForm extends StatefulWidget {
  const PoultryDirectionForm({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.inspectorName,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final String inspectorName;

  @override
  State<PoultryDirectionForm> createState() => _PoultryDirectionFormState();
}

class _DirectionReference {
  _DirectionReference({
    required this.remarks,
    required this.clients,
    required this.facilities,
  });

  final List<PoultryDesignationRef> remarks;

  /// The client and premises directories, shared with the egg module. A
  /// direction is served on a client, and picking one fills the details the
  /// way the egg direction form does.
  final List<EggClient> clients;
  final List<EggFacility> facilities;
}

class _PoultryDirectionFormState extends State<PoultryDirectionForm> {
  late Future<_DirectionReference> _reference;
  final _formKey = GlobalKey<FormState>();

  final _facilityName = TextEditingController();
  final _clientName = TextEditingController();
  final _clientEmail = TextEditingController();
  final _remarks = TextEditingController();
  final _comments = TextEditingController();
  final _action = TextEditingController();

  int? _remarkTypeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reference = _load();
  }

  Future<_DirectionReference> _load() async => _DirectionReference(
        remarks: await widget.repository.directionRemarks(),
        clients: await widget.repository.clients(),
        facilities: await widget.repository.facilities(),
      );

  @override
  void dispose() {
    for (final c in [
      _facilityName,
      _clientName,
      _clientEmail,
      _remarks,
      _comments,
      _action,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    await widget.captureRepository.saveDirection(
      PoultryDirectionsCompanion.insert(
        clientUuid: const Uuid().v4(),
        issuedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        inspectorUsername: Value(widget.inspectorName),
        status: const Value('completed'),
        facilityName: Value(_facilityName.text.trim()),
        clientName: Value(_clientName.text.trim()),
        clientEmail: Value(_clientEmail.text.trim()),
        remarkTypeId: Value(_remarkTypeId),
        remarks: Value(_remarks.text.trim()),
        comments: Value(_comments.text.trim()),
        actionTaken: Value(_action.text.trim()),
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'New Rejection',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_DirectionReference>(
        future: _reference,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final reference = snap.data;
          if (reference == null) return const PoultryNoRules();

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                poultrySection('Client'),
                SearchPickerField<EggFacility>(
                  label: 'Facility name',
                  controller: _facilityName,
                  options: reference.facilities,
                  optionLabel: (f) => f.name,
                  optionSubtitle: (f) => f.physicalAddress,
                  isRequired: true,
                  onSelected: (f) =>
                      setState(() => _facilityName.text = f.name),
                  emptyHint: 'No facilities on this device yet. Open the '
                      'Server Sync with a network connection to download the directory.',
                ),
                // Picking a known client fills the address a direction is
                // actually sent to, instead of retyping it at the roadside.
                SearchPickerField<EggClient>(
                  label: 'Client Name',
                  controller: _clientName,
                  options: reference.clients,
                  optionLabel: (c) => c.name,
                  optionSubtitle: (c) => [
                    if (c.tradingName.trim().isNotEmpty) 't/a ${c.tradingName}',
                    c.physicalAddress,
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  onSelected: (c) => setState(() {
                    _clientName.text = c.name;
                    if (c.email.trim().isNotEmpty) {
                      _clientEmail.text = c.email;
                    }
                  }),
                  emptyHint: 'No clients on this device yet. Open Server Sync '
                      'with a network connection to download the directory.',
                ),
                poultryField(
                  _clientEmail,
                  'Email address #1',
                  keyboard: TextInputType.emailAddress,
                ),

                poultrySection('Rejection Form'),
                poultryDropdown(
                  label: 'Grading Non-Conformance Remarks',
                  value: _remarkTypeId,
                  items: reference.remarks,
                  onChanged: (v) => setState(() => _remarkTypeId = v),
                ),
                poultryField(_remarks, 'List of Added Remarks', lines: 2),
                poultryField(_comments, 'Comments/Remarks on Rejection',
                    lines: 3),
                poultryField(_action, 'Batch No. and/or Quantity Removed'),

                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandRed),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Issue rejection'),
                  ),
                ),
              ],
            ),
          );
        },
      )),
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

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.direction,
    required this.uploading,
    required this.onSend,
  });

  final PoultryDirection direction;
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
                  d.facilityName.isEmpty ? '(no facility)' : d.facilityName,
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
          if (d.clientName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                d.clientName,
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          if (d.remarks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(d.remarks, style: const TextStyle(fontSize: 13.5)),
            ),
          if (d.correctByDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Correct by ${d.correctByDate!.day.toString().padLeft(2, '0')}/'
                '${d.correctByDate!.month.toString().padLeft(2, '0')}/'
                '${d.correctByDate!.year}',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          if (!d.isUploaded) ...[
            const SizedBox(height: 10),
            SizedBox(
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
          ],
        ],
      ),
    );
  }
}
