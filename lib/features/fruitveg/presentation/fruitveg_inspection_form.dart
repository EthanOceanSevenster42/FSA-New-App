import 'dart:async';

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/compliance_slider.dart';
import '../../../core/widgets/missing_fields.dart';
import '../data/fruitveg_repository.dart';
import '../domain/grading_engine.dart';
import '../../../core/widgets/picker_menu_field.dart';

/// Fruit & Vegetable inspection capture.
///
/// Split into steps rather than one long scrolling page,
/// presenting every field at once. Here the same fields are grouped into
/// sequential sections so an inspector on a 360dp screen can work through them,
/// with the computed class shown before they commit.
class FruitVegInspectionForm extends StatefulWidget {
  const FruitVegInspectionForm({
    super.key,
    required this.repository,
    required this.inspectorName,
  });

  final FruitVegRepository repository;
  final String inspectorName;

  @override
  State<FruitVegInspectionForm> createState() => _FruitVegInspectionFormState();
}

class _DefectLine {
  _DefectLine({required this.group});

  final FvDefectGroup group;
  // Set by the defect card as the inspector types.
  FvSubDefect? subDefect;
  int? count;
  double? weightG;
}

class _CapturedPhoto {
  _CapturedPhoto({required this.kind, required this.path});
  final String kind;
  final String path;
}

class _FruitVegInspectionFormState extends State<FruitVegInspectionForm> {
  final _uuid = const Uuid().v4();
  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  /// Whether [_goto] is turning the page, so [_holdPage] leaves it be.
  bool _turning = false;
  bool _holdQueued = false;

  /// The required fields a refused step or save flagged, so the page can
  /// take the inspector to the first and mark each red.
  final _missing = MissingFields();

  // Reference data
  List<FvInspectionPoint> _points = [];
  List<FvCommodityGroup> _groups = [];
  List<FvCommodity> _commodities = [];
  List<FvCultivar> _cultivars = [];
  List<FvCountry> _countries = [];
  List<FvGrade> _grades = [];
  List<FvDefectGroup> _defectGroups = [];
  List<FvRequirement> _marking = [];
  List<FvRequirement> _packing = [];
  bool _loading = true;

  // Selections
  FvInspectionPoint? _point;
  FvCommodityGroup? _group;
  FvCommodity? _commodity;
  FvCultivar? _cultivar;
  FvCountry? _country;
  FvGrade? _markedGrade;
  final _failedRequirements = <int>{};
  final _defects = <_DefectLine>[];
  final _photos = <_CapturedPhoto>[];
  Position? _position;

  // Text fields
  final _clientName = TextEditingController();
  final _clientAddress = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNumber = TextEditingController();
  final _marketPlace = TextEditingController();
  final _description = TextEditingController();
  final _containers = TextEditingController();
  final _barcode = TextEditingController();
  final _grn = TextEditingController();
  final _boe = TextEditingController();
  final _sampleWeight = TextEditingController();
  final _containerWeight = TextEditingController();
  final _sampleUnits = TextEditingController();
  final _brix = TextEditingController();
  final _remarks = TextEditingController();
  final _overrideReason = TextEditingController();

  GradingResult? _result;
  bool _override = false;
  FvGrade? _overrideGrade;

  static const _titles = [
    'Inspection details',
    'Consignment',
    'Sample',
    'Defects',
    'Requirements',
    'Photos',
    'Result',
  ];

  @override
  void initState() {
    super.initState();
    _page.addListener(_holdPage);
    _loadReference();
    unawaited(_captureLocation(silent: true));
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in [
      _clientName,
      _clientAddress,
      _contactPerson,
      _contactNumber,
      _marketPlace,
      _description,
      _containers,
      _barcode,
      _grn,
      _boe,
      _sampleWeight,
      _containerWeight,
      _sampleUnits,
      _brix,
      _remarks,
      _overrideReason,
    ]) {
      c.dispose();
    }
    _missing.dispose();
    super.dispose();
  }

  Future<void> _loadReference() async {
    final r = widget.repository;
    _points = await r.inspectionPoints();
    _groups = await r.commodityGroups();
    _countries = await r.countries();
    _grades = await r.grades();
    _defectGroups = await r.defectGroups();
    _marking = await r.requirements('marking');
    _packing = await r.requirements('packing');
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onGroupChanged(FvCommodityGroup? g) async {
    _group = g;
    _commodity = null;
    _cultivar = null;
    _commodities =
        g == null ? [] : await widget.repository.commodities(groupId: g.id);
    if (mounted) setState(() {});
  }

  Future<void> _onCommodityChanged(FvCommodity? c) async {
    _commodity = c;
    _cultivar = null;
    _cultivars = c == null ? [] : await widget.repository.cultivars(c.id);
    if (mounted) setState(() {});
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));
  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _computeGrade() async {
    final commodity = _commodity;
    if (commodity == null) return;
    final tolerances = await widget.repository.tolerancesFor(commodity.id);
    final measurements = [
      for (final d in _defects)
        DefectMeasurement(
          defectGroupId: d.group.id,
          defectGroupName: d.group.name,
          count: d.count,
          weightG: d.weightG,
        ),
    ];
    final sampleWeightKg = _num(_sampleWeight);
    final result = GradingEngine.grade(
      defects: measurements,
      tolerances: tolerances,
      sampleUnitCount: _int(_sampleUnits),
      sampleWeightG: sampleWeightKg == null ? null : sampleWeightKg * 1000,
    );
    if (mounted) setState(() => _result = result);
  }

  Future<void> _capturePhoto(String kind) async {
    final picker = ImagePicker();
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      // Downscale at capture: a full-resolution bitmap will OOM a 2-4GB handset.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (shot == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final target = '${dir.path}/fv_${_uuid}_${kind}_${_photos.length}.jpg';
    await File(shot.path).copy(target);
    if (mounted) {
      setState(() => _photos.add(_CapturedPhoto(kind: kind, path: target)));
    }
  }

  /// Taken in the background as the form opens. Where the inspector is
  /// standing is not a decision they make, so it is not a button they press.
  Future<void> _captureLocation({bool silent = false}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silent) _toast('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) setState(() => _position = pos);
    } on Object catch (e) {
      if (!silent) _toast('Could not get a location fix. $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  String? _blockingIssue() {
    if (_commodity == null) return 'Select a commodity before saving.';
    if (_point == null) return 'Select an inspection point before saving.';
    if (_override && _overrideReason.text.trim().isEmpty) {
      return 'A reason is required when overriding the class.';
    }
    return null;
  }

  /// The fields marked required (asterisked) that are still empty, in page
  /// order, as ids for [_missing] with the step each sits on and its caption.
  ///
  /// Ids carry their step: the page view can hold two steps built at once.
  List<({int step, String id, String label})> _missingRequired() => [
        if (_point == null)
          (step: 0, id: 'details.point', label: 'Inspection point'),
        if (_group == null)
          (step: 1, id: 'consignment.group', label: 'Commodity group'),
        if (_commodity == null)
          (step: 1, id: 'consignment.commodity', label: 'Commodity'),
        if (_override && _overrideReason.text.trim().isEmpty)
          (step: 6, id: 'result.overrideReason', label: 'Reason for override'),
      ];

  static const _photosId = 'photos.photos';

  bool _stillMissing(String id) => id == _photosId
      ? _photos.isEmpty
      : _missingRequired().any((m) => m.id == id);

  /// Takes the inspector to the step of the first of [missing], and marks
  /// every one of them red.
  Future<void> _flagMissing(
    List<({int step, String id, String label})> missing,
  ) async {
    if (missing.isEmpty) return;
    final step = missing.first.step;
    // The step's list must be on screen for the field to be scrolled to.
    if (step != _step) await _goto(step);
    if (!mounted) return;
    await _missing.flag(
      context,
      [for (final m in missing) m.id],
      stillMissing: _stillMissing,
    );
  }

  /// Wraps a required field so a refused step or save can scroll to it and
  /// mark it.
  Widget _anchor(
    String id,
    Widget child, {
    bool framed = false,
    Listenable? listenable,
  }) =>
      MissingFieldAnchor(
        fields: _missing,
        id: id,
        framed: framed,
        listenable: listenable,
        child: child,
      );

  /// NEXT: refuses to leave a step with an asterisked field still empty.
  Future<void> _next() async {
    final missing =
        _missingRequired().where((m) => m.step == _step).toList();
    if (missing.isNotEmpty) {
      _toast('Fill in ${missing.map((m) => m.label).join(', ')} before '
          'continuing.');
      await _flagMissing(missing);
      return;
    }
    if (_step == 3) await _computeGrade();
    await _goto(_step + 1);
  }

  Future<void> _save() async {
    final issue = _blockingIssue();
    if (issue != null) {
      _toast(issue);
      await _flagMissing(_missingRequired());
      return;
    }
    if (_photos.isEmpty) {
      _toast('Capture at least one inspection photo before saving.');
      await _flagMissing(
          const [(step: 5, id: _photosId, label: 'Inspection photo')]);
      return;
    }
    _missing.clear();
    setState(() => _saving = true);

    final sampleWeightKg = _num(_sampleWeight);
    final now = DateTime.now();
    final determined = _override ? _overrideGrade?.id : _result?.gradeId;

    final inspection = FvInspectionsCompanion.insert(
      clientUuid: _uuid,
      inspectedAt: now,
      commodityId: _commodity!.id,
      updatedAt: now,
      status: const Value('completed'),
      inspectionPointId: Value(_point?.id),
      clientName: Value(_clientName.text.trim()),
      clientAddress: Value(_clientAddress.text.trim()),
      clientContactPerson: Value(_contactPerson.text.trim()),
      clientContactNumber: Value(_contactNumber.text.trim()),
      marketPlace: Value(_marketPlace.text.trim()),
      cultivarId: Value(_cultivar?.id),
      countryId: Value(_country?.id),
      consignmentDescription: Value(_description.text.trim()),
      containerNumbers: Value(_containers.text.trim()),
      barcode: Value(_barcode.text.trim()),
      grnVoucher: Value(_grn.text.trim()),
      billOfEntry: Value(_boe.text.trim()),
      sampleWeightKg: Value(sampleWeightKg),
      markedContainerWeightKg: Value(_num(_containerWeight)),
      markedGradeId: Value(_markedGrade?.id),
      brixReading: Value(_num(_brix)),
      determinedGradeId: Value(determined),
      gradeOverridden: Value(_override),
      overrideReason: Value(_overrideReason.text.trim()),
      remarks: Value(_remarks.text.trim()),
      latitude: Value(_position?.latitude),
      longitude: Value(_position?.longitude),
      failedRequirementIds: Value(_failedRequirements.join(',')),
    );

    final defects = [
      for (final d in _defects)
        FvInspectionDefectsCompanion.insert(
          inspectionUuid: _uuid,
          defectGroupId: d.group.id,
          subDefectId: Value(d.subDefect?.id),
          count: Value(d.count),
          weightG: Value(d.weightG),
          percentage: Value(_result?.percentages[d.group.id]),
        ),
    ];

    try {
      await widget.repository.saveInspection(inspection, defects);
      for (final p in _photos) {
        await widget.repository.addPhoto(
          FvInspectionPhotosCompanion.insert(
            inspectionUuid: _uuid,
            kind: p.kind,
            filePath: p.path,
            capturedAt: now,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Inspection saved on this device.');
    } on Object catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast('Could not save. $e');
    }
  }

  Future<void> _goto(int step) async {
    setState(() => _step = step);
    _turning = true;
    try {
      await _page.animateToPage(
        step,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      _turning = false;
    }
  }

  /// Keeps the wizard square on its step. Scrolling a flagged field into
  /// view scrolls every list it sits in, the page view included, which
  /// would otherwise leave the step nudged a few pixels sideways. Put back
  /// in a microtask, before the frame is laid out, rather than from inside
  /// the scroll animation's own tick.
  void _holdPage() {
    if (_turning || _holdQueued) return;
    _holdQueued = true;
    scheduleMicrotask(() {
      _holdQueued = false;
      if (_turning || !mounted || !_page.hasClients) return;
      final p = _page.position;
      if (!p.hasViewportDimension) return;
      final settled = _step * p.viewportDimension;
      if ((p.pixels - settled).abs() > 0.5) p.jumpTo(settled);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body:
              ContentWidth(child: Center(child: CircularProgressIndicator())));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titles[_step],
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            Text(
              'Step ${_step + 1} of ${_titles.length}',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
      body: ContentWidth(
          child: Column(
        children: [
          LinearProgressIndicator(
            value: (_step + 1) / _titles.length,
            backgroundColor: AppColors.surfaceAlt,
            color: AppColors.brandPrimary,
            minHeight: 3,
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _detailsStep(),
                _consignmentStep(),
                _sampleStep(),
                _defectsStep(),
                _requirementsStep(),
                _photosStep(),
                _resultStep(),
              ],
            ),
          ),
          _navBar(),
        ],
      )),
    );
  }

  Widget _navBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => unawaited(_goto(_step - 1)),
                      child: const Text('Back'),
                    ),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            if (_step == _titles.length - 1) {
                              await _save();
                            } else {
                              await _next();
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(_step == _titles.length - 1
                            ? 'SAVE INSPECTION'
                            : 'NEXT'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // --- Steps --------------------------------------------------------------

  Widget _pad(List<Widget> children) => ListView(
        // Clear the system navigation bar: the save button is the last
        // thing on the page, and the bar was drawing over it and taking
        // the tap.
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: children,
      );

  Widget _detailsStep() => _pad([
        _anchor('details.point', _DropdownField<FvInspectionPoint>(
          label: 'Inspection point *',
          value: _point,
          items: _points,
          itemLabel: (p) => p.name,
          onChanged: (p) => setState(() => _point = p),
        )),
        _TextField(label: 'Client name', controller: _clientName),
        _TextField(label: 'Client address', controller: _clientAddress),
        _TextField(label: 'Contact person', controller: _contactPerson),
        _TextField(
          label: 'Contact number',
          controller: _contactNumber,
          keyboardType: TextInputType.phone,
        ),
        _TextField(label: 'Market place', controller: _marketPlace),
      ]);

  Widget _consignmentStep() => _pad([
        _anchor('consignment.group', _DropdownField<FvCommodityGroup>(
          label: 'Commodity group *',
          value: _group,
          items: _groups,
          itemLabel: (g) => g.name,
          onChanged: _onGroupChanged,
        )),
        _anchor('consignment.commodity', _DropdownField<FvCommodity>(
          label: 'Commodity *',
          value: _commodity,
          items: _commodities,
          itemLabel: (c) => c.name,
          onChanged: _onCommodityChanged,
          hint: _group == null ? 'Select a commodity group first' : null,
        )),
        _DropdownField<FvCultivar>(
          label: 'Cultivar / variety',
          value: _cultivar,
          items: _cultivars,
          itemLabel: (c) => c.name,
          onChanged: (c) => setState(() => _cultivar = c),
          hint: _commodity == null ? 'Select a commodity first' : null,
        ),
        _DropdownField<FvCountry>(
          label: 'Country of origin',
          value: _country,
          items: _countries,
          itemLabel: (c) => c.name,
          onChanged: (c) => setState(() => _country = c),
        ),
        _TextField(label: 'Consignment description', controller: _description),
        _TextField(label: 'Container number(s)', controller: _containers),
        _TextField(label: 'Barcode', controller: _barcode),
        _TextField(label: 'GRN voucher', controller: _grn),
        _TextField(label: 'Bill of entry', controller: _boe),
      ]);

  Widget _sampleStep() => _pad([
        _TextField(
          label: 'Sample weight (kg)',
          controller: _sampleWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          helper: 'Used to convert weighed defects into a percentage.',
        ),
        _TextField(
          label: 'Sample unit count',
          controller: _sampleUnits,
          keyboardType: TextInputType.number,
          helper: 'Used to convert counted defects into a percentage.',
        ),
        _TextField(
          label: 'Marked container weight (kg)',
          controller: _containerWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        _DropdownField<FvGrade>(
          label: 'Marked class (on the packaging)',
          value: _markedGrade,
          items: _grades,
          itemLabel: (g) => g.name,
          onChanged: (g) => setState(() => _markedGrade = g),
        ),
        if (_commodity?.requiresBrix ?? false)
          _TextField(
            label: 'Brix reading (TSS %)',
            controller: _brix,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
      ]);

  Widget _defectsStep() => _pad([
        if (_defects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No defects recorded. A sample with no defects grades at the '
              'best available class.',
              style: TextStyle(color: AppColors.muted, height: 1.35),
            ),
          ),
        for (var i = 0; i < _defects.length; i++) _defectCard(i),
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _addDefect,
            icon: const Icon(Icons.add),
            label: const Text('Add defect'),
          ),
        ),
      ]);

  Widget _defectCard(int index) {
    final d = _defects[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
                  d.group.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _defects.removeAt(index)),
                icon:
                    const Icon(Icons.delete_outline, color: AppColors.brandPrimary),
              ),
            ],
          ),
          Text(
            d.group.isInternal
                ? 'Internal defect — measured by weight'
                : 'External defect — measured by count',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          if (d.group.isInternal)
            TextFormField(
              initialValue: d.weightG?.toString() ?? '',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (g)'),
              onChanged: (v) => d.weightG = double.tryParse(v.trim()),
            )
          else
            TextFormField(
              initialValue: d.count?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Count'),
              onChanged: (v) => d.count = int.tryParse(v.trim()),
            ),
        ],
      ),
    );
  }

  Future<void> _addDefect() async {
    final chosen = await showModalBottomSheet<FvDefectGroup>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select a defect group',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            for (final g in _defectGroups)
              ListTile(
                title: Text(g.name),
                subtitle: Text(g.isInternal ? 'By weight' : 'By count'),
                onTap: () => Navigator.of(context).pop(g),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() => _defects.add(_DefectLine(group: chosen)));
    }
  }

  Widget _requirementsStep() => _pad([
        Text(
          'Tick anything the consignment FAILS.',
          style: TextStyle(color: AppColors.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _requirementSection('Marking / labelling', _marking),
        const SizedBox(height: 18),
        _requirementSection('Packing', _packing),
      ]);

  Widget _requirementSection(String title, List<FvRequirement> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ComplianceSlider(
                    compliant: !_failedRequirements.contains(r.id),
                    onChanged: (isCompliant) => setState(() {
                      if (isCompliant) {
                        _failedRequirements.remove(r.id);
                      } else {
                        _failedRequirements.add(r.id);
                      }
                    }),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _photosStep() => _pad([
        // Any one photo lets the inspection save, so the rows are marked
        // together.
        _anchor(_photosId, framed: true, Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in const [
              ('grn', 'GRN / delivery note'),
              ('label', 'Business end (packaging) label'),
              ('defect', 'Defect photo'),
            ])
              _photoRow(entry.$1, entry.$2),
          ],
        )),
        Divider(height: 28, color: AppColors.border),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.my_location, color: AppColors.brandTeal),
          title: const Text(
            'GPS location',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _position == null
                ? 'Waiting for a fix — the inspection saves without one'
                : '${_position!.latitude.toStringAsFixed(5)}, '
                    '${_position!.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: Icon(
            _position == null ? Icons.location_disabled : Icons.check_circle,
            color: _position == null ? AppColors.muted : AppColors.brandTeal,
          ),
        ),
      ]);

  Widget _photoRow(String kind, String label) {
    final shots = _photos.where((p) => p.kind == kind).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _capturePhoto(kind),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Capture'),
              ),
            ],
          ),
          if (shots.isEmpty)
            Text(
              'None captured',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            )
          else
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(shots[i].path),
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    cacheWidth: 252,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultStep() {
    final r = _result;
    return _pad([
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DETERMINED CLASS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              r?.gradeName ?? 'Not calculated',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: r?.isDetermined ?? false
                    ? AppColors.ink
                    : AppColors.noticeForeground,
              ),
            ),
            if (_markedGrade != null) ...[
              const SizedBox(height: 6),
              Text(
                'Marked on packaging: ${_markedGrade!.name}',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (r != null && r.reasons.isNotEmpty) ...[
        Text(
          'HOW THIS WAS DETERMINED',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        for (final reason in r.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${reason.defectGroupName}: '
              '${reason.percentage.toStringAsFixed(2)}% → ${reason.gradeName}'
              '${reason.toleranceApplied == null ? '' : ' (limit ${reason.toleranceApplied!.toStringAsFixed(2)}%)'}',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        const SizedBox(height: 18),
      ],
      YesNoQuestion(
        label: 'Override the determined class',
        bold: true,
        helper: 'Requires a reason, and is recorded against your name.',
        value: _override,
        onChanged: (v) => setState(() => _override = v),
      ),
      if (_override) ...[
        _DropdownField<FvGrade>(
          label: 'Override class',
          value: _overrideGrade,
          items: _grades,
          itemLabel: (g) => g.name,
          onChanged: (g) => setState(() => _overrideGrade = g),
        ),
        _anchor(
          'result.overrideReason',
          listenable: _overrideReason,
          _TextField(
            label: 'Reason for override *',
            controller: _overrideReason,
            maxLines: 2,
          ),
        ),
      ],
      _TextField(
          label: 'Conditions / remarks', controller: _remarks, maxLines: 3),
      const SizedBox(height: 8),
      Text(
        'Inspector: ${widget.inspectorName}',
        style: TextStyle(fontSize: 12.5, color: AppColors.muted),
      ),
    ]);
  }
}

// --- Small form widgets ----------------------------------------------------

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? helper;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15.5),
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            // Red while a refused step or save has flagged it.
            errorText: MissingFieldScope.errorOf(context),
          ),
        ),
      );
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => PickerMenuField<T>(
        label: label,
        value: value,
        options: [
          for (final item in items) (value: item, text: itemLabel(item)),
        ],
        onChanged: onChanged,
        hint: hint,
      );
}
