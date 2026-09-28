import 'package:flutter/material.dart';

/// Brand palette sampled from foodsafetyacademy.co.za — the Food Safety Agency
/// (Pty) Ltd public site — rather than invented.
///
/// An earlier iteration used #4F0FFF (vivid purple) for its banner and buttons, which
/// appears nowhere in the brand. Its other two colours were closer: #0D8BB5 sat
/// near the logo teal, and MainTextColour #E36159 near the logo red. Those are
/// now replaced with the actual values.
/// One set of colours. Two exist: one for daylight, one for dark.
///
/// The brand reds and teal are identical in both — a logo does not change
/// colour when the sun goes down — so only the surfaces, text and borders
/// differ.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.noticeBackground,
    required this.noticeForeground,
    required this.noticeBorder,
  });

  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color noticeBackground;
  final Color noticeForeground;
  final Color noticeBorder;

  /// A palette is one of two fixed sets, never mixed: switching theme swaps
  /// the whole set, so no per-colour copy or blend is meaningful.
  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < 0.5 || other is! AppPalette ? this : other;

  static const light = AppPalette(
    ink: Color(0xFF1D1D1D),
    inkSoft: Color(0xFF3C3C3C),
    muted: Color(0xFF6D6D6D),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6F6F6),
    border: Color(0xFFDCDCDC),
    noticeBackground: Color(0xFFFFF4E0),
    noticeForeground: Color(0xFF8A5A00),
    noticeBorder: Color(0xFFE8C88A),
  );

  /// Not pure black: an OLED-black sheet under a red button smears badly in
  /// the dark, and inspectors work at night in cold rooms. Charcoal reads
  /// better and is kinder on the eyes.
  static const dark = AppPalette(
    ink: Color(0xFFF2F2F2),
    inkSoft: Color(0xFFD8D8D8),
    muted: Color(0xFF9C9C9C),
    surface: Color(0xFF171717),
    surfaceAlt: Color(0xFF242424),
    border: Color(0xFF3A3A3A),
    // The notice keeps its meaning — informational, not alarming — but has to
    // sit on a dark card without glowing.
    noticeBackground: Color(0xFF3A2E12),
    noticeForeground: Color(0xFFE8C27A),
    noticeBorder: Color(0xFF5C4A20),
  );
}

/// The palette in force.
///
/// Deliberately read through static getters rather than context: the app has
/// several hundred references to these colours, many inside widgets built
/// without a BuildContext to hand. Changing the theme rebuilds the whole app
/// from [FsaApp], which sets [current] first, so a frame is never drawn with a
/// palette that does not match the ThemeData around it.
abstract final class AppColors {
  static AppPalette _current = AppPalette.light;

  static AppPalette get current => _current;

  /// The palette of the theme actually around [context].
  ///
  /// Use this from widgets built with `const` — a section heading, a field
  /// label. Those are never rebuilt just because their parent was, so read
  /// through the static getters they kept the palette in force when they were
  /// first built: the handset switching from dark mode to light at sunrise
  /// left "AT A GLANCE" in the dark theme's white on a white page. Reading
  /// through the theme registers a dependency, and the theme changing rebuilds
  /// them.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? _current;

  /// Called by the app root before each build, from the resolved brightness.
  static void use(Brightness brightness) {
    _current =
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  }

  /// The colour the app is built around — the logo's teal. White text on it
  /// measures 5.20:1, past the 4.5:1 AA figure, so a filled button reads at
  /// arm's length in a cold room under warehouse lighting.
  static const brandPrimary = Color(0xFF007890);
  static const brandPrimaryPressed = Color(0xFF005E71);

  /// Occurrence reports carry their own colour.
  ///
  /// An occurrence is not an inspection — nothing was graded and nothing is
  /// billed — so the document and the report that makes it are marked out
  /// from the teal the inspection flow uses. White on it measures 4.6:1.
  static const brandOrange = Color(0xFFB35309);
  static const brandOrangePressed = Color(0xFF8C4107);

  /// The exact red of the Food Safety Agency logo, sampled from
  /// foodsafetyagency.co.za's own artwork.
  ///
  /// Kept for the things red actually means — a required field, a product
  /// that failed, a direction served — rather than as the app's accent.
  static const brandRed = Color(0xFFEC343C);
  static const brandRedPressed = Color(0xFFC42630);

  /// Same red; kept as a separate name where accents on dark use it.
  static const logoRed = Color(0xFFEC343C);

  /// The exact teal of the logo. On white it measures 5.20:1 — WCAG AA.
  static const brandTeal = Color(0xFF007890);

  static Color get ink => _current.ink;
  static Color get inkSoft => _current.inkSoft;
  static Color get muted => _current.muted;
  static Color get surface => _current.surface;
  static Color get surfaceAlt => _current.surfaceAlt;
  static Color get border => _current.border;
  static Color get noticeBackground => _current.noticeBackground;
  static Color get noticeForeground => _current.noticeForeground;
  static Color get noticeBorder => _current.noticeBorder;
}

abstract final class AppTheme {
  /// The app is set in Poppins; the printed forms stay in Lato.
  static const fontFamily = 'Poppins';

  static ThemeData build([Brightness brightness = Brightness.light]) {
    // Reads an explicit palette and mutates nothing.
    //
    // It used to set the global palette as a side effect, which broke the
    // moment the app root built both themes: light first, then dark, and the
    // dark call won — so choosing Light left every surface dark. Whoever holds
    // the resolved brightness sets the global; this only describes a theme.
    final p =
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

    // A red seed hands Material 3 a family of pale pinks for its "container"
    // roles — chip fills, switch tracks, tonal buttons, checked boxes. None
    // of that is FSA's: selections read in the logo's teal, red is kept for
    // what is wrong, and the pinks are replaced wholesale here.
    final dark = brightness == Brightness.dark;
    final tealContainer =
        dark ? const Color(0xFF0E3A44) : const Color(0xFFDDEEF1);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandPrimary,
      brightness: brightness,
      primary: AppColors.brandPrimary,
      onPrimary: Colors.white,
      primaryContainer: tealContainer,
      onPrimaryContainer: dark ? Colors.white : AppColors.brandTeal,
      secondary: AppColors.brandTeal,
      onSecondary: Colors.white,
      secondaryContainer: tealContainer,
      onSecondaryContainer: dark ? Colors.white : AppColors.brandTeal,
      tertiary: AppColors.brandTeal,
      onTertiary: Colors.white,
      tertiaryContainer: tealContainer,
      onTertiaryContainer: dark ? Colors.white : AppColors.brandTeal,
      surface: p.surface,
      onSurface: p.ink,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.surface,
      // Material 3 washes elevated surfaces with the seed colour, and a red
      // seed turns every dialog and sheet a salmon-pink. Dialogs stay on the
      // plain surface instead.
      // The pickers are dialogs too, and Material 3 washes them with the seed
      // colour — a red seed made the clock and calendar salmon pink. Plain
      // surfaces, the brand red only where something is selected.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        dialBackgroundColor: p.surfaceAlt,
        dialHandColor: AppColors.brandPrimary,
        dialTextColor: p.ink,
        hourMinuteColor: p.surfaceAlt,
        hourMinuteTextColor: p.ink,
        // The AM/PM choice: the chosen half of the day in brand red.
        dayPeriodColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.brandPrimary
                : p.surfaceAlt),
        dayPeriodTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : p.ink),
        dayPeriodBorderSide: BorderSide(color: p.border),
        entryModeIconColor: AppColors.brandTeal,
        helpTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: p.muted,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      // Cards catch the same red-seed wash and come out salmon-pink.
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      // The same red-seed wash reaches the app bar when content scrolls
      // under it, tinting the header pink. Keep it on the plain surface.
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      // The date picker has its own theme channel, so the dialog fix above
      // does not reach it — left alone it comes out pink from the red seed,
      // and its header ellipsises a long field name. Plain surface, and a
      // header size that fits "Best Before/Best Quality Before Date".
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.surface,
        headerForegroundColor: p.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        headerHelpStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: p.ink,
        displayColor: p.ink,
      ),
      // Left to Material, a red-seeded scheme gives a segmented button pale
      // pink fills and near-invisible unselected labels on a dark background.
      // Stated explicitly so both themes are legible.
      // Choice chips: plain until chosen, then the brand teal with white text.
      // (A chip that means "bad" asks for red explicitly where it is built.)
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceAlt,
        selectedColor: AppColors.brandTeal,
        disabledColor: p.surfaceAlt,
        checkmarkColor: Colors.white,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.white : p.ink),
        ),
        showCheckmark: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : p.muted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.brandTeal
                : p.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.brandTeal
                : p.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.brandTeal
                : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: p.muted, width: 1.6),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.brandTeal
                : p.muted),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.brandTeal
                : p.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected) ? Colors.white : p.ink;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        // 56dp tall fields: usable with gloves and in direct sun.
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: TextStyle(
          color: p.muted,
          fontFamily: fontFamily,
        ),
        prefixIconColor: p.muted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandTeal, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.brandPrimary.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.brandPrimaryPressed;
            }
            return AppColors.brandPrimary;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.brandTeal),
          minimumSize: WidgetStatePropertyAll(Size(0, 48)),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
