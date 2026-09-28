import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'picker_field.dart';
import 'required_label.dart';

/// One option in a picker.
typedef PickerOption<T> = ({T value, String text});

/// A dropdown that drops: the options open in a menu directly under the
/// field, and never above it.
///
/// Material's own `DropdownButton` positions its menu to keep the selected
/// row against the button and then clamps to the screen, so the same picker
/// opened downwards at the top of a form and *upwards* near the foot of
/// it — the inspector could not learn where the list was going to appear.
///
/// This anchors the menu to the bottom of the field and caps its height to
/// the room actually left below, so a long list scrolls inside the menu
/// rather than flipping the menu over. The card is as wide as the field, in
/// the same surface and radius as the rest of the app's pickers.
class PickerMenuField<T> extends StatefulWidget {
  const PickerMenuField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.isRequired = false,
    this.enabled = true,
    this.hint,
    this.helper,
    this.emptyHint,
  });

  final String label;
  final T? value;
  final List<PickerOption<T>> options;
  final ValueChanged<T?> onChanged;
  final bool isRequired;

  /// False while the screen's own order says this step is not open yet.
  final bool enabled;

  /// Stands in for the value while nothing is chosen.
  final String? hint;

  /// A note under the field.
  final String? helper;

  /// Says why the list is empty rather than showing a dead control.
  final String? emptyHint;

  @override
  State<PickerMenuField<T>> createState() => _PickerMenuFieldState<T>();
}

class _PickerMenuFieldState<T> extends State<PickerMenuField<T>> {
  final _link = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _menu;

  /// Held so a pick can clear the "Required" the last validate() put up,
  /// rather than leaving it on a field that has since been answered.
  FormFieldState<T>? _formState;

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  bool get _empty => widget.options.isEmpty;
  bool get _locked => !widget.enabled || _empty;

  String? get _selectedText {
    for (final option in widget.options) {
      if (option.value == widget.value) return option.text;
    }
    return null;
  }

  void _close() {
    _menu?.remove();
    _menu = null;
  }

  /// Room below the field for the menu, less a margin so it never sits
  /// flush against the bottom edge or behind the keyboard.
  double _roomBelow() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final top = box.localToGlobal(Offset(0, box.size.height)).dy;
    return MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        top -
        12;
  }

  /// A menu shorter than this is not worth opening: barely a row and a half
  /// showing, with the rest of the list scrolled out of reach.
  static const _wantedRoom = 220.0;

  Future<void> _open() async {
    if (_menu != null) {
      _close();
      return;
    }
    var context_ = _fieldKey.currentContext;
    if (context_ == null) return;

    // A field near the foot of a long form has no room under it, and a menu
    // that opens downwards from there runs off the bottom of the screen —
    // its options unreachable, with nothing to say they are there. Rather
    // than flip the menu upwards, which is the behaviour this field exists
    // to avoid, the page scrolls until the field has room (FSA, 2026-09-08).
    if (_roomBelow() < _wantedRoom && Scrollable.maybeOf(context_) != null) {
      await Scrollable.ensureVisible(
        context_,
        // Near the top of the viewport, so the whole list fits under it.
        alignment: 0.15,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      // The scroll has to land before the menu can be positioned against
      // where the field ended up.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      context_ = _fieldKey.currentContext;
      // Freshly read after the scroll, but say so for the analyser.
      if (context_ == null || !context_.mounted) return;
    }

    final box = context_.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    final room = _roomBelow();
    // A floor: with a very short gap the menu still opens downwards and
    // scrolls, rather than jumping above the field.
    final maxHeight = room.clamp(160.0, PickerField.menuMaxHeight);

    _menu = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // A tap anywhere else closes it, as a dropdown does.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: Material(
              color: PickerField.menuColour,
              elevation: PickerField.menuElevation,
              borderRadius: BorderRadius.circular(PickerField.menuRadius),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: width,
                  minWidth: width,
                  maxHeight: maxHeight,
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.options.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) {
                    final option = widget.options[i];
                    final selected = option.value == widget.value;
                    return InkWell(
                      onTap: () {
                        _close();
                        _formState?.didChange(option.value);
                        widget.onChanged(option.value);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.text,
                                maxLines: PickerField.itemMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: PickerField.itemStyle.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check,
                                  size: 18, color: AppColors.brandPrimary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_menu!);
  }

  @override
  Widget build(BuildContext context) {
    // A required picker is a form field, not a decoration.
    //
    // The asterisk beside the label is a promise, and the forms keep it by
    // calling `Form.validate()` before they complete a record. A picker that
    // is not a [FormField] is invisible to that call — the inspection
    // completed and uploaded with the grade never chosen, asterisk and all.
    return FormField<T>(
      initialValue: widget.value,
      validator: (_) => widget.isRequired && widget.value == null
          ? 'Required'
          : null,
      builder: (state) {
        _formState = state;
        return _field(context, state);
      },
    );
  }

  Widget _field(BuildContext context, FormFieldState<T> state) {
    final text = _selectedText;
    return LabelledField(
      label: widget.label,
      isRequired: widget.isRequired,
      child: CompositedTransformTarget(
        link: _link,
        child: InkWell(
          key: _fieldKey,
          borderRadius: BorderRadius.circular(PickerField.menuRadius),
          onTap: _locked ? null : _open,
          child: InputDecorator(
            isEmpty: false,
            decoration: PickerField.decoration(
              helperText: _empty ? widget.emptyHint : widget.helper,
            ).copyWith(errorText: state.errorText),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text ??
                        (_locked
                            ? (widget.hint ?? 'Not yet')
                            : (widget.hint ?? 'Select')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      color: text == null ? AppColors.muted : AppColors.ink,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down,
                    color: _locked ? AppColors.border : AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
