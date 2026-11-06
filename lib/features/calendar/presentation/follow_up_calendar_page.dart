import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/local_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../eggs/data/eggs_repository.dart';
import '../../eggs/data/eggs_sync_service.dart';
import '../../pmp/data/pmp_repository.dart';
import '../../poultry/data/poultry_capture_repository.dart';
import '../../poultry/data/poultry_repository.dart';
import '../../rawrmp/data/rawrmp_repository.dart';
import '../../visits/data/visit_repository.dart';
import '../../visits/presentation/store_visit_pages.dart';
import '../../../core/domain/facility_address.dart';
import '../../../core/widgets/search_picker.dart';
import '../data/conducted_visit_repository.dart';
import '../data/follow_up_repository.dart';
import '../data/planned_visit_repository.dart';

/// A month calendar of the inspector's work. Each day box shows who is due
/// that day — not a blank grid — and tapping a day opens the full detail.
///
/// Three things share the grid, and each keeps its own colour so a month
/// can be read at a glance without opening a single day:
///
/// * **Inspections conducted** (green) — the visits that were signed off,
///   sitting on the day the inspector was at the premises. The record of
///   what was actually done.
/// * **Planned visits** (amber) — the inspector's own, the week they intend
///   to work, which until now lived in a notebook.
/// * **Follow-ups due** (teal, red once overdue) — read off the records:
///   the "correct by" dates every commodity captures, which say where the
///   inspector *must* return and by when.
///
/// All three are shown together because a day is a day: the point of one
/// calendar is to see the work done and the returns already owed before
/// filling the rest of the week around them.
///
/// Conducted visits and follow-ups cannot be edited here; they belong to
/// the records behind them. Plans can be added, moved, edited and deleted
/// freely, and stay on the handset.
/// Green — an inspection that was conducted. Also ticks off a follow-up
/// whose return visit happened and a plan that has been started, because
/// both of those mean the same thing: the work was done. At file scope
/// because the calendar and the plan form both use it.
const _green = Color(0xFF2E7D32);

class FollowUpCalendarPage extends StatefulWidget {
  const FollowUpCalendarPage({
    super.key,
    required this.database,
    required this.visits,
    required this.eggs,
    required this.poultry,
    required this.poultryCapture,
    required this.rawRmp,
    required this.pmp,
    this.eggsSync,
    this.inspectorName,
    this.canRemoveRecords = false,
    this.planner,
  });

  final LocalDatabase database;
  final VisitRepository visits;
  final EggsRepository eggs;
  final EggsSyncService? eggsSync;
  final PoultryRepository poultry;
  final PoultryCaptureRepository poultryCapture;
  final RawRmpRepository rawRmp;
  final PmpRepository pmp;
  final String? inspectorName;
  final bool canRemoveRecords;

  /// The planning store. Passed in rather than built here so the calendar
  /// and Server Sync work the same rows — a plan written here is one the
  /// next sync finds waiting to go up.
  final PlannedVisitRepository? planner;

  @override
  State<FollowUpCalendarPage> createState() => _FollowUpCalendarPageState();
}

class _FollowUpCalendarPageState extends State<FollowUpCalendarPage> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// A planned visit, in the palette's "notice" amber.
  ///
  /// Not the brand orange, which this app has already spent on occurrence
  /// reports — an occurrence is a particular kind of record, and borrowing
  /// its colour for a diary entry made two unrelated things look related.
  /// The notice colours are the set the palette keeps for what is
  /// informational rather than alarming, which is exactly what a plan is:
  /// the inspector's own intention, not an obligation off a record. Read
  /// through the getters so it follows the handset into dark mode.
  static Color get _planInk => AppColors.noticeForeground;
  static Color get _planFill => AppColors.noticeBackground;
  static Color get _planEdge => AppColors.noticeBorder;

  /// A visit the office scheduled, in its own blue.
  ///
  /// Not the amber a plan the inspector made wears: the difference matters
  /// on the day, because this one is somebody else's instruction and
  /// cannot be moved or dropped here. Blue is the same colour the office's
  /// own planning board gives it, so the two screens agree.
  ///
  /// Read through getters, and dark mode gets its own pair, because the
  /// light fill with light text on it was unreadable on a handset after
  /// sunset — the same reason the notice colours are done this way.
  static bool get _isDark => AppColors.current == AppPalette.dark;
  static Color get _officeInk =>
      _isDark ? const Color(0xFF9FC0FF) : const Color(0xFF1D4ED8);
  static Color get _officeFill =>
      _isDark ? const Color(0xFF16233F) : const Color(0xFFE8EEFF);
  static Color get _officeEdge =>
      _isDark ? const Color(0xFF2C3F6B) : const Color(0xFFBFCDF8);

  /// What an inspector can be planning to do, offered as chips so a plan
  /// takes a tap rather than typing. More than one can be chosen: a single
  /// call at a store is one grouped inspection covering whatever is found
  /// there, commonly raw processed meat and eggs together. Anything else
  /// goes in the note.
  static const _commodities = [
    'Eggs',
    'Poultry',
    'Raw Processed Meat',
    'Processed Meat',
  ];

  bool _loading = true;
  final Map<DateTime, List<FollowUp>> _byDay = {};
  final Map<DateTime, List<PlannedVisit>> _plansByDay = {};
  final Map<DateTime, List<ConductedVisit>> _doneByDay = {};
  List<FollowUp> _all = const [];
  List<PlannedVisit> _plans = const [];
  List<ConductedVisit> _conducted = const [];

  /// The premises directory, for naming a planned visit without typing it.
  List<EggFacility> _directory = const [];

  /// Falls back to a local-only store, so the page still works in a test
  /// or on a device that was never pointed at a server.
  late final PlannedVisitRepository _planner =
      widget.planner ?? PlannedVisitRepository(widget.database);

  /// The visits already signed off, read straight from the handset's own
  /// records — nothing to configure and nothing to sync.
  late final ConductedVisitRepository _conductedVisits =
      ConductedVisitRepository(widget.database, widget.visits);

  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final list = await FollowUpRepository(widget.database).all();
    final plans = await _planner.all(widget.inspectorName);
    final done = await _conductedVisits.all(widget.inspectorName);
    // The directory only needs fetching once; a sync while the calendar is
    // open is rare enough not to be worth re-reading on every refresh.
    if (_directory.isEmpty) {
      try {
        _directory = await widget.eggs.facilities();
      } on Object {
        // A handset that has never synced has no directory. Planning still
        // works — the facility is simply typed.
        _directory = const [];
      }
    }
    final map = <DateTime, List<FollowUp>>{};
    for (final f in list) {
      map.putIfAbsent(f.date, () => []).add(f);
    }
    final planMap = <DateTime, List<PlannedVisit>>{};
    for (final p in plans) {
      planMap.putIfAbsent(p.plannedFor, () => []).add(p);
    }
    final doneMap = <DateTime, List<ConductedVisit>>{};
    for (final c in done) {
      doneMap.putIfAbsent(c.date, () => []).add(c);
    }
    if (!mounted) return;
    setState(() {
      _all = list;
      _plans = plans;
      _conducted = done;
      _byDay
        ..clear()
        ..addAll(map);
      _plansByDay
        ..clear()
        ..addAll(planMap);
      _doneByDay
        ..clear()
        ..addAll(doneMap);
      _loading = false;
    });
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// What was done in the month on screen — the one number a calendar of
  /// conducted visits is asked for, and it changes as the month is stepped
  /// through rather than sitting on today like the chips above it.
  int get _doneThisMonth => _conducted
      .where((c) => c.date.year == _month.year && c.date.month == _month.month)
      .length;

  List<FollowUp> get _upcoming =>
      _all.where((f) => !f.date.isBefore(_today)).toList();
  List<FollowUp> get _overdue =>
      _all.where((f) => f.date.isBefore(_today)).toList();

  /// Plans still to be done.
  ///
  /// Not only the ones ahead. A plan whose day has gone by without the
  /// inspection being started is the single most useful row on the page —
  /// it is the visit that was missed — and it was being dropped from the
  /// list entirely, so the calendar said "nothing planned" while holding
  /// one. It is shown, marked MISSED, for a fortnight afterwards; older
  /// than that it stays on the grid and on the office's copy but stops
  /// crowding the list.
  List<PlannedVisit> get _plannedAhead {
    final from = _today.subtract(const Duration(days: 14));
    return _plans
        .where((p) =>
            p.startedVisitUuid.isEmpty && !p.plannedFor.isBefore(from))
        .toList();
  }

  String _fmt(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

  void _step(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Follow-up Calendar'),
        actions: [
          TextButton(
            onPressed: () =>
                setState(() => _month = DateTime(_today.year, _today.month)),
            child: const Text('Today'),
          ),
        ],
      ),
      // The one thing an inspector comes here to do that the calendar cannot
      // do for them. Always within reach, whatever is scrolled into view.
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editPlan(onDay: _today),
              icon: const Icon(Icons.add),
              label: const Text('Plan a visit'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
              children: [
                _summary(),
                const SizedBox(height: 14),
                _calendarCard(),
                const SizedBox(height: 20),
                _upcomingSection(),
              ],
            ),
    );
  }

  // ---- summary ------------------------------------------------------------

  Widget _summary() => Row(
        children: [
          Expanded(
            child: _statChip(
              value: '${_plannedAhead.length}',
              label: 'Planned',
              color: _planInk,
              icon: Icons.push_pin_outlined,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statChip(
              value: '${_upcoming.length}',
              label: 'Follow-ups',
              color: AppColors.brandPrimary,
              icon: Icons.event_available_outlined,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statChip(
              value: '${_overdue.length}',
              label: 'Overdue',
              color: AppColors.brandRed,
              icon: Icons.error_outline,
            ),
          ),
        ],
      );

  Widget _statChip({
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: color,
                          height: 1.0)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(label,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ---- calendar -----------------------------------------------------------

  Widget _calendarCard() {
    final leading = _month.weekday - 1; // Mon-first
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => _step(-1),
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left)),
              // Tap the month to jump to any month/year quickly.
              Expanded(
                child: InkWell(
                  onTap: _pickMonth,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                              '${_months[_month.month - 1]} ${_month.year}',
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down,
                            size: 22, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                  onPressed: () => _step(1),
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Cells scale with the available width so the grid fits phones and
          // tablets alike.
          LayoutBuilder(
            builder: (context, c) {
              const spacing = 3.0;
              final cellW = (c.maxWidth - spacing * 6) / 7;
              final extent = (cellW * 1.45).clamp(74.0, 130.0);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leading + daysInMonth,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: extent,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                ),
                itemBuilder: (_, index) {
                  if (index < leading) return const SizedBox();
                  return _buildCell(index - leading + 1);
                },
              );
            },
          ),
          const SizedBox(height: 8),
          if (_doneThisMonth > 0) ...[
            Text(
              '$_doneThisMonth inspection${_doneThisMonth == 1 ? '' : 's'} '
              'conducted in ${_months[_month.month - 1]}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _green),
            ),
            const SizedBox(height: 6),
          ],
          _legend(),
        ],
      ),
    );
  }

  // ---- month/year picker --------------------------------------------------

  Future<void> _pickMonth() async {
    var year = _month.year;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Jump to month',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          onPressed: () => setSheet(() => year--),
                          icon: const Icon(Icons.chevron_left)),
                      Text('$year',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      IconButton(
                          onPressed: () => setSheet(() => year++),
                          icon: const Icon(Icons.chevron_right)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Three columns of month buttons, fixed comfortable height
                  // so the whole picker is always visible.
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 52,
                    children: [
                      for (var m = 1; m <= 12; m++)
                        _monthChoice(m, year, sheetCtx),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthChoice(int m, int year, BuildContext sheetCtx) {
    final selected = _month.year == year && _month.month == m;
    final isCurrent = _today.year == year && _today.month == m;
    final hasItems =
        _all.any((f) => f.date.year == year && f.date.month == m);
    return InkWell(
      onTap: () {
        setState(() => _month = DateTime(year, m));
        Navigator.of(sheetCtx).pop();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandPrimary
              : (hasItems
                  ? AppColors.brandPrimary.withValues(alpha: 0.08)
                  : AppColors.surfaceAlt),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.brandPrimary
                : (isCurrent ? AppColors.brandPrimary : AppColors.border),
            width: isCurrent && !selected ? 1.4 : 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_months[m - 1],
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.ink)),
            if (hasItems) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.brandPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCell(int dayNum) {
    final day = DateTime(_month.year, _month.month, dayNum);
    final items = _byDay[day] ?? const <FollowUp>[];
    final plans = _plansByDay[day] ?? const <PlannedVisit>[];
    final done = _doneByDay[day] ?? const <ConductedVisit>[];
    final isToday = day == _today;
    final overdue = items.isNotEmpty && day.isBefore(_today);
    final accent = overdue ? AppColors.brandRed : AppColors.brandPrimary;

    // Two lines fit in a cell, and three kinds of thing want them. What was
    // conducted goes first: it is the one that happened, and on a past day
    // it is usually the only reason to look at the cell at all. The
    // inspector's own plans come next — a follow-up can be read off the
    // record later, a plan exists nowhere else.
    final total = done.length + plans.length + items.length;
    final showDone = done.take(2).toList();
    final showPlans = plans.take(2 - showDone.length).toList();
    final showItems =
        items.take(2 - showDone.length - showPlans.length).toList();
    final extra =
        total - showDone.length - showPlans.length - showItems.length;

    return InkWell(
      // Every day opens, empty ones included: the sheet both shows what
      // is on the day and adds to it, so one tap covers both and neither
      // is behind a question about which one was meant.
      onTap: () => _showDaySheet(day),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          // Tinted by whatever is on the day, in the same order the chips
          // are listed, so the wash behind a cell agrees with the chip at
          // the top of it rather than naming a different thing.
          color: done.isNotEmpty
              ? _green.withValues(alpha: 0.08)
              : (plans.isNotEmpty
                  // Blue when the day holds the office's work, amber when
                  // it is the inspector's own, so the wash behind the cell
                  // agrees with the chips in it.
                  ? (plans.every((p) => p.scheduledByOffice)
                      ? _officeFill
                      : _planFill)
                  : (items.isNotEmpty
                      ? accent.withValues(alpha: 0.08)
                      : null)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? AppColors.brandPrimary : AppColors.border,
            width: isToday ? 1.6 : 0.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$dayNum',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                  color: isToday ? AppColors.brandPrimary : AppColors.ink,
                )),
            const SizedBox(height: 2),
            for (final c in showDone) _chip(c.facility, _green, done: true),
            // A plan or a follow-up that has been dealt with keeps its own
            // colour and gets a tick. It used to turn green, which now
            // reads as "an inspection was conducted on this day" — and on
            // a plan's own day that is a different claim: the plan is
            // ticked off where it was made, while the visit it became is
            // the green chip on the day it actually happened.
            for (final p in showPlans)
              _chip(
                p.facilityName.isEmpty ? 'Planned' : p.facilityName,
                p.scheduledByOffice ? _officeInk : _planInk,
                done: p.startedVisitUuid.isNotEmpty,
              ),
            for (final f in showItems)
              _chip(f.facility, accent, done: f.done),
            if (extra > 0)
              Text('+$extra more',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: accent)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color c, {bool done = false}) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done) ...[
              Icon(Icons.check, size: 9.5, color: c),
              const SizedBox(width: 2),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w700, color: c),
              ),
            ),
          ],
        ),
      );

  Widget _legend() => Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 4,
        children: [
          _legendDot(_green, 'Inspection done'),
          _legendDot(_planInk, 'Planned by you'),
          _legendDot(_officeInk, 'From the office'),
          _legendDot(AppColors.brandPrimary, 'Follow-up due'),
          _legendDot(AppColors.brandRed, 'Overdue'),
          _legendDot(null, 'Today', outline: true),
        ],
      );

  Widget _legendDot(Color? color, String label, {bool outline = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: outline ? null : color,
              shape: BoxShape.circle,
              border: outline
                  ? Border.all(color: AppColors.brandPrimary, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      );

  // ---- day detail sheet ---------------------------------------------------

  /// The day itself: what is on it, and the way to put something on it.
  ///
  /// One sheet rather than a chooser. Asking "view or add?" before showing
  /// anything makes the inspector answer a question they can answer better
  /// by looking — so the day opens, with Add at the top and whatever is
  /// already there underneath it.
  Future<void> _showDaySheet(DateTime day) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Rebuilt from the page's own maps on every frame, so a plan added
      // or removed from inside the sheet shows without closing it.
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final items = _byDay[day] ?? const <FollowUp>[];
          final plans = _plansByDay[day] ?? const <PlannedVisit>[];
          final done = _doneByDay[day] ?? const <ConductedVisit>[];
          Future<void> refresh() async {
            await _load();
            if (mounted) setSheet(() {});
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.92,
            builder: (_, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text('${_weekdays[day.weekday - 1]}, ${_fmt(day)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  _daySummaryLine(done.length, plans.length, items.length),
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _editPlan(onDay: day);
                      await refresh();
                    },
                    icon: const Icon(Icons.add, size: 19),
                    label: const Text('Add a visit on this day'),
                  ),
                ),
                const SizedBox(height: 16),
                if (done.isEmpty && plans.isEmpty && items.isEmpty)
                  _emptyNote('Nothing on this day yet. Add a visit above and '
                      'it will show here and on the calendar.'),
                if (done.isNotEmpty) ...[
                  const _SectionLabel('Inspections conducted'),
                  const SizedBox(height: 8),
                  ...done.map(_conductedCard),
                  const SizedBox(height: 8),
                ],
                // The office's work and the inspector's own are listed
                // apart, with the office's first. They are not the same
                // kind of thing: one is an instruction with somebody
                // waiting on it, the other is a note to self.
                if (plans.any((p) => p.scheduledByOffice)) ...[
                  const _SectionLabel('From the office'),
                  const SizedBox(height: 8),
                  ...plans
                      .where((p) => p.scheduledByOffice)
                      .map((p) => _planCard(p, onChanged: refresh)),
                  const SizedBox(height: 8),
                ],
                if (plans.any((p) => !p.scheduledByOffice)) ...[
                  const _SectionLabel('Planned by you'),
                  const SizedBox(height: 8),
                  ...plans
                      .where((p) => !p.scheduledByOffice)
                      .map((p) => _planCard(p, onChanged: refresh)),
                  const SizedBox(height: 8),
                ],
                if (items.isNotEmpty) ...[
                  const _SectionLabel('Follow-ups due'),
                  const SizedBox(height: 8),
                  ...items.map(_followUpCard),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _daySummaryLine(int done, int plans, int dues) {
    final parts = [
      if (done > 0) '$done inspection${done == 1 ? '' : 's'} conducted',
      if (plans > 0) '$plans planned visit${plans == 1 ? '' : 's'}',
      if (dues > 0) '$dues follow-up${dues == 1 ? '' : 's'} due',
    ];
    return parts.isEmpty ? 'Nothing on this day yet' : parts.join('  -  ');
  }

  // ---- planning -----------------------------------------------------------

  /// Opens the plan form, and writes whatever comes back.
  ///
  /// One form for both new and existing plans, because they ask for exactly
  /// the same things; [existing] only decides what it opens filled with and
  /// whether Delete is offered.
  Future<void> _editPlan({PlannedVisit? existing, DateTime? onDay}) async {
    final result = await showModalBottomSheet<_PlanResult>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PlanSheet(
        day: existing?.plannedFor ?? onDay ?? _today,
        existing: existing,
        directory: _directory,
        commodities: _commodities,
      ),
    );
    if (result == null) return;

    if (result.delete) {
      await _planner.delete(existing!.uuid);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Planned visit removed.')));
    } else {
      await _planner.save(
        uuid: existing?.uuid,
        inspector: widget.inspectorName ?? '',
        plannedFor: result.date,
        facilityName: result.facility,
        facilityAddress: result.address,
        facilityPhone: result.phone,
        commodities: result.commodities,
        note: result.note,
      );
      if (!mounted) return;
      // Bring the grid to the month the plan landed in, so the inspector
      // sees what they just made rather than having to find it.
      setState(() => _month = DateTime(result.date.year, result.date.month));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(existing == null
                ? 'Planned for ${_fmt(result.date)}.'
                : 'Plan updated.')));
    }
    await _load();
  }

  /// Opens the real inspection from a plan, pre-filled the same way a
  /// follow-up does, and notes on the plan which visit it became.
  Future<void> _startPlanned(PlannedVisit plan) async {
    final navigator = Navigator.of(context);
    final uuid = const Uuid().v4();
    final inspector = widget.inspectorName ?? '';
    await widget.visits.create(uuid, inspector);
    await widget.visits.updateDetails(
      uuid,
      StoreVisitsCompanion(
        facilityName: Value(plan.facilityName),
        facilityAddress: Value(plan.facilityAddress),
        facilityPhone: Value(plan.facilityPhone),
      ),
    );
    await _planner.markStarted(plan.uuid, uuid);
    if (!mounted) return;
    _closeSheetIfOpen(navigator);
    await navigator.push(
      MaterialPageRoute<String>(
        builder: (_) => StoreVisitPage(
          visitUuid: uuid,
          visits: widget.visits,
          eggs: widget.eggs,
          eggsSync: widget.eggsSync,
          poultry: widget.poultry,
          poultryCapture: widget.poultryCapture,
          rawRmp: widget.rawRmp,
          pmp: widget.pmp,
          inspectorName: inspector,
          canRemoveRecords: widget.canRemoveRecords,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// Dismisses the day sheet, and only the day sheet.
  ///
  /// See the note in [_startFollowUp]: the cards that call this are shown
  /// both inside the sheet and on the page behind it.
  void _closeSheetIfOpen(NavigatorState navigator) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent && navigator.canPop()) {
      navigator.pop();
    }
  }

  Widget _planCard(PlannedVisit plan, {required Future<void> Function() onChanged}) {
    final started = plan.startedVisitUuid.isNotEmpty;
    final office = plan.scheduledByOffice;
    final accent = started ? _green : (office ? _officeInk : _planInk);
    final overdue = !started && plan.plannedFor.isBefore(_today);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: started
            ? _green.withValues(alpha: 0.06)
            : (office ? _officeFill : _planFill),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: started
                ? _green.withValues(alpha: 0.40)
                : (office ? _officeEdge : _planEdge)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.30)),
                  ),
                  child: Column(
                    children: [
                      Text('${plan.plannedFor.day}',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(_mon[plan.plannedFor.month - 1].toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          plan.facilityName.isEmpty
                              ? 'Planned visit'
                              : plan.facilityName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if (plan.facilityAddress.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: AppColors.muted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(plan.facilityAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _tag(office ? 'FROM THE OFFICE' : 'PLANNED', accent,
                              filled: true),
                          for (final c in commoditiesOf(plan))
                            _tag(c, AppColors.brandPrimary),
                          if (started) _tag('STARTED', _green, filled: true),
                          if (overdue)
                            _tag('MISSED', AppColors.brandRed, filled: true),
                        ],
                      ),
                      if (plan.note.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(plan.note,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                color: AppColors.muted)),
                      ],
                      // Whose instruction it is. "The office" is nobody;
                      // a name is someone to ring if the day does not work.
                      if (office) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.business_outlined,
                                size: 13, color: _officeInk),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                plan.scheduledBy.trim().isEmpty
                                    ? 'Scheduled by the office'
                                    : 'Scheduled by ${plan.scheduledBy.trim()}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _officeInk),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!started)
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: () => _startPlanned(plan),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Start inspection'),
                      ),
                    ),
                  ),
                // Edit and remove are for the inspector's own plans only.
                // A visit the office scheduled is somebody else's
                // instruction and they are relying on it being made; it is
                // withdrawn at the office, not here. The inspection still
                // starts from it in exactly the same way.
                if (!office) ...[
                  if (!started) const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _editPlan(existing: plan);
                        await onChanged();
                      },
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // On the card, not only inside the form. A plan that
                  // falls away — the store calls to cancel, the round is
                  // reshuffled — is removed far more often than it is
                  // edited, and making that go through the editor left
                  // stale visits sitting on the week.
                  SizedBox(
                    height: 40,
                    width: 48,
                    child: OutlinedButton(
                      onPressed: () async {
                        if (await _confirmDeletePlan(plan)) await onChanged();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandRed,
                        side: BorderSide(
                            color: AppColors.brandRed.withValues(alpha: 0.5)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.delete_outline, size: 19),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Asks before removing a plan, and says what is and is not affected.
  ///
  /// Returns true when it was removed. Nothing captured is touched: a plan
  /// is only ever the inspector's own note of where they meant to go, so
  /// the warning says so rather than sounding like a record is at stake.
  Future<bool> _confirmDeletePlan(PlannedVisit plan) async {
    final named = plan.facilityName.trim();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this planned visit?'),
        content: Text(
          named.isEmpty
              ? 'It comes off your calendar. Nothing that was captured is '
                  'affected.'
              : '$named on ${_fmt(plan.plannedFor)} comes off your calendar. '
                  'Nothing that was captured is affected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return false;

    await _planner.delete(plan.uuid);
    await _load();
    if (!mounted) return true;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
          const SnackBar(content: Text('Planned visit removed.')));
    return true;
  }

  Widget _tag(String text, Color color, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: filled ? 10 : 11,
                fontWeight: filled ? FontWeight.w800 : FontWeight.w700,
                color: filled ? Colors.white : color)),
      );

  // ---- start a follow-up inspection --------------------------------------

  Future<void> _startFollowUp(FollowUp f) async {
    final navigator = Navigator.of(context);
    final uuid = const Uuid().v4();
    final inspector = widget.inspectorName ?? '';
    await widget.visits.create(uuid, inspector);
    await widget.visits.updateDetails(
      uuid,
      StoreVisitsCompanion(
        facilityName: Value(f.facility),
        facilityAddress: Value(f.address),
        facilityPhone: Value(f.phone),
        inspectionReason: const Value('Follow-up'),
      ),
    );
    if (!mounted) return;
    // Close the day sheet if it is open, then open the new visit for
    // capture — the same screen the normal inspection flow uses.
    //
    // Only if it is open. The same card is shown in the list further down
    // the page, where nothing is stacked on the calendar and a bare
    // canPop() would close the calendar itself: the inspector would come
    // back from the inspection to the home screen instead of the calendar
    // they started from. The calendar's route not being the current one is
    // what tells us the sheet is there.
    _closeSheetIfOpen(navigator);
    await navigator.push(
      MaterialPageRoute<String>(
        builder: (_) => StoreVisitPage(
          visitUuid: uuid,
          visits: widget.visits,
          eggs: widget.eggs,
          eggsSync: widget.eggsSync,
          poultry: widget.poultry,
          poultryCapture: widget.poultryCapture,
          rawRmp: widget.rawRmp,
          pmp: widget.pmp,
          inspectorName: inspector,
          canRemoveRecords: widget.canRemoveRecords,
        ),
      ),
    );
    if (mounted) await _load();
  }

  // ---- upcoming list ------------------------------------------------------

  Widget _upcomingSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Your planned visits'),
          const SizedBox(height: 8),
          if (_plannedAhead.isEmpty)
            _emptyNote('Nothing planned yet. Use + on a day, or the '
                'Plan a visit button, to set out your week.')
          else
            ..._plannedAhead.map((p) => _planCard(p, onChanged: _load)),
          const SizedBox(height: 20),
          const _SectionLabel('All upcoming follow-ups'),
          const SizedBox(height: 8),
          if (_upcoming.isEmpty)
            _emptyNote('No upcoming follow-ups.')
          else
            ..._upcoming.map((f) => _followUpCard(f)),
        ],
      );

  Widget _emptyNote(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text, style: TextStyle(color: AppColors.muted)),
      );

  /// One inspection that was carried out on this day.
  ///
  /// Read-only on purpose: a signed-off visit is a record, and the place to
  /// change one is Inspection Management, where the edit is pushed back to
  /// the office. The calendar only says it happened.
  Widget _conductedCard(ConductedVisit c) {
    final time = '${c.completedAt.hour.toString().padLeft(2, '0')}:'
        '${c.completedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.40)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle, size: 24, color: _green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.facility,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  if (c.address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 13, color: AppColors.muted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(c.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (c.isOccurrenceReport)
                        _tag('OCCURRENCE REPORT', _green, filled: true)
                      else if (c.commodities.isEmpty)
                        _tag('No inspections captured', AppColors.muted)
                      else
                        for (final name in c.commodities)
                          _tag(name, AppColors.brandPrimary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Signed off at $time',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followUpCard(FollowUp f) {
    const green = Color(0xFF2E7D32);
    final overdue = f.date.isBefore(_today);
    final accent = f.done ? green : (overdue ? AppColors.brandRed : AppColors.brandPrimary);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: f.done ? green.withValues(alpha: 0.06) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: f.done ? green.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text('${f.date.day}',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: accent,
                              height: 1.0)),
                      const SizedBox(height: 2),
                      Text(_mon[f.date.month - 1].toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.facility,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if (f.address.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: AppColors.muted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(f.address.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandPrimary
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(f.detail,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandPrimary)),
                          ),
                          if (f.done) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: green,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('DONE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ] else if (overdue) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.brandRed,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('OVERDUE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f.inspectedOn == null
                            ? 'Return by ${_fmt(f.date)}'
                            : 'Inspected ${_fmt(f.inspectedOn!)}  →  return by '
                                '${_fmt(f.date)}',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!f.done) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton.icon(
                  onPressed: () => _startFollowUp(f),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start follow-up inspection'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: AppColors.muted,
        ),
      );
}

/// What the plan form hands back. [delete] is the one answer that is not a
/// set of values, so it travels with them rather than through a second
/// channel the caller could forget to read.
typedef _PlanResult = ({
  bool delete,
  DateTime date,
  String facility,
  String address,
  String phone,
  List<String> commodities,
  String note,
});

/// The form for one planned visit.
///
/// Deliberately short. An inspector planning six stops will not fill in six
/// long forms, so only the date is actually required — everything else is
/// there to make the day easier when it arrives, and a plan that says no
/// more than "Tuesday, Kekkel en Kraai" is a useful plan.
class _PlanSheet extends StatefulWidget {
  const _PlanSheet({
    required this.day,
    required this.directory,
    required this.commodities,
    this.existing,
  });

  final DateTime day;
  final List<EggFacility> directory;
  final List<String> commodities;
  final PlannedVisit? existing;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  static const _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec',
  ];

  late DateTime _date = widget.existing?.plannedFor ?? widget.day;
  late final _facility =
      TextEditingController(text: widget.existing?.facilityName ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.facilityAddress ?? '');

  /// Tidying happens when the inspector leaves the box, never as they
  /// type: rewriting a half-typed address under the cursor is the quickest
  /// way to make a field feel broken.
  final _addressFocus = FocusNode();
  late final _phone =
      TextEditingController(text: widget.existing?.facilityPhone ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  /// Kept in the order of the chip list rather than the order they were
  /// tapped, so the same two commodities always read the same way.
  late final Set<String> _chosen = {
    if (widget.existing != null) ...commoditiesOf(widget.existing!),
  };

  /// What is wrong with the address as written, empty when it is right.
  List<String> _addressProblems = const [];

  @override
  void initState() {
    super.initState();
    _addressFocus.addListener(() {
      if (_addressFocus.hasFocus) return;
      final tidied = FacilityAddress.tidy(_address.text);
      setState(() {
        if (tidied != _address.text) _address.text = tidied;
        _addressProblems = FacilityAddress.problems(_address.text);
      });
    });
  }

  @override
  void dispose() {
    _facility.dispose();
    _address.dispose();
    _phone.dispose();
    _addressFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Plan this visit for',
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _save() {
    // Tidied on the way out, whether or not it is complete: a correct
    // address can still be untidy — "western Cape", a double comma, a
    // stray space — and it should settle into its proper spelling rather
    // than leave the office with two of everything.
    //
    // Nothing is refused. The shape is shown under the box and the gaps
    // are named while the box is being filled; a plan is the inspector's
    // own note and holding it hostage over a postal code only teaches
    // them not to write plans.
    final tidied = FacilityAddress.tidy(_address.text);
    if (tidied != _address.text) _address.text = tidied;
    _pop();
  }

  void _pop() => Navigator.of(context).pop((
        delete: false,
        date: _date,
        facility: _facility.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        commodities: [
          for (final c in widget.commodities)
            if (_chosen.contains(c)) c,
        ],
        note: _note.text.trim(),
      ));

  Future<void> _confirmDelete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this plan?'),
        content: const Text(
            'It only comes off your calendar. Nothing that was captured is '
            'affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    Navigator.of(context).pop((
      delete: true,
      date: _date,
      facility: '',
      address: '',
      phone: '',
      commodities: const <String>[],
      note: '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return SafeArea(
      child: Padding(
        // Lifted clear of the keyboard, which otherwise covers the note
        // field and the Save button together.
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.95,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              Text(editing ? 'Edit planned visit' : 'Plan a visit',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                'Only the date is needed. The rest saves you time on the day.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 14),

              _label('Day'),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.brandPrimary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_fmt(_date),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      const Text('Change',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandPrimary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _label('Facility'),
              SearchPickerField<EggFacility>(
                label: 'Facility name',
                controller: _facility,
                options: widget.directory,
                optionLabel: (f) => f.name,
                optionSubtitle: (f) => f.physicalAddress,
                onSelected: (f) => setState(() {
                  _facility.text = f.name;
                  if (f.physicalAddress.trim().isNotEmpty) {
                    _address.text = f.physicalAddress.trim();
                  }
                  if (f.telephone.trim().isNotEmpty) {
                    _phone.text = f.telephone.trim();
                  }
                }),
                emptyHint: 'No premises on this device yet. You can still '
                    'type the name.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                focusNode: _addressFocus,
                maxLines: 2,
                minLines: 1,
                // Rebuilt on every keystroke so the guide below fills in
                // as they type, which is the whole point of it.
                onChanged: (_) => setState(() => _addressProblems = const []),
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperMaxLines: 3,
                  helperText: FacilityAddress.asking,
                  errorMaxLines: 3,
                  errorText: _addressProblems.isEmpty
                      ? null
                      : _addressProblems.join(' '),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telephone',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),

              _label('What for'),
              Text('Choose as many as the visit covers.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in widget.commodities)
                    FilterChip(
                      label: Text(c),
                      selected: _chosen.contains(c),
                      onSelected: (on) => setState(
                          () => on ? _chosen.add(c) : _chosen.remove(c)),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              _label('Note'),
              TextField(
                controller: _note,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Anything to remember - who to ask for, what to '
                      'check, where to park',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check, size: 19),
                  label: Text(editing ? 'Save changes' : 'Add to my calendar'),
                ),
              ),
              if (editing) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: TextButton.icon(
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline, size: 19),
                    label: const Text('Remove this plan'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandRed),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }


  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            color: AppColors.muted,
          ),
        ),
      );
}
