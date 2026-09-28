import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/poultry_capture_repository.dart';
import '../data/poultry_repository.dart';
import 'poultry_direction_pages.dart';
import 'poultry_inspection_list_page.dart';
import 'poultry_label_checklist_form.dart';
import 'poultry_quid_continue_page.dart';
import 'poultry_quid_setup_form.dart';

/// Poultry landing page.
///
/// Five entries. The original has six: its two poultry record tiles are one
/// here — labelling, with grading to follow when the inspector says so on
/// that form (Ethan, 2026-09-23). Its seventh, "Seizure Management", is
/// `IsVisible="False"` in `PoultryMenuPage.xaml` and its handler says only
/// "This is a future feature" — so it is absent here too rather than shown as
/// something an inspector might wait for.
class PoultryMenuPage extends StatefulWidget {
  const PoultryMenuPage({
    super.key,
    required this.repository,
    required this.captureRepository,
    required this.user,
  });

  final PoultryRepository repository;
  final PoultryCaptureRepository captureRepository;
  final SessionUser user;

  @override
  State<PoultryMenuPage> createState() => _PoultryMenuPageState();
}

class _PoultryMenuPageState extends State<PoultryMenuPage> {
  late Future<int> _rules;

  @override
  void initState() {
    super.initState();
    // The bundled rules load from the asset, so the menu is usable with no
    // signal and no prior sync. A refresh from the server is attempted after,
    // and its failure is not allowed to block the screen.
    _rules = _prepare();
  }

  Future<int> _prepare() async {
    await widget.repository.loadBundledRulesIfEmpty();
    final items = await widget.repository.checklistItems();
    unawaited(
      widget.repository.syncReference().catchError((_) => 0),
    );
    return items.length;
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => page),
    );
    if (mounted) setState(() {});
  }

  Future<void> _newLabelChecklist() => _open(
        PoultryLabelChecklistForm(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          inspectorName: widget.user.userName,
        ),
      );

  Future<void> _setupQuid() => _open(
        PoultryQuidSetupForm(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          inspectorName: widget.user.userName,
        ),
      );

  Future<void> _continueQuid() => _open(
        PoultryQuidContinuePage(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          user: widget.user,
        ),
      );

  Future<void> _directions() => _open(
        PoultryDirectionManagementPage(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          user: widget.user,
        ),
      );

  void _management() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PoultryInspectionListPage(
          repository: widget.repository,
          captureRepository: widget.captureRepository,
          user: widget.user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Poultry',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
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
                )
              else if (!ready)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.noticeBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.noticeBorder),
                  ),
                  child: Text(
                    'This device has no poultry rules yet. Connect once and '
                    'they will be kept for offline use.',
                    style: TextStyle(
                      color: AppColors.noticeForeground,
                      height: 1.35,
                    ),
                  ),
                ),
              // The original's order, top to bottom.
              _Tile(
                title: 'New Labelling and Grading Checklist',
                subtitle: 'Label and container first; grading can follow',
                icon: Icons.label_outline,
                onTap: ready ? _newLabelChecklist : null,
              ),
              _Tile(
                title: 'Setup QUID Checklist',
                subtitle: 'Record what is being sampled, before weighing',
                icon: Icons.science_outlined,
                onTap: ready ? _setupQuid : null,
              ),
              _Tile(
                title: 'Continue with QUID Checklist',
                subtitle: 'Weigh carcasses against a set-up',
                icon: Icons.play_circle_outline,
                onTap: _continueQuid,
              ),
              _Tile(
                title: 'Rejection Management',
                subtitle: 'Issue, review and send rejections',
                icon: Icons.gavel_outlined,
                onTap: _directions,
                accent: AppColors.brandRed,
              ),
              _Tile(
                title: 'Inspection Management',
                subtitle: 'Review, resume and send captured inspections',
                icon: Icons.fact_check_outlined,
                onTap: _management,
              ),
            ],
          );
        },
      )),
    );
  }
}

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
