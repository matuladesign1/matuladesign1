import 'package:flutter/material.dart';

/// Palette officielle Matula Design, accordée au logo « Sermons de Branham Matomate ».
class Brand {
  static const deepBlue = Color(0xFF071D45);
  static const royalBlue = Color(0xFF123E78);
  static const lightBlue = Color(0xFF78B7F0);
  static const gold = Color(0xFFE6B63E);
  static const brightYellow = Color(0xFFF6CE69);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF101010);
  static const grey = Color(0xFF858585);

  // Mode sombre « Nuit royale »
  static const nightBg = Color(0xFF07132E);
  static const nightCard = Color(0xFF0F2148);
  static const nightCardHigh = Color(0xFF172D5C);
  static const nightCardHighest = Color(0xFF1F3A72);
  static const nightBar = Color(0xFF0A1838);

  // Mode clair « Parchemin »
  static const parchment = Color(0xFFF7F2E7);
  static const parchmentHigh = Color(0xFFEDE5D3);

  /// Dégradé doré des titres et boutons principaux.
  static const goldGradient = LinearGradient(
    colors: [Color(0xFFF6D57A), Color(0xFFE6B63E), Color(0xFFC8921F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Dégradé de l'en-tête (ciel du logo).
  static const skyGradient = LinearGradient(
    colors: [Color(0xFF0B2A63), Color(0xFF123E78), Color(0xFF07132E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

const readingFont = 'Lora';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? Brand.gold : Brand.royalBlue,
    onPrimary: dark ? const Color(0xFF1E1500) : Brand.white,
    primaryContainer: dark ? const Color(0xFF3B3016) : const Color(0xFFD9E5F7),
    onPrimaryContainer: dark ? Brand.brightYellow : Brand.deepBlue,
    secondary: dark ? Brand.brightYellow : const Color(0xFFB8860B),
    onSecondary: Brand.black,
    secondaryContainer: dark ? const Color(0xFF2A2A1E) : const Color(0xFFFFF0C7),
    onSecondaryContainer: dark ? Brand.brightYellow : const Color(0xFF5C4300),
    tertiary: dark ? Brand.lightBlue : Brand.royalBlue,
    onTertiary: dark ? Brand.black : Brand.white,
    error: const Color(0xFFE5484D),
    onError: Brand.white,
    surface: dark ? Brand.nightBg : Brand.parchment,
    onSurface: dark ? const Color(0xFFF4F1E8) : const Color(0xFF16161A),
    onSurfaceVariant: dark ? const Color(0xFFAFBCD8) : const Color(0xFF5B5A57),
    surfaceContainerLowest: dark ? Brand.nightBg : Brand.white,
    surfaceContainerLow: dark ? const Color(0xFF0B1A3D) : Brand.white,
    surfaceContainer: dark ? Brand.nightCard : Brand.white,
    surfaceContainerHigh: dark ? Brand.nightCardHigh : Brand.parchmentHigh,
    surfaceContainerHighest: dark ? Brand.nightCardHighest : const Color(0xFFE3D9C3),
    outline: dark ? const Color(0xFF2E4A86) : const Color(0xFFCBBF9F),
    outlineVariant: dark ? const Color(0xFF1C3164) : const Color(0xFFE4DBC7),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final heading = TextStyle(fontFamily: readingFont, color: scheme.onSurface, fontWeight: FontWeight.w700);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge!.merge(heading),
      headlineMedium: base.textTheme.headlineMedium!.merge(heading),
      headlineSmall: base.textTheme.headlineSmall!.merge(heading.copyWith(fontWeight: FontWeight.w600)),
      titleLarge: base.textTheme.titleLarge!.merge(heading.copyWith(fontWeight: FontWeight.w600)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? Brand.nightBar : Brand.parchment,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 2,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: TextStyle(
          fontFamily: readingFont, fontSize: 21, fontWeight: FontWeight.w700, color: dark ? Brand.brightYellow : Brand.deepBlue),
      iconTheme: IconThemeData(color: dark ? Brand.brightYellow : Brand.deepBlue),
    ),
    cardTheme: CardTheme(
      color: scheme.surfaceContainer,
      elevation: dark ? 0 : 1,
      shadowColor: Colors.black26,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: dark ? const Color(0xFF1C3164) : const Color(0xFFEAE1CC)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? Brand.nightBar : Brand.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? Brand.gold.withValues(alpha: .22) : const Color(0xFFD9E5F7),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? Brand.nightCardHigh : Brand.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: dark ? const Color(0xFF26407A) : const Color(0xFFE0D5BC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.primary,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.primary : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurfaceVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      secondarySelectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
      checkmarkColor: scheme.onPrimaryContainer,
      iconTheme: IconThemeData(color: scheme.primary, size: 18),
      side: BorderSide(color: scheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    sliderTheme: SliderThemeData(activeTrackColor: scheme.primary, thumbColor: scheme.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Brand.nightCard : Brand.parchment,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: dark ? Brand.nightCard : Brand.parchment,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
    ),
    listTileTheme: ListTileThemeData(iconColor: scheme.primary),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}
