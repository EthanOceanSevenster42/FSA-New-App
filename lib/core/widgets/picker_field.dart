import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How every picker in the app looks and behaves, in one place.
///
/// The options drop over the field as a menu — the control the poultry
/// grading screen has always used and the one the Agency asked for
/// everywhere. Three screens had grown three versions of this; sharing the
/// pieces is what stops them drifting apart again.
abstract final class PickerField {
  /// The closed field. No arrow here: a dropdown draws its own.
  static InputDecoration decoration({
    String? helperText,
    String? errorText,
  }) =>
      InputDecoration(
        // Height, fill and borders come from the theme, so a picker sits at
        // the same height as the text fields around it.
        errorText: errorText,
        helperText: helperText,
        helperMaxLines: 2,
      );

  /// The open menu: a card, not a full-bleed sheet. Left at the theme
  /// default it paints in the page's own colour, so in dark mode its edges
  /// vanish and the options read as loose text in the screen corners.
  static Color get menuColour => AppColors.surfaceAlt;
  static const menuRadius = 12.0;
  static const menuElevation = 4.0;

  /// Long lists stay usable: 26 class designations in an unbounded menu
  /// cover the screen and lose the field they belong to.
  static const menuMaxHeight = 360.0;

  /// An option in the open menu. Two lines rather than one: several
  /// designations and every direction remark are longer than a handset is
  /// wide, and an ellipsis in the menu hides which option is being chosen.
  static const itemStyle = TextStyle(fontSize: 15.5);
  static const itemMaxLines = 2;
}
