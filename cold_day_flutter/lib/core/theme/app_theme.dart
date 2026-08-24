import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF102A43);
  static const slate = Color(0xFF486581);
  static const primary = Color(0xFF0B7285);
  static const primaryDark = Color(0xFF075985);
  static const accent = Color(0xFFF59E0B);
  static const success = Color(0xFF087F5B);
  static const danger = Color(0xFFB42318);
  static const lightBackground = Color(0xFFF4F7F9);
  static const darkBackground = Color(0xFF0B1724);
  static const darkSurface = Color(0xFF142536);

  static ColorScheme lightScheme() => const ColorScheme.light(
    primary: primary,
    onPrimary: Colors.white,
    secondary: accent,
    onSecondary: ink,
    surface: Colors.white,
    onSurface: ink,
    surfaceContainerHighest: Color(0xFFE6EEF2),
    onSurfaceVariant: slate,
    error: danger,
    onError: Colors.white,
  );

  static ColorScheme darkScheme() => const ColorScheme.dark(
    primary: Color(0xFF67D3E5),
    onPrimary: Color(0xFF073642),
    secondary: Color(0xFFFFC857),
    onSecondary: Color(0xFF3D2A00),
    surface: darkSurface,
    onSurface: Color(0xFFF2F7FA),
    surfaceContainerHighest: Color(0xFF263B4D),
    onSurfaceVariant: Color(0xFFB8CAD6),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
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
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
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
  );
  final outline = scheme.outlineVariant;
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: TextStyle(color: scheme.onSurface, height: 1.35),
      bodyMedium: TextStyle(color: scheme.onSurface, height: 1.35),
      bodySmall: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onPrimary,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: BorderSide(color: scheme.primary, width: 2),
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
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? scheme.surfaceContainerHighest : AppColors.ink,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}
