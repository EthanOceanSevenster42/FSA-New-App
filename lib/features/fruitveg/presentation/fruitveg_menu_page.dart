import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/fruitveg_repository.dart';
import 'fruitveg_inspection_form.dart';
import 'fruitveg_inspection_list_page.dart';

/// Fruit & Vegetable landing page.
///
/// New Inspection / Direction
/// Management / Inspection Management), but shows whether the device actually
/// has the reference data those screens need, rather than letting you open
/// a blank inspection form and only failed once you tried to pick a commodity.
class FruitVegMenuPage extends StatefulWidget {
  const FruitVegMenuPage({
    super.key,
    required this.repository,
    required this.inspectorName,
  });

  final FruitVegRepository repository;
  final String inspectorName;

  @override
  State<FruitVegMenuPage> createState() => _FruitVegMenuPageState();
}

class _FruitVegMenuPageState extends State<FruitVegMenuPage> {
  bool _syncing = false;
  late Future<_MenuState> _state;

  @override
  void initState() {
    super.initState();
    _state = _load();
  }

  Future<_MenuState> _load() async {
    final ready = await widget.repository.hasReferenceData;
    final commodities = await widget.repository.commodities();
    final saved = await widget.repository.savedInspections();
    final pending = await widget.repository.pendingUploadCount();
    return _MenuState(
      hasReference: ready,
      commodityCount: commodities.length,
      savedCount: saved.length,
      pendingCount: pending,
    );
  }

  // Block body, not an arrow: an arrow returns the assigned Future, and
  // setState asserts when its callback returns one.
  void _refresh() => setState(() {
        _state = _load();
      });

  Future<void> _syncReference() async {
    setState(() => _syncing = true);
    String message;
    try {
      final rows = await widget.repository.syncReference(full: true);
      message = 'Reference data updated — $rows records.';
    } on Object catch (e) {
      message = 'Could not reach the server. $e';
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    _refresh();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  Future<void> _newInspection() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FruitVegInspectionForm(
          repository: widget.repository,
          inspectorName: widget.inspectorName,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _openList() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FruitVegInspectionListPage(repository: widget.repository),
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
          'Fruit & Vegetables',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: FutureBuilder<_MenuState>(
        future: _state,
        builder: (context, snap) {
          final s = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              _ReferenceBanner(
                loading: loading,
                hasReference: s?.hasReference ?? false,
                commodityCount: s?.commodityCount ?? 0,
                syncing: _syncing,
                onSync: _syncReference,
              ),
              const SizedBox(height: 20),
              _MenuButton(
                icon: Icons.add_circle_outline,
                title: 'New Inspection',
                subtitle: 'Capture a consignment and grade it',
                enabled: (s?.hasReference ?? false) && !_syncing,
                primary: true,
                onTap: _newInspection,
              ),
              const SizedBox(height: 10),
              _MenuButton(
                icon: Icons.fact_check_outlined,
                title: 'Inspection Management',
                subtitle: s == null
                    ? ''
                    : '${s.savedCount} saved · ${s.pendingCount} awaiting upload',
                enabled: !_syncing,
                onTap: _openList,
              ),
              const SizedBox(height: 10),
              const _MenuButton(
                icon: Icons.gavel_outlined,
                title: 'Direction Management',
                subtitle: 'Directives and seizures',
                enabled: false,
                onTap: null,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuState {
  const _MenuState({
    required this.hasReference,
    required this.commodityCount,
    required this.savedCount,
    required this.pendingCount,
  });

  final bool hasReference;
  final int commodityCount;
  final int savedCount;
  final int pendingCount;
}

class _ReferenceBanner extends StatelessWidget {
  const _ReferenceBanner({
    required this.loading,
    required this.hasReference,
    required this.commodityCount,
    required this.syncing,
    required this.onSync,
  });

  final bool loading;
  final bool hasReference;
  final int commodityCount;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 78,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final ok = hasReference;
    final fg = ok ? const Color(0xFF2E7D32) : AppColors.noticeForeground;
    final bg = ok ? const Color(0xFFEAF5EB) : AppColors.noticeBackground;
    final border = ok ? const Color(0xFFB6DCBA) : AppColors.noticeBorder;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? 'Grading rules ready — $commodityCount commodities'
                      : 'No grading rules on this device',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ok
                ? 'Inspections can be captured and graded offline.'
                : 'Download them once while you have signal. Without them an '
                    'inspection cannot be graded.',
            style: TextStyle(fontSize: 12.5, color: fg, height: 1.3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: syncing ? null : onSync,
              icon: syncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(syncing
                  ? 'Downloading…'
                  : ok
                      ? 'Refresh rules'
                      : 'Download rules'),
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(color: border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? AppColors.ink : AppColors.muted;
    return Material(
      color: enabled && primary ? AppColors.brandRed : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled && primary ? AppColors.brandRed : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: primary && enabled ? Colors.white : fg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: primary && enabled ? Colors.white : fg,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: primary && enabled
                              ? Colors.white70
                              : AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!enabled)
                const Text(
                  'SOON',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: AppColors.brandTeal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
