import 'package:flutter/material.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_repository.dart';
import '../domain/poultry_rules.dart';

/// A captured grading inspection, read back.
///
/// Leads with the deviations rather than the fields, because that is what a
/// direction is written from. Compliant rows are listed after, so the record
/// shows what was checked and not only what failed — an inspection with
/// nothing wrong should not read as an inspection that never happened.
class PoultryInspectionSummaryPage extends StatefulWidget {
  const PoultryInspectionSummaryPage({
    super.key,
    required this.repository,
    required this.inspectionUuid,
  });

  final PoultryRepository repository;
  final String inspectionUuid;

  @override
  State<PoultryInspectionSummaryPage> createState() =>
      _PoultryInspectionSummaryPageState();
}

class _Loaded {
  _Loaded({
    required this.inspection,
    required this.items,
    required this.compliant,
    required this.names,
  });

  final PoultryInspection inspection;
  final List<PoultryChecklistItemRef> items;
  final Set<int> compliant;

  /// Reference id -> display name, for every lookup this page shows.
  final Map<String, String> names;
}

class _PoultryInspectionSummaryPageState
    extends State<PoultryInspectionSummaryPage> {
  late Future<_Loaded?> _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  Future<_Loaded?> _load() async {
    final repo = widget.repository;
    final inspection = await repo.inspectionByUuid(widget.inspectionUuid);
    if (inspection == null) return null;

    final names = <String, String>{};
    void put(String prefix, int? id, List<PoultryDesignationRef> refs) {
      if (id == null) return;
      for (final r in refs) {
        if (r.id == id) names[prefix] = r.name;
      }
    }

    put('location', inspection.locationId, await repo.inspectionLocations());
    put('reason', inspection.reasonId, await repo.inspectionReasons());
    put('portion', inspection.portionTypeId, await repo.portionTypes());
    put('designation', inspection.designationClassId,
        await repo.designationClasses());
    put('altDesignation', inspection.altDesignationClassId,
        await repo.alternativeDesignationClasses());

    for (final m in await repo.meatTypes()) {
      if (m.id == inspection.meatTypeId) names['meatType'] = m.name;
    }
    for (final g in await repo.grades()) {
      if (g.id == inspection.gradeId) names['grade'] = g.name;
    }

    return _Loaded(
      inspection: inspection,
      items: await repo.checklistItems(),
      compliant: {
        for (final part in inspection.compliantItemIds.split(','))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      },
      names: names,
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
      body: FutureBuilder<_Loaded?>(
        future: _loaded,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final loaded = snap.data;
          if (loaded == null) {
            return Center(
              child: Text(
                'That inspection is no longer on this device.',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          }
          return _body(loaded);
        },
      ),
    );
  }

  Widget _body(_Loaded loaded) {
    final i = loaded.inspection;
    final findings = PoultryRules.findings(
      items: loaded.items,
      compliantItemIds: loaded.compliant,
    );
    final compliant = [
      for (final item in loaded.items)
        if (loaded.compliant.contains(item.id)) item,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text(
          i.facilityName.isEmpty ? '(no facility)' : i.facilityName,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
        ),
        const SizedBox(height: 4),
        Text(
          '${i.inspectedAt.toLocal()}'.split('.').first,
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),

        const SizedBox(height: 18),
        _banner(findings.length),

        _section('Deviations'),
        if (findings.isEmpty)
          Text(
            'None. Every row on every list was ticked.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          )
        else
          for (final f in findings)
            _line(f.item.description, f.item.regulationReference, bad: true),

        _section('Product'),
        _kv('Poultry type', loaded.names['meatType']),
        _kv('Portion type', loaded.names['portion']),
        _kv('Class designation', loaded.names['designation']),
        _kv('Alternative designation', loaded.names['altDesignation']),
        _kv('Grade', loaded.names['grade']),
        _kv('Product details', i.productDetails),
        _kv('Sample #', i.sampleNumber),

        _section('Inspection'),
        _kv('Location', loaded.names['location']),
        _kv('Reason', loaded.names['reason']),
        _kv('Facility address', i.facilityAddress),
        _kv('Telephone', i.facilityTelephone),
        _kv('Company reg.', i.companyRegNumber),
        _kv('Contact person', i.contactPerson),
        _kv('Manager', i.managerName),

        if (i.inspectionComments.isNotEmpty ||
            i.directionComments.isNotEmpty ||
            i.directionRemarks.isNotEmpty) ...[
          _section('Remarks'),
          _kv('Inspection', i.inspectionComments),
          _kv('Direction', i.directionComments),
          _kv('Direction remarks', i.directionRemarks),
        ],

        _section('Checked and compliant (${compliant.length})'),
        for (final item in compliant)
          _line(item.description, item.regulationReference, bad: false),
      ],
    );
  }

  Widget _banner(int findings) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: findings == 0
              ? const Color(0xFFEAF5EB)
              : AppColors.noticeBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: findings == 0
                ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                : AppColors.noticeBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              findings == 0 ? Icons.check_circle_outline : Icons.warning_amber,
              color: findings == 0
                  ? const Color(0xFF2E7D32)
                  : AppColors.noticeForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                findings == 0
                    ? 'No deviations recorded.'
                    : '$findings ${findings == 1 ? "deviation" : "deviations"} '
                        'recorded. A direction may need to be served.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: findings == 0
                      ? const Color(0xFF2E7D32)
                      : AppColors.noticeForeground,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
            color: AppColors.ink,
          ),
        ),
      );

  Widget _line(String text, String regulation, {required bool bad}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              bad ? Icons.close : Icons.check,
              size: 16,
              color: bad ? AppColors.brandRed : const Color(0xFF2E7D32),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: const TextStyle(fontSize: 13.5)),
                  if (regulation.isNotEmpty)
                    Text(
                      regulation,
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  /// Omits a field that was never filled in, rather than printing an em dash
  /// for every blank on a form this long.
  Widget _kv(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
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
}
