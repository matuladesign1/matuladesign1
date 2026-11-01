import 'package:flutter/material.dart';

/// Palette officielle Matula Design.
class Brand {
  static const deepBlue = Color(0xFF071D45);
  static const royalBlue = Color(0xFF123E78);
  static const lightBlue = Color(0xFF78B7F0);
  static const gold = Color(0xFFE6B63E);
  static const brightYellow = Color(0xFFF6CE69);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF101010);
  static const grey = Color(0xFF858585);

  // Surfaces du mode sombre (inspirées des captures fournies)
  static const darkBg = Color(0xFF0E0E0F);
  static const darkCard = Color(0xFF1E1F21);
  static const darkCardHigh = Color(0xFF2A2B2E);
  // Mode clair
  static const lightBg = Color(0xFFF7F5F0);
}

const readingFont = 'Lora';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? Brand.lightBlue : Brand.deepBlue,
    onPrimary: dark ? Brand.black : Brand.white,
    primaryContainer: dark ? const Color(0xFF26354A) : const Color(0xFFDCE8F7),
    onPrimaryContainer: dark ? Brand.lightBlue : Brand.deepBlue,
    secondary: Brand.gold,
    onSecondary: Brand.black,
    secondaryContainer: dark ? const Color(0xFF3A3122) : const Color(0xFFFFF1CF),
    onSecondaryContainer: dark ? Brand.brightYellow : const Color(0xFF5C4300),
    tertiary: Brand.royalBlue,
    onTertiary: Brand.white,
    error: const Color(0xFFE5484D),
    onError: Brand.white,
    surface: dark ? Brand.darkBg : Brand.lightBg,
    onSurface: dark ? const Color(0xFFF1F1F1) : Brand.black,
    onSurfaceVariant: dark ? const Color(0xFFB4B4B4) : const Color(0xFF5A5A5A),
    surfaceContainerLowest: dark ? Brand.darkBg : Brand.white,
    surfaceContainerLow: dark ? const Color(0xFF161718) : Brand.white,
    surfaceContainer: dark ? Brand.darkCard : Brand.white,
    surfaceContainerHigh: dark ? Brand.darkCardHigh : const Color(0xFFEFECE5),
    surfaceContainerHighest: dark ? const Color(0xFF333438) : const Color(0xFFE6E2D9),
    outline: dark ? const Color(0xFF4A4B4F) : const Color(0xFFCFCAC0),
    outlineVariant: dark ? const Color(0xFF2E2F33) : const Color(0xFFE2DED5),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF1A1B1D) : scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1A1B1D) : Brand.white,
      indicatorColor: dark ? const Color(0xFF2C3440) : const Color(0xFFDCE8F7),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF2A2B2E) : const Color(0xFFEDEAE3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? const Color(0xFF2F6EAF) : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Brand.white : scheme.onSurfaceVariant),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}
