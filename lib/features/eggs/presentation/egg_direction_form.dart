import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import '../data/eggs_sync_service.dart';
import '../domain/egg_rules.dart';
import 'date_field.dart';
import 'picker_sheet.dart';
import 'required_label.dart';
import 'saved_dialog.dart';

/// Capture a direction.
///
/// Covers the "Poultry Egg Quality Direction" and "Egg Labelling
/// Direction" forms: a direction number, a correct-by date, standard remarks
/// picked from a list plus free text, and the quantity of product removed.
class EggDirectionForm extends StatefulWidget {
  const EggDirectionForm({
    super.key,
    required this.repository,
    required this.inspectorName,
    this.syncService,
    this.inspectionUuid,
    this.requirement,
    this.clientName,
    this.producerSupplier,
    this.resumeUuid,
  });

  final EggsRepository repository;
  final String inspectorName;

  /// The inspection this direction arises from, when it was raised by one
  /// rather than started from the menu.
  final String? inspectionUuid;

  /// Which parts the inspection's findings make compulsory.
  ///
  /// When set, the parts are fixed: the rules decided them from the deviations
  /// and the labelling checklists, and an inspector cannot decline to serve a
  /// part the regulations require. Null means this was started by hand, and
  /// the parts are chosen.
  final DirectionRequirement? requirement;

  final String? clientName;
  final String? producerSupplier;

  /// An unfinished direction to pick back up, the way an inspection can be.
  /// A notice is often written standing next to the consignment, and the app
  /// can be killed for memory at any point.
  final String? resumeUuid;

  /// Sends the direction the moment it is saved, when there is a signal.
  final EggsSyncService? syncService;

  @override
  State<EggDirectionForm> createState() => _EggDirectionFormState();
}

class _EggDirectionFormState extends State<EggDirectionForm> {
  /// A resumed draft keeps the uuid it was saved under, so continuing writes
  /// back to the same row rather than leaving the old one behind.
  late final String _uuid = widget.resumeUuid ?? const Uuid().v4();

  /// True while the draft is being written, to keep concurrent saves out of
  /// each other's way.
  bool _savingDraft = false;
  Timer? _draftDebounce;

  /// A direction carries either part or both; each has its own deadline.
  late bool _labelling = widget.requirement?.labelling ?? false;
  late bool _quality = widget.requirement?.quality ?? true;

  /// True when the rules chose the parts, so they are shown but not editable.
  bool get _partsFixed => widget.requirement != null;

  final _remarksByType = <String, List<EggDirectionRemark>>{};
  List<EggClient> _clients = [];
  final _selectedRemarks = <int>{};
  EggClient? _client;
  DateTime? _labelCorrectBy;
  DateTime? _qualityCorrectBy;
  Position? _position;

  /// When the notice was started. Held so a resumed draft keeps its original
  /// time rather than jumping to whenever it was picked back up.
  DateTime _startedAt = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  final _number = TextEditingController();
  final _clientName = TextEditingController();
  final _producer = TextEditingController();
  final _quantity = TextEditingController();
  final _additional = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _fixLocation();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    for (final c in [
      _number, _clientName, _producer, _quantity, _additional,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _clients = await widget.repository.clients();
    // Both sets, because a direction can carry both parts and each has its own
    // remarks.
    for (final type in const ['quality', 'labelling']) {
      _remarksByType[type] = await widget.repository.directionRemarks(type);
    }
    _clientName.text = widget.clientName ?? '';
    _producer.text = widget.producerSupplier ?? '';
    if (widget.resumeUuid != null) await _restoreDraft();
    if (mounted) setState(() => _loading = false);
  }

  /// Remarks that no longer apply once a part is dropped.
  void _dropRemarksFor(String type) {
    for (final r in _remarksByType[type] ?? const <EggDirectionRemark>[]) {
      _selectedRemarks.remove(r.id);
    }
  }

  Future<void> _fixLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) setState(() => _position = pos);
    } on Object {
      // A missing fix does not stop a direction being issued.
    }
  }

  String? _blockingIssue() {
    if (_number.text.trim().isEmpty) return 'A direction number is required.';
    if (_clientName.text.trim().isEmpty) return 'A client is required.';
    if (!_labelling && !_quality) {
      return 'A direction must cover labelling, quality, or both.';
    }
    // Each part carries its own deadline, so a part without one is a notice
    // the client cannot comply with.
    if (_labelling && _labelCorrectBy == null) {
      return 'A correct-by date is required for the labelling part.';
    }
    if (_quality && _qualityCorrectBy == null) {
      return 'A correct-by date is required for the quality part.';
    }
    if (_selectedRemarks.isEmpty && _additional.text.trim().isEmpty) {
      return 'Select at least one remark, or write one.';
    }
    return null;
  }

  Future<void> _pickClient() async {
    final picked = await showPickerSheet<EggClient>(
      context: context,
      title: 'Select client',
      items: _clients,
      itemLabel: (c) => c.name,
      itemSubtitle: (c) => c.physicalAddress,
      selected: _client,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _client = picked;
      _clientName.text = picked.name;
    });
    _scheduleDraft();
  }

  /// Writes what has been entered so far, as a draft.
  ///
  /// Drafts are never uploaded — the sync service skips anything not
  /// `completed`, and the repository refuses outright — so this is purely a
  /// safety net against the process dying or the inspector being called away.
  Future<void> _saveDraft() async {
    if (_savingDraft) return;
    // Nothing worth keeping yet; an empty draft is just noise on the menu.
    if (_clientName.text.trim().isEmpty &&
        _number.text.trim().isEmpty &&
        _selectedRemarks.isEmpty &&
        _additional.text.trim().isEmpty) {
      return;
    }
    _savingDraft = true;
    try {
      await widget.repository.saveDirection(_companion(status: 'draft'));
    } on Object catch (error) {
      // A failed draft save must never interrupt capture.
      debugPrint('Could not save direction draft: $error');
    } finally {
      _savingDraft = false;
    }
  }

  /// Saves shortly after typing stops, rather than on every keystroke.
  void _scheduleDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(seconds: 1), () {
      unawaited(_saveDraft());
    });
  }

  /// The direction row, at whatever stage it has reached.
  EggDirectionsCompanion _companion({required String status}) {
    final now = DateTime.now();
    return EggDirectionsCompanion.insert(
      clientUuid: _uuid,
      inspectionUuid: Value(widget.inspectionUuid),
      labellingPart: Value(_labelling),
      qualityPart: Value(_quality),
      labelCorrectBy: Value(_labelling ? _labelCorrectBy : null),
      qualityCorrectBy: Value(_quality ? _qualityCorrectBy : null),
      issuedAt: _startedAt,
      updatedAt: now,
      status: Value(status),
      directionNumber: Value(_number.text.trim()),
      quantityRemoved: Value(
        double.tryParse(_quantity.text.trim().replaceAll(',', '.')),
      ),
      remarkIds: Value(_selectedRemarks.join(',')),
      additionalRemarks: Value(_additional.text.trim()),
      clientName: Value(_clientName.text.trim()),
      producerSupplier: Value(_producer.text.trim()),
      latitude: Value(_position?.latitude),
      longitude: Value(_position?.longitude),
    );
  }

  /// Reloads an unfinished direction into the form.
  Future<void> _restoreDraft() async {
    final draft = await widget.repository.directionByUuid(_uuid);
    if (draft == null) return;

    _startedAt = draft.issuedAt;
    _labelling = draft.labellingPart;
    _quality = draft.qualityPart;
    _labelCorrectBy = draft.labelCorrectBy;
    _qualityCorrectBy = draft.qualityCorrectBy;
    _number.text = draft.directionNumber;
    _clientName.text = draft.clientName;
    _producer.text = draft.producerSupplier;
    _quantity.text =
        draft.quantityRemoved == null ? '' : '${draft.quantityRemoved}';
    _additional.text = draft.additionalRemarks;
    _selectedRemarks
      ..clear()
      ..addAll(draft.remarkIds
          .split(',')
          .map((x) => int.tryParse(x.trim()))
          .whereType<int>());
    _client = _clients.where((c) => c.name == draft.clientName).firstOrNull;
  }

  Future<void> _save() async {
    final issue = _blockingIssue();
    if (issue != null) {
      _toast(issue);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.saveDirection(_companion(status: 'completed'));
    } on Object catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast('Could not save. $e');
      return;
    }

    // Saved. Upload failures from here are "will send later", not errors.
    var sent = false;
    final sync = widget.syncService;
    if (sync != null) {
      final saved = await widget.repository.directionByUuid(_uuid);
      if (saved != null) sent = await sync.sendDirectionNow(saved);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    await showSavedDialog(
      context,
      noun: 'direction',
      state: _savedState(sent, sync),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Turns the send result into something the inspector can act on.
  SavedState _savedState(bool sent, EggsSyncService? sync) {
    if (sent) return SavedState.sent;
    return switch (sync?.lastOutcome) {
      SendOutcome.notAuthenticated => SavedState.needsSignIn,
      SendOutcome.rejected => SavedState.rejected,
      // Offline, or a hiccup worth retrying. Either way the service handles it.
      _ => SavedState.queued,
    };
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'New Direction',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const _SectionLabel('WHAT THIS DIRECTION COVERS'),
          if (_partsFixed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Set from the inspection findings and cannot be changed here.',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.muted, height: 1.35),
              ),
            ),
          _PartTile(
            title: 'Quality - grade and size',
            value: _quality,
            enabled: !_partsFixed,
            onChanged: (v) {
              setState(() {
                _quality = v;
                if (!v) _dropRemarksFor('quality');
              });
              _scheduleDraft();
            },
          ),
          _PartTile(
            title: 'Labelling - marking and packing',
            value: _labelling,
            enabled: !_partsFixed,
            onChanged: (v) {
              setState(() {
                _labelling = v;
                if (!v) _dropRemarksFor('labelling');
              });
              _scheduleDraft();
            },
          ),
          const SizedBox(height: 18),
          // A sheet rather than a dropdown menu: a menu opens over its own
          // button and covers the fields around it.
          LabelledField(
            label: 'Select client',
            child: InkWell(
              onTap: _clients.isEmpty ? null : _pickClient,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                isEmpty: false,
                decoration: const InputDecoration(
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text(
                  _client?.name ??
                      (_clients.isEmpty
                          ? 'No clients on this device yet'
                          : 'Select'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight:
                        _client != null ? FontWeight.w700 : FontWeight.w400,
                    color: _client != null ? AppColors.ink : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
          _field('Client', _clientName, isRequired: true),
          _field('Producer / supplier', _producer),
          _field('Direction number', _number, isRequired: true),
          // A deadline per part: correcting a label and re-grading a
          // consignment are not the same job and are not given the same time.
          if (_quality)
            DateField(
              label: 'Quality - correct by',
              value: _qualityCorrectBy,
              onChanged: (d) {
                setState(() => _qualityCorrectBy = d);
                _scheduleDraft();
              },
              // A correction deadline in the past is meaningless.
              firstDate: DateTime.now().add(const Duration(days: 1)),
              lastDate: DateTime(DateTime.now().year + 2),
              isRequired: true,
              helperText: 'The date by which the grade and size findings must '
                  'be corrected.',
            ),
          if (_labelling)
            DateField(
              label: 'Labelling - correct by',
              value: _labelCorrectBy,
              onChanged: (d) {
                setState(() => _labelCorrectBy = d);
                _scheduleDraft();
              },
              firstDate: DateTime.now().add(const Duration(days: 1)),
              lastDate: DateTime(DateTime.now().year + 2),
              isRequired: true,
              helperText: 'The date by which the marking and packing findings '
                  'must be corrected.',
            ),
          _field(
            'Quantity of product removed',
            _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          for (final part in [
            if (_quality) ('quality', 'QUALITY REMARKS'),
            if (_labelling) ('labelling', 'LABELLING REMARKS'),
          ]) ...[
            _SectionLabel(part.$2),
            for (final r
                in _remarksByType[part.$1] ?? const <EggDirectionRemark>[])
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.brandRed,
                value: _selectedRemarks.contains(r.id),
                title:
                    Text(r.remarkText, style: const TextStyle(fontSize: 13.5)),
                onChanged: (v) {
                  setState(() {
                    if (v ?? false) {
                      _selectedRemarks.add(r.id);
                    } else {
                      _selectedRemarks.remove(r.id);
                    }
                  });
                  _scheduleDraft();
                },
              ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 6),
          _field('Additional remarks', _additional, maxLines: 3),
          const SizedBox(height: 6),
          Text(
            _position == null
                ? 'Location not captured'
                : 'Location: ${_position!.latitude.toStringAsFixed(5)}, '
                    '${_position!.longitude.toStringAsFixed(5)}',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('SAVE DIRECTION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool isRequired = false,
  }) =>
      LabelledField(
        label: label,
        isRequired: isRequired,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15.5),
          // Cheap insurance: typing leaves a recoverable draft behind.
          onChanged: (_) => _scheduleDraft(),
        ),
      );
}

/// A small all-caps heading, matching the rest of the capture forms.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
            color: AppColors.muted,
          ),
        ),
      );
}

/// One part of a direction, on or off.
///
/// Shown ticked but disabled when the inspection's findings decided it: the
/// inspector needs to see what is being served, and must not be able to drop a
/// part the regulations require.
class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.brandRed,
      value: value,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: value ? FontWeight.w700 : FontWeight.w400,
          color: value ? AppColors.ink : AppColors.muted,
        ),
      ),
    );
  }
}
