import 'package:flutter/material.dart';

/// Monochrome sage + ink palette derived from `reference.png`.
///
/// Direction: soft sage-mist background, pure white cards, and a near-black
/// green-tinted ink as the primary action color (buttons, selected navigation,
/// links). No chromatic brand accent; the composition is intentionally calm.
abstract final class AppColors {
  // Ink / neutral text
  static const ink = Color(0xFF1A211F);
  static const slate = Color(0xFF3F4A46);

  // Action primary: near-black green-tinted ink
  static const primary = Color(0xFF262D2A);
  static const primaryContainer = Color(0xFFDCECE7);
  static const onPrimaryContainer = Color(0xFF1A211F);

  // Secondary: muted sage for status/highlights
  static const secondary = Color(0xFF3E5B50);
  static const secondaryContainer = Color(0xFFD6E8E0);
  static const onSecondaryContainer = Color(0xFF14211B);

  // Tertiary: soft grey-green for completed/verified states
  static const tertiary = Color(0xFF003912);
  static const tertiaryContainer = Color(0xFF00B048);

  // Semantic
  static const danger = Color(0xFFBA1A1A);
  static const success = Color(0xFF003912);
  static const successContainer = Color(0xFF00B048);

  // Surfaces — sage-mist scaffold + pure white cards
  static const sageMist = Color(0xFFCAD7D7);
  static const lightBackground = Color(0xFFDCE7E4);
  static const darkBackground = Color(0xFF11151A);
  static const darkSurface = Color(0xFF161B1F);
  static const white = Color(0xFFFFFFFF);

  static ColorScheme lightScheme() => const ColorScheme.light(
    primary: primary,
    onPrimary: white,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: secondary,
    onSecondary: white,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: Color(0xFF33403A),
    onTertiary: white,
    tertiaryContainer: Color(0xFFD3E2DB),
    onTertiaryContainer: Color(0xFF141D18),
    surface: white,
    onSurface: ink,
    surfaceContainerLowest: white,
    surfaceContainerLow: Color(0xFFEDF2F0),
    surfaceContainer: Color(0xFFF2F6F4),
    surfaceContainerHigh: Color(0xFFE8ECE9),
    surfaceContainerHighest: Color(0xFFE0E6E2),
    onSurfaceVariant: slate,
    outline: Color(0xFF6E7C75),
    outlineVariant: Color(0xFFC0CCC6),
    error: danger,
    errorContainer: Color(0xFFFFDAD6),
    onError: white,
    onErrorContainer: Color(0xFF93000A),
  );

  static ColorScheme darkScheme() => const ColorScheme.dark(
    primary: Color(0xFFD3E2DB),
    onPrimary: Color(0xFF1A211F),
    primaryContainer: Color(0xFF33403A),
    onPrimaryContainer: Color(0xFFEAF2EE),
    secondary: Color(0xFF8FB9A9),
    onSecondary: Color(0xFF102016),
    secondaryContainer: Color(0xFF2C4238),
    onSecondaryContainer: Color(0xFFC7DDD3),
    tertiary: Color(0xFF7FC094),
    onTertiary: Color(0xFF003912),
    tertiaryContainer: Color(0xFF00531E),
    onTertiaryContainer: Color(0xFF69FF87),
    surface: darkSurface,
    onSurface: Color(0xFFE6EFEC),
    surfaceContainerLowest: Color(0xFF101417),
    surfaceContainerLow: Color(0xFF1E252A),
    surfaceContainer: Color(0xFF222A2E),
    surfaceContainerHigh: Color(0xFF2C3438),
    surfaceContainerHighest: Color(0xFF383F43),
    onSurfaceVariant: Color(0xFFB5C6C0),
    outline: Color(0xFF7F8F87),
    outlineVariant: Color(0xFF3D4A45),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
  );
}

abstract final class AppSpacing {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark ? AppColors.darkScheme() : AppColors.lightScheme();
  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground,
    useMaterial3: true,
    fontFamily:
        null, // Inter is not bundled; Flutter's platform sans fallback is intentional.
  );
  final outline = scheme.outlineVariant;
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: TextStyle(color: scheme.onSurface, fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        height: 1.43,
      ),
      bodySmall: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.43,
      ),
      headlineLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.29,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
      centerTitle: false,
      scrolledUnderElevation: 2,
      surfaceTintColor: scheme.surface,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: outline.withValues(alpha: 0.35)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.45)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        side: BorderSide(color: scheme.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surface,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 6,
      selectedIconTheme: IconThemeData(color: scheme.primary, size: 24),
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      showUnselectedLabels: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? scheme.surfaceContainerHighest : AppColors.ink,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}
