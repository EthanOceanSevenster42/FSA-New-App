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
class AppPalette {
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

  /// Called by the app root before each build, from the resolved brightness.
  static void use(Brightness brightness) {
    _current =
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  }

  /// Call-to-action red used on every button across the FSA site.
  /// White text on this measures 4.67:1 — WCAG AA for normal text.
  static const brandRed = Color(0xFFDE2F1B);
  static const brandRedPressed = Color(0xFFB82715);

  /// Logo red, brighter than the CTA red. Reserved for accents on dark.
  static const logoRed = Color(0xFFF0303C);

  /// Logo teal. On white it measures 5.20:1 — WCAG AA.
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
  static const fontFamily = 'Lato';

  static ThemeData build([Brightness brightness = Brightness.light]) {
    // Reads an explicit palette and mutates nothing.
    //
    // It used to set the global palette as a side effect, which broke the
    // moment the app root built both themes: light first, then dark, and the
    // dark call won — so choosing Light left every surface dark. Whoever holds
    // the resolved brightness sets the global; this only describes a theme.
    final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandRed,
      brightness: brightness,
      primary: AppColors.brandRed,
      secondary: AppColors.brandTeal,
      surface: p.surface,
      onSurface: p.ink,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: p.surface,
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: p.ink,
        displayColor: p.ink,
      ),
      // Left to Material, a red-seeded scheme gives a segmented button pale
      // pink fills and near-invisible unselected labels on a dark background.
      // Stated explicitly so both themes are legible.
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
            return states.contains(WidgetState.selected)
                ? Colors.white
                : p.ink;
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
              return AppColors.brandRed.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.brandRedPressed;
            }
            return AppColors.brandRed;
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
