import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'required_label.dart';

/// A text field that offers matching records as you type.
///
/// A plain dropdown is unusable once the directory runs to thousands of
/// entries, and a plain text field means the same premises is spelled three
/// ways across three visits. This keeps the field free-text — an inspector can
/// still record somewhere that is not on the list — while making the known
/// entries one tap away.
///
/// Built for a directory of thousands on a cheap handset. Three things keep
/// typing responsive at that size:
///
///  * names are lower-cased **once** into [_haystack], not per keystroke;
///  * matching runs on a debounce, so a fast typist triggers one pass, not one
///    per letter;
///  * matching happens outside `build`, so an unrelated rebuild does not
///    rescan the directory.
///
/// Without those, every keystroke allocated one lowercase string per record —
/// which on five thousand clients is what made the keyboard stutter.
class SearchPickerField<T> extends StatefulWidget {
  const SearchPickerField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
    this.optionSubtitle,
    this.isRequired = false,
    this.emptyHint,
    this.minQueryLength = 2,
    this.maxListHeight = 300,
    this.debounce = const Duration(milliseconds: 120),
    this.onAddNew,
    this.addNewLabel,
  });

  final String label;
  final TextEditingController controller;
  final List<T> options;
  final String Function(T) optionLabel;

  /// Second line under each suggestion — address, type, whatever tells two
  /// similarly-named entries apart. Shown, but never searched.
  final String Function(T)? optionSubtitle;

  final ValueChanged<T> onSelected;
  final bool isRequired;

  /// Shown when the device holds no records at all, which is different from a
  /// search that simply matched nothing.
  final String? emptyHint;

  /// Registers something the directory does not hold, and hands back what was
  /// typed so the sheet can be pre-filled with it.
  ///
  /// Inspectors arrive at premises that are not on the list. Without this the
  /// name goes onto the inspection as loose text and nobody else ever sees it
  /// again; the next inspector at the same depot types it afresh, differently.
  final Future<void> Function(String typedName)? onAddNew;

  /// What the button says — "Add as a new client", "Add as new premises".
  final String? addNewLabel;

  /// Characters needed before searching. Below this, nothing is listed —
  /// against a directory of thousands, a single letter is not a search.
  final int minQueryLength;

  /// Height cap on the results list. Every match is reachable by scrolling;
  /// this only stops the list from pushing the rest of the form off-screen.
  final double maxListHeight;

  /// How long to wait after the last keystroke before matching.
  final Duration debounce;

  @override
  State<SearchPickerField<T>> createState() => _SearchPickerFieldState<T>();
}

class _SearchPickerFieldState<T> extends State<SearchPickerField<T>> {
  final _focus = FocusNode();

  /// The text field itself, measured after each frame. The form is never
  /// scrolled for the inspector; instead the list floats over the form,
  /// anchored to the field, below it when there is room and above it when
  /// the keyboard has taken the room below.
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _overlay = OverlayPortalController();

  double _fieldWidth = 0;
  bool _openAbove = false;
  double _panelMaxHeight = 300;

  /// Lower-cased names, index-aligned with `widget.options`. Built once.
  late List<String> _haystack;

  List<T> _matches = const [];
  bool _exactMatch = false;
  String _appliedQuery = '';
  bool _open = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _buildHaystack();
    _focus.addListener(() {
      // Keep the list up while the field has focus; collapse once it loses it,
      // so the rest of the form is not permanently pushed down the screen.
      if (!mounted) return;
      setState(() => _open = _focus.hasFocus);
      _syncOverlay();
    });
  }

  @override
  void didUpdateWidget(SearchPickerField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the directory itself changed — a sync, typically. Comparing
    // identity first keeps an ordinary rebuild off this path.
    if (!identical(oldWidget.options, widget.options) ||
        oldWidget.options.length != widget.options.length) {
      _buildHaystack();
      _runSearch(force: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _buildHaystack() {
    _haystack = List<String>.generate(
      widget.options.length,
      (i) => widget.optionLabel(widget.options[i]).toLowerCase(),
      growable: false,
    );
  }

  String get _query => widget.controller.text.trim().toLowerCase();

  void _onChanged(String _) {
    _debounce?.cancel();
    final query = _query;
    // Crossing the minimum, or clearing the field, changes what is on screen
    // immediately — waiting for the debounce there just feels broken.
    if (query.length < widget.minQueryLength) {
      if (_matches.isNotEmpty || _appliedQuery.isNotEmpty) {
        setState(() {
          _matches = const [];
          _exactMatch = false;
          _appliedQuery = query;
        });
      } else {
        setState(() {});
      }
      return;
    }
    // Rebuild now — without it the previous query's results stay painted under
    // the new text, which reads as the search having already answered. This is
    // a cheap rebuild: it renders a one-line note, and the directory is not
    // touched until the debounce fires.
    setState(() {});
    _debounce = Timer(widget.debounce, _runSearch);
  }

  /// One pass over the pre-lowered names, collecting prefix matches, substring
  /// matches and the exact-match flag together.
  void _runSearch({bool force = false}) {
    if (!mounted) return;
    final query = _query;
    if (!force && query == _appliedQuery) return;

    if (query.length < widget.minQueryLength) {
      setState(() {
        _matches = const [];
        _exactMatch = false;
        _appliedQuery = query;
      });
      return;
    }

    final starts = <T>[];
    final contains = <T>[];
    var exact = false;
    for (var i = 0; i < _haystack.length; i++) {
      final name = _haystack[i];
      if (name.startsWith(query)) {
        starts.add(widget.options[i]);
        if (!exact && name.length == query.length) exact = true;
      } else if (name.contains(query)) {
        contains.add(widget.options[i]);
      }
    }

    // "Cape Egg Packers" outranks "Western Cape Traders" for "cape", but both
    // are offered — every match is reachable.
    int byName(T a, T b) =>
        widget.optionLabel(a).compareTo(widget.optionLabel(b));
    starts.sort(byName);
    contains.sort(byName);

    setState(() {
      _matches = [...starts, ...contains];
      _exactMatch = exact;
      _appliedQuery = query;
    });
  }

  void _syncOverlay() {
    if (_open && !_overlay.isShowing) {
      _overlay.show();
    } else if (!_open && _overlay.isShowing) {
      _overlay.hide();
    }
  }

  /// Decides which side of the field the list opens on, and how tall it may
  /// be, from where the field actually sits on screen this frame.
  ///
  /// Searching used to scroll the whole form to make room, which read as
  /// losing one's place; leaving the form still and always opening downward
  /// put the matches under the keyboard whenever the field sat low. So the
  /// list behaves like a menu: below when there is room, above when there is
  /// not, and the field never moves.
  void _measurePlacement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) return;
      final field = _fieldKey.currentContext;
      if (field == null || !field.mounted) return;
      final box = field.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;

      // Read straight off the view, not through MediaQuery: inside a Scaffold
      // that shrinks for the keyboard the inset reads as zero, and the
      // nearest Scrollable's box proved an unreliable stand-in. The view
      // knows the screen, the keyboard and the status bar for certain.
      final view = MediaQueryData.fromView(View.of(field));
      final bottom = view.size.height - view.viewInsets.bottom;
      final top = view.padding.top;
      final fieldTop = box.localToGlobal(Offset.zero).dy;
      final fieldBottom = fieldTop + box.size.height;
      final roomBelow = bottom - fieldBottom - _gap;
      final roomAbove = fieldTop - top - _gap;

      // One row, the "add new" line and the count is the least worth
      // showing; below that, the other side is the better home if it has
      // more room.
      final above = roomBelow < _minPanel && roomAbove > roomBelow;
      final room = above ? roomAbove : roomBelow;
      final maxHeight =
          room.clamp(_minPanel * 0.8, widget.maxListHeight + _chrome);

      if (above != _openAbove ||
          (maxHeight - _panelMaxHeight).abs() > 1 ||
          (box.size.width - _fieldWidth).abs() > 1) {
        setState(() {
          _openAbove = above;
          _panelMaxHeight = maxHeight;
          _fieldWidth = box.size.width;
        });
      }
    });
  }

  /// Space between the field and the list.
  static const _gap = 6.0;

  /// The "add new" row and the match-count footer, roughly.
  static const _chrome = 100.0;

  /// One match row plus the chrome.
  static const _minPanel = 56.0 + _chrome;

  double get _listHeight =>
      (_panelMaxHeight - _chrome).clamp(56.0, widget.maxListHeight);

  bool get _searching => _query.length >= widget.minQueryLength;

  void _choose(T option) {
    widget.onSelected(option);
    _focus.unfocus();
    _debounce?.cancel();
    setState(() {
      _open = false;
      _appliedQuery = _query;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_open) _measurePlacement();
    return LabelledField(
      label: widget.label,
      isRequired: widget.isRequired,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (_) => _floatingPanel(),
          child: TextField(
            key: _fieldKey,
            controller: widget.controller,
            focusNode: _focus,
            style: const TextStyle(fontSize: 15.5),
            textInputAction: TextInputAction.next,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: widget.controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: 'Clear',
                      onPressed: () {
                        widget.controller.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The matches, floating over the form and glued to the field.
  ///
  /// Drawn in the app's overlay so it covers whatever is under it instead of
  /// pushing the form about, and follows the field if the form scrolls.
  Widget _floatingPanel() {
    if (!_open) return const SizedBox.shrink();
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: _openAbove ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: _openAbove ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, _openAbove ? -_gap : _gap),
      child: Align(
        alignment: _openAbove ? Alignment.bottomLeft : Alignment.topLeft,
        child: SizedBox(
          width: _fieldWidth > 0 ? _fieldWidth : null,
          child: Material(
            color: AppColors.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _panelMaxHeight),
              child: SingleChildScrollView(
                // Only ever scrolls when even one row will not fit; the
                // match list itself scrolls inside its own box.
                physics: const ClampingScrollPhysics(),
                child: _suggestions(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The "add new" row, drawn the way the office system draws it: a
  /// highlighted line directly under the field, quoting what was typed —
  /// not a button parked below the list, which reads as a separate act.
  Widget _addNewRow({bool rounded = false}) {
    final typed = widget.controller.text.trim();
    if (typed.isEmpty) return const SizedBox.shrink();
    return Material(
      color: AppColors.noticeBackground,
      borderRadius: rounded ? BorderRadius.circular(12) : null,
      child: InkWell(
        borderRadius: rounded ? BorderRadius.circular(12) : null,
        onTap: () async {
          _focus.unfocus();
          setState(() => _open = false);
          await widget.onAddNew!(typed);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.noticeBorder),
            borderRadius: rounded ? BorderRadius.circular(12) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle,
                  size: 18, color: AppColors.noticeForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.addNewLabel ?? 'Add new'}: "$typed"',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.noticeForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestions() {
    if (widget.options.isEmpty) {
      // A handset that has never synced still has to be able to work: the
      // inspector is standing at the premises, and refusing to register one
      // because the directory is empty is the worst moment to say no.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(
            widget.emptyHint ??
                'No records on this device yet. Sync to download them.',
          ),
          if (widget.onAddNew != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _addNewRow(rounded: true),
            ),
        ],
      );
    }
    if (!_searching) {
      final letters = widget.minQueryLength == 1 ? 'letter' : 'letters';
      final records = widget.options.length == 1 ? 'record' : 'records';
      return _note(
        'Type at least ${widget.minQueryLength} $letters of the name to '
        'search ${widget.options.length} $records.',
      );
    }
    // The debounce has not fired yet, so the list still belongs to an older
    // query. Say nothing rather than show a stale answer as if it were current.
    if (_appliedQuery != _query) {
      return _note('Searching…');
    }
    if (_matches.isEmpty) {
      // Not an error: the inspector may genuinely be at a new premises.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note('No name contains "$_query".'),
          if (widget.onAddNew != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _addNewRow(rounded: true),
            ),
        ],
      );
    }

    final count = _matches.length;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _listHeight),
            child: ListView.separated(
              // Builder, not a Column: a search can match hundreds of names and
              // only the visible rows should be built.
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, thickness: 1, color: AppColors.border),
              itemBuilder: (context, i) => _row(_matches[i]),
            ),
          ),
          // Offered even when there are matches: "Sunrise Poultry" matching
          // "Sunrise Poultry Farm" does not mean the inspector is at either.
          if (widget.onAddNew != null && !_exactMatch) _addNewRow(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Text(
              _exactMatch
                  ? '$count match${count == 1 ? '' : 'es'}'
                  : '$count match${count == 1 ? '' : 'es'} · or keep '
                      '"$_query" as typed',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(T option) {
    final subtitle = widget.optionSubtitle?.call(option).trim() ?? '';
    return InkWell(
      onTap: () => _choose(option),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.optionLabel(option),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.north_west, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          text,
          style:
              TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.35),
        ),
      );
}
