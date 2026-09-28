import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

/// Takes an inspector to the required field they skipped, and marks it red.
///
/// A form used to stop a save with one line at the foot of the screen —
/// "Answer X, Y before completing this inspection" — and leave the inspector
/// to hunt a long page for X. Now the save calls [flag] with the missing
/// fields in page order; the page scrolls to the first one and every missing
/// field shows red until it is filled in.
///
/// Why the forms name their missing fields rather than relying on
/// `Form.validate()` alone: the forms are lazy lists, so a field scrolled off
/// screen is not built and `validate()` never sees it. Each field is wrapped
/// in a [MissingFieldAnchor] instead, which remembers where it last sat in the
/// list, so it can be scrolled back to even while unbuilt.
class MissingFields extends ChangeNotifier {
  final _keys = <String, GlobalKey>{};
  final _offsets = <String, double>{};

  /// The list the fields were last seen in, for when none is built now —
  /// every flagged field scrolled out of the list's build range.
  ScrollableState? _lastScrollable;
  Set<String> _flagged = const {};
  bool Function(String id)? _stillMissing;

  /// Every field flagged by the last failed save.
  Set<String> get flagged => _flagged;

  /// Whether [id] was flagged and has still not been filled in.
  ///
  /// Asked on every rebuild, so a field turns back from red the moment it is
  /// answered rather than at the next save.
  bool isMissing(String id) =>
      _flagged.contains(id) && (_stillMissing?.call(id) ?? true);

  GlobalKey _keyFor(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'missing:$id'));

  /// Marks [ids] red and scrolls to the first of them.
  ///
  /// [ids] must be in page order: the first is the one the inspector is taken
  /// to. [stillMissing] re-checks a field as the form changes, so its red goes
  /// as soon as it is answered; without it the red stays until the next
  /// [flag] or [clear].
  Future<void> flag(
    BuildContext context,
    List<String> ids, {
    bool Function(String id)? stillMissing,
  }) async {
    _flagged = ids.toSet();
    _stillMissing = stillMissing;
    notifyListeners();
    if (ids.isEmpty) return;
    await reveal(context, ids.first);
  }

  /// Removes every red mark, for a save that went through.
  void clear() {
    if (_flagged.isEmpty) return;
    _flagged = const {};
    _stillMissing = null;
    notifyListeners();
  }

  /// Scrolls the field [id] into view.
  ///
  /// [context] is any context inside the form's scrollable, used when the field
  /// itself has never been built and so has no position of its own yet.
  Future<void> reveal(BuildContext context, String id) async {
    // Found once, up front: the field that led to it may itself scroll out
    // of the list's build range on the first jump.
    ScrollableState? scrollable;
    for (var attempt = 0; attempt < 40; attempt++) {
      final target = _keys[id]?.currentContext;
      if (target != null && target.mounted) {
        // Only the form's own list. `Scrollable.ensureVisible` would also
        // scroll every scrollable around it — the fruit & veg step PageView
        // among them, which it nudged sideways off the step.
        final list = Scrollable.maybeOf(target, axis: Axis.vertical);
        final box = target.findRenderObject();
        if (list == null || box == null) return;
        await list.position.ensureVisible(
          box,
          alignment: 0.15,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        return;
      }

      scrollable ??= _scrollableFor(context);
      if (scrollable == null || !scrollable.mounted) return;
      final position = scrollable.position;

      // Unbuilt: jump to where it was last seen, or — never seen — walk down
      // a screen at a time until the list builds it. A lazy list builds from
      // the top, so a field never seen lies below what has been.
      final known = _offsets[id];
      final double next;
      if (known != null && attempt == 0) {
        next = known;
      } else {
        if (position.pixels >= position.maxScrollExtent) return;
        next = position.pixels + position.viewportDimension * 0.8;
      }
      position.jumpTo(
        next.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
    }
  }

  /// The list the fields sit in. Found through any field that is built, since
  /// a page's own context is usually above its list rather than inside it.
  ScrollableState? _scrollableFor(BuildContext fallback) {
    for (final key in _keys.values) {
      final c = key.currentContext;
      if (c != null && c.mounted) {
        final s = Scrollable.maybeOf(c, axis: Axis.vertical);
        if (s != null) return s;
      }
    }
    final last = _lastScrollable;
    if (last != null && last.mounted) return last;
    return fallback.mounted
        ? Scrollable.maybeOf(fallback, axis: Axis.vertical)
        : null;
  }

  void _remember(String id, BuildContext context) {
    final box = context.findRenderObject();
    if (box == null || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    _offsets[id] = viewport.getOffsetToReveal(box, 0.15).offset;
    _lastScrollable =
        Scrollable.maybeOf(context, axis: Axis.vertical) ?? _lastScrollable;
  }
}

/// Wraps one required field so [MissingFields] can find it and mark it red.
///
/// Inputs that draw their own box — the shared text, picker and date fields —
/// turn their own border red by reading [MissingFieldScope]. Anything else
/// (a photo grid, a signature, a slider) is given a red outline here; pass
/// `framed: false` for the former so the field is not boxed twice.
class MissingFieldAnchor extends StatelessWidget {
  const MissingFieldAnchor({
    super.key,
    required this.fields,
    required this.id,
    required this.child,
    this.framed = true,
    this.listenable,
    this.message = 'Required',
  });

  final MissingFields fields;
  final String id;
  final Widget child;

  /// Whether to draw the red outline here, rather than leave it to the input.
  final bool framed;

  /// Rebuilds the mark when this changes, e.g. the field's text controller,
  /// for inputs that do not rebuild the form as they are typed into.
  final Listenable? listenable;

  /// Shown under an outlined field while it is missing.
  final String message;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([fields, if (listenable != null) listenable]),
        builder: (context, _) {
          final missing = fields.isMissing(id);
          return KeyedSubtree(
            key: fields._keyFor(id),
            child: _PositionRecorder(
              onLaidOut: (c) => fields._remember(id, c),
              child: MissingFieldScope(
                missing: missing,
                child: framed && missing ? _outlined(child) : child,
              ),
            ),
          );
        },
      );

  Widget _outlined(Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.brandRed, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(padding: const EdgeInsets.all(6), child: child),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 8),
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.brandRed,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

/// Tells an input inside a [MissingFieldAnchor] that it is missing, so it can
/// draw its own border red instead of being outlined.
class MissingFieldScope extends InheritedWidget {
  const MissingFieldScope({
    super.key,
    required this.missing,
    required super.child,
  });

  final bool missing;

  /// The error text an input should show: 'Required' while missing, else null.
  static String? errorOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MissingFieldScope>()?.missing ==
              true
          ? 'Required'
          : null;

  @override
  bool updateShouldNotify(MissingFieldScope oldWidget) =>
      missing != oldWidget.missing;
}

/// Reports its position after each layout, so an anchor scrolled off screen
/// still knows where to be scrolled back to.
class _PositionRecorder extends StatefulWidget {
  const _PositionRecorder({required this.onLaidOut, required this.child});

  final void Function(BuildContext context) onLaidOut;
  final Widget child;

  @override
  State<_PositionRecorder> createState() => _PositionRecorderState();
}

class _PositionRecorderState extends State<_PositionRecorder> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLaidOut(context);
    });
    return widget.child;
  }
}
