import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Asks the inspector to choose one option, from a sheet at the bottom of the
/// screen.
///
/// Replaces the dropdown menu, which Flutter positions *over* its button — so
/// on a form it always covered the fields above and below it, and read as two
/// screens drawn on top of each other. A sheet is unambiguous: it comes up
/// from the bottom, dims what is behind it, names what is being chosen, and
/// gives every option a full-width row that is easy to hit with a thumb.
Future<T?> showPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) itemLabel,
  T? selected,
  String Function(T)? itemSubtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    // Long lists get the full height and scroll; short ones only take the room
    // they need.
    isScrollControlled: true,
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Grab handle: the usual signal that a sheet can be dragged away.
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.only(
                  bottom: media.padding.bottom + 12,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final isSelected = selected != null && item == selected;
                  final subtitle = itemSubtitle?.call(item);
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    title: Text(
                      itemLabel(item),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight:
                            isSelected ? FontWeight.w900 : FontWeight.w400,
                        color: AppColors.ink,
                      ),
                    ),
                    subtitle: subtitle == null || subtitle.isEmpty
                        ? null
                        : Text(
                            subtitle,
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.muted),
                          ),
                    trailing: isSelected
                        ? const Icon(Icons.check,
                            color: AppColors.brandPrimary, size: 22)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
