import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
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
      if (mounted) setState(() => _open = _focus.hasFocus);
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
    return LabelledField(
      label: widget.label,
      isRequired: widget.isRequired,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
          if (_open) _suggestions(),
        ],
      ),
    );
  }

  Widget _addNewButton() {
    final typed = widget.controller.text.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: typed.isEmpty
              ? null
              : () async {
                  _focus.unfocus();
                  setState(() => _open = false);
                  await widget.onAddNew!(typed);
                },
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            '${widget.addNewLabel ?? 'Add'} "$typed"',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _suggestions() {
    if (widget.options.isEmpty) {
      return _note(
        widget.emptyHint ??
            'No records on this device yet. Sync to download them.',
      );
    }
    if (!_searching) {
      return _note(
        'Type at least ${widget.minQueryLength} letters of the name to '
        'search ${widget.options.length} records.',
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
          if (widget.onAddNew != null) _addNewButton(),
        ],
      );
    }

    final count = _matches.length;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxListHeight),
            child: ListView.separated(
              // Builder, not a Column: a search can match hundreds of names and
              // only the visible rows should be built.
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: count,
              separatorBuilder: (_, __) => Divider(
                  height: 1, thickness: 1, color: AppColors.border),
              itemBuilder: (context, i) => _row(_matches[i]),
            ),
          ),
          // Offered even when there are matches: "Sunrise Poultry" matching
          // "Sunrise Poultry Farm" does not mean the inspector is at either.
          if (widget.onAddNew != null && !_exactMatch) _addNewButton(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
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
                        style: TextStyle(
                            fontSize: 12, color: AppColors.muted),
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
        margin: const EdgeInsets.only(top: 6),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 12.5, color: AppColors.muted, height: 1.35),
        ),
      );
}
