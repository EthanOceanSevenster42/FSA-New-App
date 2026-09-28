import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/responsive.dart';

import '../../../core/data/local_database.dart';
import '../../../core/services/photo_storage.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../data/eggs_repository.dart';
import '../data/eggs_sync_service.dart';
import 'egg_direction_form.dart';
import 'egg_direction_list_page.dart';
import 'egg_inspection_form.dart';
import 'egg_inspection_list_page.dart';

/// Poultry Egg landing page.
///
/// New Inspection / Direction / Inspection
/// Management) but states up front whether the device holds the reference data
/// those screens need, rather than letting you open a blank form and only
/// failing once you reach a picker.
class EggsMenuPage extends StatefulWidget {
  const EggsMenuPage({
    super.key,
    required this.repository,
    required this.user,
    this.syncService,
  });

  final EggsRepository repository;
  final SessionUser user;
  final EggsSyncService? syncService;

  @override
  State<EggsMenuPage> createState() => _EggsMenuPageState();
}

class _EggsMenuPageState extends State<EggsMenuPage> {
  late Future<_MenuState> _state;

  String? _syncError;

  @override
  void initState() {
    super.initState();
    // Local reads only — the menu is usable the moment it is built.
    _state = _load();
    unawaited(_downloadInBackground());
  }

  /// Fetches this inspector's own records in the background.
  ///
  /// Deliberately not awaited before the menu is shown. The rules ship inside
  /// the app and every count here comes from the local database, so there is
  /// nothing on this screen that needs the network. Waiting for a download
  /// left New Inspection disabled for as long as the round-trip took — which
  /// on a poor signal is a long time to stare at a button you cannot press.
  ///
  /// Best-effort: offline is the normal case, and a failure leaves the local
  /// records untouched.
  Future<void> _downloadInBackground() async {
    final token = await widget.repository.storedToken();
    if (token == null) return;
    try {
      await widget.repository.downloadMine(token: token);
    } on Object {
      return; // Nothing to tell the user; their own records are still intact.
    }
    // Counts may have changed, so redraw them.
    if (mounted) _refresh();
  }

  Future<_MenuState> _load() async => _MenuState(
        drafts: await widget.repository.drafts(),
        directionDrafts: await widget.repository.directionDrafts(),
        hasReference: await widget.repository.hasReferenceData,
        sizeCount: (await widget.repository.sizeBands()).length,
        deviationCount: (await widget.repository.deviationRefs()).length,
        savedCount: (await widget.repository.savedInspections()).length,
        pendingCount: await widget.repository.pendingUploadCount(),
        directionCount: (await widget.repository.savedDirections()).length,
        pendingDirections: await widget.repository.pendingDirectionCount(),
      );

  Future<void> _openDirections() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggDirectionListPage(
          repository: widget.repository,
          user: widget.user,
          syncService: widget.syncService,
        ),
      ),
    );
    _refresh();
  }

  // Block body, not an arrow: an arrow returns the assigned Future, and
  // setState asserts when its callback returns one.
  void _refresh() => setState(() {
        _state = _load();
      });

  /// Fetches reference data without interrupting the user. Failure is recorded
  /// and surfaced in the banner rather than thrown as a dialog — offline is a
  /// normal state here.
  Future<void> _syncQuietly() async {
    try {
      await widget.repository.syncReference(full: true);
      _syncError = null;
    } on Object catch (e) {
      _syncError = e.toString();
    }
  }

  /// Retry from the problem banner. Only reachable if the bundled rules are
  /// somehow missing, which should not happen.
  Future<void> _sync() async {
    await _syncQuietly();
    if (mounted) _refresh();
  }

  Future<void> _resume(EggInspection draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggInspectionForm(
          repository: widget.repository,
          inspectorName: widget.user.userName,
          syncService: widget.syncService,
          resumeUuid: draft.clientUuid,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _resumeDirection(EggDirection draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggDirectionForm(
          repository: widget.repository,
          inspectorName: widget.user.userName,
          syncService: widget.syncService,
          resumeUuid: draft.clientUuid,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _discardDirectionDrafts(List<EggDirection> drafts) async {
    final many = drafts.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(many
            ? 'Discard ${drafts.length} unfinished rejections?'
            : 'Discard the unfinished rejection?'),
        content: Text(
          many
              ? 'All ${drafts.length} unfinished rejections on this device '
                  'will be deleted. This cannot be undone.'
              : 'Everything entered so far will be deleted. This cannot be '
                  'undone.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = await widget.repository.deleteAllDirectionDrafts();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(removed == 1
              ? 'Unfinished rejection discarded.'
              : '$removed unfinished rejections discarded.'),
          backgroundColor: AppColors.ink,
        ),
      );
  }

  /// "Acacia Farm Fresh · started 02/08 at 14:30 — most recent of 3"
  static String _draftSubtitle(
    String clientName,
    String facilityName,
    DateTime updatedAt,
    int count,
  ) {
    final at = updatedAt.toLocal();
    final when = '${at.day.toString().padLeft(2, '0')}/'
        '${at.month.toString().padLeft(2, '0')} at '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final who =
        clientName.trim().isEmpty ? facilityName.trim() : clientName.trim();
    return [
      who.isEmpty ? 'Started $when' : '$who · started $when',
      if (count > 1) 'most recent of $count',
    ].join(' — ');
  }

  Future<void> _discardDrafts(List<EggInspection> drafts) async {
    final many = drafts.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(many
            ? 'Discard ${drafts.length} unfinished inspections?'
            : 'Discard the unfinished inspection?'),
        content: Text(
          many
              // Said plainly, because discarding one at a time and watching the
              // banner reappear is what made this look broken.
              ? 'All ${drafts.length} unfinished inspections on this device '
                  'will be deleted, including any photographs. This cannot be '
                  'undone.'
              : 'Everything captured so far, including any photographs, will '
                  'be deleted. This cannot be undone.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Remove the photographs from disk as well; the repository owns rows, not
    // files.
    final storage = await PhotoStorage.instance();
    for (final draft in drafts) {
      for (final photo in await widget.repository.photosFor(draft.clientUuid)) {
        await storage.delete(photo.filePath);
      }
    }
    final removed = await widget.repository.deleteAllDrafts();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(removed == 1
              ? 'Unfinished inspection discarded.'
              : '$removed unfinished inspections discarded.'),
          backgroundColor: AppColors.ink,
        ),
      );
  }

  Future<void> _newInspection() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggInspectionForm(
          repository: widget.repository,
          inspectorName: widget.user.userName,
          syncService: widget.syncService,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _openList() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EggInspectionListPage(
          repository: widget.repository,
          user: widget.user,
          syncService: widget.syncService,
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title:
            const Text('Eggs', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
          child: FutureBuilder<_MenuState>(
        future: _state,
        builder: (context, snap) {
          final s = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              // The rules ship with the app, so capture is available from the
              // first launch. A banner only appears if they are somehow
              // missing, which should not happen.
              if (!loading && !(s?.hasReference ?? true)) ...[
                _ProblemBanner(error: _syncError, onRetry: _sync),
                const SizedBox(height: 20),
              ],
              if (s != null && s.drafts.isNotEmpty) ...[
                _ResumeBanner(
                  title: s.drafts.length == 1
                      ? 'Unfinished inspection'
                      : '${s.drafts.length} unfinished inspections',
                  subtitle: _draftSubtitle(
                    s.drafts.first.clientName,
                    s.drafts.first.facilityName,
                    s.drafts.first.updatedAt,
                    s.drafts.length,
                  ),
                  onResume: () => _resume(s.drafts.first),
                  // Removing captured work is the office's call; an
                  // inspector resumes the draft instead.
                  onDiscard: widget.user.canRemoveRecords
                      ? () => _discardDrafts(s.drafts)
                      : null,
                ),
                const SizedBox(height: 14),
              ],
              if (s != null && s.directionDrafts.isNotEmpty) ...[
                _ResumeBanner(
                  title: s.directionDrafts.length == 1
                      ? 'Unfinished rejection'
                      : '${s.directionDrafts.length} unfinished rejections',
                  subtitle: _draftSubtitle(
                    s.directionDrafts.first.clientName,
                    '',
                    s.directionDrafts.first.updatedAt,
                    s.directionDrafts.length,
                  ),
                  onResume: () => _resumeDirection(s.directionDrafts.first),
                  onDiscard: () => _discardDirectionDrafts(s.directionDrafts),
                ),
                const SizedBox(height: 14),
              ],
              // Every destination here is built and works offline, so none
              // of them is gated on a load. Only the counts in the subtitles
              // wait for the database, and they are cosmetic.
              _MenuButton(
                icon: Icons.add_circle_outline,
                title: 'New Inspection',
                subtitle: 'Weigh, size and grade a sample of eggs',
                primary: true,
                onTap: _newInspection,
              ),
              const SizedBox(height: 10),
              _MenuButton(
                icon: Icons.fact_check_outlined,
                title: 'Inspection Management',
                subtitle: s == null
                    ? 'Review and send captured inspections'
                    : '${s.savedCount} saved · ${s.pendingCount} awaiting upload',
                onTap: _openList,
              ),
              const SizedBox(height: 10),
              _MenuButton(
                icon: Icons.gavel_outlined,
                title: 'Rejection Management',
                subtitle: s == null
                    ? 'Quality and labelling rejections'
                    : '${s.directionCount} issued · '
                        '${s.pendingDirections} awaiting upload',
                onTap: _openDirections,
                accent: AppColors.brandRed,
              ),
            ],
          );
        },
      )),
    );
  }
}

class _MenuState {
  const _MenuState({
    this.drafts = const [],
    this.directionDrafts = const [],
    required this.hasReference,
    required this.sizeCount,
    required this.deviationCount,
    required this.savedCount,
    required this.pendingCount,
    required this.directionCount,
    required this.pendingDirections,
  });

  /// Inspections left unfinished, newest first.
  ///
  /// Plural on purpose: a draft is written on every step change, so each
  /// abandoned attempt leaves one behind. Showing only the newest made
  /// discarding look broken — the banner came straight back with the next.
  final List<EggInspection> drafts;

  /// Directions left unfinished, newest first.
  final List<EggDirection> directionDrafts;

  final bool hasReference;
  final int sizeCount;
  final int deviationCount;
  final int savedCount;
  final int pendingCount;
  final int directionCount;
  final int pendingDirections;
}

/// Shown only when the rules could not be fetched and none are stored.
class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.noticeBackground,
          border: Border.all(color: AppColors.noticeBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    size: 20, color: AppColors.noticeForeground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Egg rules unavailable',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.noticeForeground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'The device could not reach the server, so eggs cannot be '
              'sized or graded yet. Connect once and this will resolve itself.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.noticeForeground,
                height: 1.3,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.noticeForeground,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.noticeForeground,
                  side: BorderSide(color: AppColors.noticeBorder),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Offers back an inspection that was interrupted mid-capture.
///
/// Android reclaims memory by killing whatever is in the background, and the
/// camera is the hungriest thing an inspector opens — so being killed partway
/// through is routine on a small handset, not an edge case. Without this the
/// eggs already weighed were simply gone.
class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({
    required this.title,
    required this.subtitle,
    required this.onResume,
    required this.onDiscard,
  });

  /// Serves inspections and directions alike: both are half-captured work the
  /// inspector should be able to pick back up or throw away.
  final String title;
  final String subtitle;
  final VoidCallback onResume;

  /// Null when the signed-in role may not remove work: the button is shown
  /// but dead, so an inspector can see the action exists and who has it.
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.noticeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.noticeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 20, color: AppColors.noticeForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unfinished inspection',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.noticeForeground,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Resume'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A destination on the egg menu.
///
/// There is no disabled state and no "SOON" badge. Everything reachable from
/// here is built and works offline, and a badge reading "SOON" on a feature
/// that merely had not finished loading told the inspector it was not
/// available at all.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  /// Overrides the icon's colour on an ordinary tile. Rejections carry the
  /// app's red, as every other rejection screen does.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.brandPrimary : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: primary ? AppColors.brandPrimary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 26,
                  color: primary ? Colors.white : (accent ?? AppColors.ink)),
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
                        color: primary ? Colors.white : AppColors.ink,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: primary ? Colors.white70 : AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
