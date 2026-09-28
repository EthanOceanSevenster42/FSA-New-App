import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'picker_menu_field.dart';

/// Restricted particulars, added from a dropdown and listed as chips.
///
/// The same menu every other picker on the form drops — not a sheet sliding
/// up from the bottom, which read as a different control from the field
/// above it. Picking one appends it to [selected] and the menu resets, so the
/// next particular is one tap away; the chips show what has been named and
/// take a particular off again.
///
/// The menu is the same on every form: this form's own list, then every
/// other commodity's ([shared]), then the typing entry. A pick from the
/// form's own list is kept by its id; one from another list has no id on
/// this record and is kept as text, the way a typed-in one is.
///
/// A particular no list has can be typed in from the last entry of the
/// menu. It is recorded on this inspection alone: the lists every
/// inspector picks from are the Agency's, kept at the office, and a word
/// one inspector met on one label is not a reason to change them. Typed
/// ones sit among the chips with a pencil, so a reader can tell which were
/// chosen and which were written.
class RestrictedParticularsPicker<T> extends StatelessWidget {
  const RestrictedParticularsPicker({
    super.key,
    required this.options,
    required this.optionId,
    required this.optionLabel,
    required this.selected,
    required this.onChanged,
    this.typed,
    this.shared = const [],
    this.onDuplicate,
    this.label = 'Restricted Particulars',
    this.hint = 'Add restricted particular',
    this.note,
  });

  final List<T> options;
  final int Function(T) optionId;
  final String Function(T) optionLabel;

  /// Names from the office's other lists, offered after this form's own so
  /// every form has the same menu. One that matches an option by name is
  /// that option; any other is kept in [typed], so it needs [typed] to be
  /// given, and is left off the menu otherwise.
  final List<String> shared;

  /// The ids named so far. Mutated in place, then [onChanged] is called.
  final Set<int> selected;
  final VoidCallback onChanged;

  /// Particulars typed in because the list did not have them. Mutated in
  /// place like [selected]. Left null, the menu offers no way to type one.
  final Set<String>? typed;

  /// Called instead of adding when the pick is already listed. Left null, a
  /// duplicate is simply ignored.
  final Future<void> Function()? onDuplicate;

  final String label;
  final String hint;
  final String? note;

  /// The menu entry that opens the typing box. No office row has this id.
  static const typeItIn = -1;
  static const typeItInLabel = 'Not on the list — type it in';

  /// Menu values for [shared] names count down from here; no office row
  /// has one of these either.
  static const _sharedBase = -2;

  /// The shared names this form's own list does not already have, once
  /// each, in the order given.
  List<String> get _extras {
    if (typed == null) return const [];
    final kept = <String>[];
    for (final name in shared) {
      if (name.trim().isEmpty) continue;
      if (options.any((o) => _same(optionLabel(o), name))) continue;
      if (kept.any((k) => _same(k, name))) continue;
      kept.add(name.trim());
    }
    return kept;
  }

  Future<void> _add(int id) async {
    if (selected.contains(id)) {
      // The same one twice says nothing twice.
      await onDuplicate?.call();
      onChanged();
      return;
    }
    selected.add(id);
    onChanged();
  }

  /// Takes a name, typed or picked off another list: the listed option
  /// when it is one, otherwise text on this record.
  Future<void> _take(String text) async {
    // The same as one the list has: that is the listed one, not a second
    // spelling of it.
    for (final option in options) {
      if (_same(optionLabel(option), text)) {
        await _add(optionId(option));
        return;
      }
    }
    if (typed!.any((t) => _same(t, text))) {
      await onDuplicate?.call();
      onChanged();
      return;
    }
    typed!.add(text);
    onChanged();
  }

  Future<void> _typeOne(BuildContext context) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _TypeParticularDialog(),
    );
    if (text == null || text.isEmpty) return;
    await _take(text);
  }

  static bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final typed = this.typed ?? const <String>{};
    final extras = _extras;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              note!,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.muted, height: 1.35),
            ),
          ),
        // The list opens as a sheet, like every other picker: a Material
        // menu placed itself against the field and flipped upwards near the
        // foot of a form, so the same control behaved differently depending
        // on how far down the page it had been scrolled.
        PickerMenuField<int>(
          label: label,
          // Nothing stays selected: each pick adds a chip below and the
          // field returns to its hint, ready for the next one.
          value: null,
          hint: hint,
          options: [
            for (final option in options)
              (value: optionId(option), text: optionLabel(option)),
            for (var n = 0; n < extras.length; n++)
              (value: _sharedBase - n, text: extras[n]),
            if (this.typed != null) (value: typeItIn, text: typeItInLabel),
          ],
          emptyHint: 'Nothing to choose from yet',
          onChanged: (id) async {
            if (id == null) return;
            if (id == typeItIn) {
              await _typeOne(context);
              return;
            }
            if (id <= _sharedBase) {
              await _take(extras[_sharedBase - id]);
              return;
            }
            await _add(id);
          },
        ),
        if (selected.isNotEmpty || typed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in options)
                  if (selected.contains(optionId(option)))
                    InputChip(
                      label: Text(optionLabel(option),
                          style: const TextStyle(fontSize: 13)),
                      onDeleted: () {
                        selected.remove(optionId(option));
                        onChanged();
                      },
                    ),
                for (final text in typed)
                  InputChip(
                    // The pencil marks one that was written in; a pick off
                    // another commodity's list was chosen like any other.
                    avatar: extras.any((e) => _same(e, text))
                        ? null
                        : const Icon(Icons.edit_outlined, size: 16),
                    label: Text(text, style: const TextStyle(fontSize: 13)),
                    onDeleted: () {
                      this.typed!.remove(text);
                      onChanged();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// How typed-in particulars are kept on a record: one per line, in the
/// same text column the forms already have for them. A line each because
/// the typing box is a single line, so nothing an inspector writes can be
/// mistaken for two.
abstract final class TypedParticulars {
  static String pack(Iterable<String> typed) => typed.join('\n');

  static Set<String> unpack(String stored) => {
        for (final line in stored.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      };
}

class _TypeParticularDialog extends StatefulWidget {
  const _TypeParticularDialog();

  @override
  State<_TypeParticularDialog> createState() => _TypeParticularDialogState();
}

class _TypeParticularDialogState extends State<_TypeParticularDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restricted particular'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'As it appears on the label',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          Text(
            'Recorded on this inspection only. The list the inspectors '
            'choose from is not changed.',
            style: TextStyle(
                fontSize: 12.5, color: AppColors.muted, height: 1.35),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
