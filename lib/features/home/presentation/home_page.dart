import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/session/session_user.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../domain/app_feature.dart';
import '../domain/home_summary.dart';

/// Post-login home.
///
/// The drawer holds every destination, and the screen itself answers
/// "where do I stand?" before "where do I go?" — an inspector opening it
/// should learn something about their own work.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.userName,
    required this.roleName,
    required this.appVersion,
    required this.connectivity,
    required this.onSignOut,
    this.themeController,
    required this.loadSummary,
    required this.openFeature,
    this.checkForUpdates,
    this.downloadUpdates,
  });

  final String userName;
  final String roleName;
  final String appVersion;

  /// Live connectivity, not a snapshot. The first version passed a bool
  /// captured at login, so the pill said "Online" for the rest of the session
  /// however far into the veld the inspector drove.
  final ConnectivityService connectivity;
  final VoidCallback onSignOut;

  /// Light / dark preference, offered in the drawer.
  final ThemeController? themeController;
  final Future<HomeSummary> Function() loadSummary;

  /// Asks the server what reference data has changed since the last sync,
  /// as a short human-readable line. Null means "do not offer updates" — the
  /// prompt then never appears.
  final Future<String?> Function()? checkForUpdates;

  /// Downloads whatever [checkForUpdates] reported, returning how many rows
  /// were written.
  final Future<int> Function()? downloadUpdates;

  /// Returns a route for a built feature, or null if it is not built yet.
  /// Injected so the home screen has no dependency on any feature module.
  /// Takes the signed-in user so a feature can show only what that role may
  /// act on, without reaching for a global.
  final Widget? Function(AppFeature, SessionUser) openFeature;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<HomeSummary> _summary;
  final _isOnline = ValueNotifier<bool>(true);
  StreamSubscription<bool>? _connectivitySub;

  /// Set when the server holds records this device does not. Null while the
  /// answer is unknown, which is also how it stays when offline.
  String? _updateSummary;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.loadSummary();
    unawaited(_watchConnectivity());
    unawaited(_checkForUpdates());
  }

  /// Best-effort. Being unable to reach the server is normal here and must not
  /// produce an error the inspector has to dismiss.
  Future<void> _checkForUpdates() async {
    final check = widget.checkForUpdates;
    if (check == null) return;
    try {
      final summary = await check();
      if (mounted) setState(() => _updateSummary = summary);
    } on Object {
      if (mounted) setState(() => _updateSummary = null);
    }
  }

  Future<void> _downloadUpdates() async {
    final download = widget.downloadUpdates;
    if (download == null) return;
    setState(() => _downloading = true);
    try {
      final written = await download();
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _updateSummary = null;
      });
      _toast(
        written == 0
            ? 'Already up to date.'
            : 'Downloaded $written record${written == 1 ? '' : 's'}. '
                'They are on this device now.',
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _toast('Could not download. You can carry on working. $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.ink),
      );
  }

  Future<void> _watchConnectivity() async {
    _isOnline.value = await widget.connectivity.isOnline;
    _connectivitySub = widget.connectivity.onStatusChanged
        .listen((v) => _isOnline.value = v);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _isOnline.dispose();
    super.dispose();
  }

  bool get _isAdmin =>
      widget.roleName.toLowerCase().contains('admin') ||
      widget.roleName.toLowerCase().contains('supervisor');

  List<AppFeature> _visible(FeatureGroup group) => kAppFeatures
      .where((f) => f.group == group)
      .where((f) => !f.requiresAdmin || _isAdmin)
      .toList();

  Future<void> _open(AppFeature feature) async {
    // Close the drawer through the Scaffold, never through the Navigator.
    //
    // A drawer is not a route. This used to pop when `canPop()` was true —
    // which it always is, because this screen sits on top of the sign-in page.
    // So every tile tap popped the home screen: a "coming soon" tile dropped
    // the inspector onto the sign-in page, and a real one opened the feature
    // with home already gone from the stack, so backing out landed there too.
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();

    final page = widget.openFeature(
      feature,
      SessionUser(userName: widget.userName, roleName: widget.roleName),
    );
    if (page == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${feature.title} is not built yet.'),
            backgroundColor: AppColors.ink,
          ),
        );
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    // Counts may have changed while the feature was open.
    if (mounted) setState(() => _summary = widget.loadSummary());
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Follows the theme. Hardcoding dark icons left them invisible against a
      // dark navigation bar the moment dark mode existed.
      value: (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.surface,
        drawer: _Sidebar(
          userName: widget.userName,
          roleName: widget.roleName,
          appVersion: widget.appVersion,
          inspections: _visible(FeatureGroup.inspections),
          tools: _visible(FeatureGroup.tools),
          onSelect: _open,
          onSignOut: widget.onSignOut,
          themeController: widget.themeController,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                userName: widget.userName,
                roleName: widget.roleName,
                isOnline: _isOnline,
                onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.brandRed,
                  onRefresh: () async {
                    setState(() => _summary = widget.loadSummary());
                    await _summary;
                    await _checkForUpdates();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                    children: [
                      if (_updateSummary != null) ...[
                        _UpdatePrompt(
                          summary: _updateSummary!,
                          busy: _downloading,
                          onDownload: _downloadUpdates,
                        ),
                        const SizedBox(height: 20),
                      ],
                      const _SectionLabel('At a glance'),
                      const SizedBox(height: 12),
                      FutureBuilder<HomeSummary>(
                        future: _summary,
                        builder: (context, snap) => _SummaryGrid(
                          summary: snap.data,
                          loading:
                              snap.connectionState == ConnectionState.waiting,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const _SectionLabel('Start an inspection'),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        // Tuned against a 360dp viewport (the A06 baseline).
                        childAspectRatio: 1.45,
                        children: [
                          for (final f in _visible(FeatureGroup.inspections))
                            _CommodityTile(feature: f, onTap: () => _open(f)),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(Icons.menu, size: 18),
                          label: const Text('All tools and settings'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Offers newly-published clients and premises without interrupting anyone.
///
/// Downloading is the inspector's choice: they may be on a metered connection,
/// and everything they need to keep working is already on the device.
class _UpdatePrompt extends StatelessWidget {
  const _UpdatePrompt({
    required this.summary,
    required this.busy,
    required this.onDownload,
  });

  final String summary;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.brandTeal.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brandTeal.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_download_outlined,
                    size: 20, color: AppColors.brandTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New records available',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onDownload,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text(busy ? 'Downloading…' : 'Sync to this device'),
              ),
            ),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.userName,
    required this.roleName,
    required this.isOnline,
    required this.onMenu,
  });

  final String userName;
  final String roleName;
  final ValueListenable<bool> isOnline;
  final VoidCallback onMenu;

  String get _initials {
    final parts = userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onMenu,
                tooltip: 'Menu',
                icon: Icon(Icons.menu, color: AppColors.ink, size: 26),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: isOnline,
                builder: (context, online, _) =>
                    _StatusPill(isOffline: !online),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brandRed,
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $userName',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandTeal,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isOffline});

  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    // Amber and green both meet AA on this tint, so the state is readable
    // without relying on colour alone — the label says it too.
    final colour =
        isOffline ? const Color(0xFF8A5A00) : const Color(0xFF2E7D32);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            isOffline ? 'Offline' : 'Online',
            style: TextStyle(
              color: colour,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.loading});

  final HomeSummary? summary;
  final bool loading;

  static String _ago(DateTime? when) {
    if (when == null) return 'Never';
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _StatCard(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Inspections today',
          value: loading ? '' : '${s?.inspectionsToday ?? 0}',
          hint: 'captured today',
          accent: AppColors.brandRed,
        ),
        _StatCard(
          icon: Icons.cloud_upload_outlined,
          label: 'Pending upload',
          value: loading ? '' : '${s?.pendingUpload ?? 0}',
          hint: (s?.pendingUpload ?? 0) == 0
              ? 'everything is sent'
              : 'waiting to send',
          accent: AppColors.brandRed,
        ),
        _StatCard(
          icon: Icons.people_alt_outlined,
          label: 'Offline sign-in',
          value: loading ? '' : '${s?.offlineUsers ?? 0}',
          hint: 'users on this device',
          accent: AppColors.brandTeal,
        ),
        _StatCard(
          icon: Icons.sync_outlined,
          label: 'Last sync',
          value: loading ? '' : _ago(s?.lastSyncAt),
          hint: s?.hasSynced == true ? 'users up to date' : 'tap Sync users',
          accent: AppColors.brandTeal,
          compact: true,
        ),
      ],
    );
  }

}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.accent,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 18 : 26,
              fontWeight: FontWeight.w900,
              height: 1.1,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 4, height: 18, color: AppColors.brandRed),
          const SizedBox(width: 10),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: AppColors.ink,
            ),
          ),
        ],
      );
}

class _CommodityTile extends StatelessWidget {
  const _CommodityTile({required this.feature, required this.onTap});

  final AppFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = feature.available;
    return Material(
      color: enabled ? AppColors.surface : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                feature.icon,
                size: 24,
                color: enabled
                    ? AppColors.brandRed
                    : AppColors.brandRed.withValues(alpha: 0.45),
              ),
              const Spacer(),
              Text(
                feature.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  color: enabled ? AppColors.ink : AppColors.muted,
                ),
              ),
              if (!enabled) ...[
                const SizedBox(height: 3),
                const Text(
                  'COMING SOON',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: AppColors.brandTeal,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Drawer holding every destination in the app.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.userName,
    required this.roleName,
    required this.appVersion,
    required this.inspections,
    required this.tools,
    required this.onSelect,
    required this.onSignOut,
    this.themeController,
  });

  final String userName;
  final String roleName;
  final String appVersion;
  final List<AppFeature> inspections;
  final List<AppFeature> tools;
  final void Function(AppFeature) onSelect;
  final VoidCallback onSignOut;
  final ThemeController? themeController;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandRed,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      userName.isEmpty
                          ? '?'
                          : userName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          roleName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.brandTeal,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const _DrawerHeading('Inspections'),
                  for (final f in inspections)
                    _DrawerItem(feature: f, onTap: () => onSelect(f)),
                  Divider(height: 18, color: AppColors.border),
                  const _DrawerHeading('Tools'),
                  for (final f in tools)
                    _DrawerItem(feature: f, onTap: () => onSelect(f)),
                ],
              ),
            ),
            if (themeController != null) ...[
              Divider(height: 1, color: AppColors.border),
              _AppearanceTile(controller: themeController!),
            ],
            Divider(height: 1, color: AppColors.border),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.brandRed),
              title: const Text(
                'Sign out',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandRed,
                ),
              ),
              onTap: onSignOut,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Version $appVersion',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeading extends StatelessWidget {
  const _DrawerHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: AppColors.muted,
          ),
        ),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.feature, required this.onTap});

  final AppFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = feature.available;
    return ListTile(
      dense: true,
      leading: Icon(
        feature.icon,
        size: 22,
        color: enabled
            ? AppColors.ink
            : AppColors.muted.withValues(alpha: 0.7),
      ),
      title: Text(
        feature.title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: enabled ? AppColors.ink : AppColors.muted,
        ),
      ),
      trailing: enabled
          ? null
          : const Text(
              'SOON',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: AppColors.brandTeal,
              ),
            ),
      onTap: onTap,
    );
  }
}

/// Light, dark, or whatever the phone is set to.
///
/// Inspectors work in cold rooms and packhouses at six in the morning and in
/// direct sun at midday; neither setting suits both. The choice is remembered
/// on the handset.
class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile({required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : mode == ThemeMode.light
                          ? Icons.light_mode_outlined
                          : Icons.brightness_auto_outlined,
                  size: 20,
                  color: AppColors.brandTeal,
                ),
                const SizedBox(width: 12),
                Text(
                  'Appearance',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => controller.set(s.first),
            ),
          ],
        ),
      ),
    );
  }
}
