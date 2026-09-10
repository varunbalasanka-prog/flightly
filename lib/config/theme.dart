import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SkyPulse theming — derived from Stitch "Live Flight Dashboard" designs.
///
/// Dark theme: midnight navy backgrounds, neon green accents, glassmorphic cards.
/// Light theme: clean whites with the same accent palette adapted for readability.
class SkyPulseTheme {
  SkyPulseTheme._();

  // ── Dark Palette (Primary — from Stitch designs) ──

  static const _darkBackground = Color(0xFF0A0F1C);
  static const _darkSurface = Color(0xFF131927);
  static const _darkSurfaceContainer = Color(0xFF1A2035);
  static const _darkSurfaceContainerHigh = Color(0xFF222840);
  static const _darkSurfaceBright = Color(0xFF2A3250);

  static const _primaryGreen = Color(0xFF4ADE80);
  static const _onPrimary = Color(0xFF003314);
  static const _primaryContainer = Color(0xFF004D25);

  static const _secondaryBlue = Color(0xFF60A5FA);
  static const _onSecondary = Color(0xFF00315C);
  static const _secondaryContainer = Color(0xFF004A87);

  static const _tertiaryAmber = Color(0xFFFCD34D);
  static const _onTertiary = Color(0xFF3F2E00);

  static const _error = Color(0xFFEF4444);
  static const _onError = Color(0xFF600004);
  static const _errorContainer = Color(0xFF8C1D18);

  static const _onBackground = Color(0xFFF9FAFB);
  static const _onSurface = Color(0xFFE5E7EB);
  static const _onSurfaceVariant = Color(0xFF9CA3AF);
  static const _outline = Color(0xFF4B5563);
  static const _outlineVariant = Color(0xFF374151);

  // ── Light Palette ──

  static const _lightBackground = Color(0xFFF8FAFC);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceContainer = Color(0xFFF1F5F9);
  static const _lightSurfaceContainerHigh = Color(0xFFE2E8F0);

  static const _lightPrimary = Color(0xFF16A34A);
  static const _lightOnPrimary = Color(0xFFFFFFFF);

  static const _lightSecondary = Color(0xFF2563EB);
  static const _lightError = Color(0xFFDC2626);

  static const _lightOnBackground = Color(0xFF0F172A);
  static const _lightOnSurface = Color(0xFF1E293B);
  static const _lightOnSurfaceVariant = Color(0xFF64748B);
  static const _lightOutline = Color(0xFFCBD5E1);

  // ── Text Theme ──

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    return TextTheme(
      displayLarge: GoogleFonts.inter(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        color: displayColor,
        letterSpacing: -0.5,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 45,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: displayColor,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: bodyColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: bodyColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: bodyColor,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.5,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 1.5,
      ),
    );
  }

  // ── Dark Theme ──

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primaryGreen,
      onPrimary: _onPrimary,
      primaryContainer: _primaryContainer,
      onPrimaryContainer: _primaryGreen,
      secondary: _secondaryBlue,
      onSecondary: _onSecondary,
      secondaryContainer: _secondaryContainer,
      onSecondaryContainer: _secondaryBlue,
      tertiary: _tertiaryAmber,
      onTertiary: _onTertiary,
      error: _error,
      onError: _onError,
      errorContainer: _errorContainer,
      onErrorContainer: _error,
      surface: _darkSurface,
      onSurface: _onSurface,
      onSurfaceVariant: _onSurfaceVariant,
      outline: _outline,
      outlineVariant: _outlineVariant,
      surfaceContainerLowest: _darkBackground,
      surfaceContainerLow: _darkSurface,
      surfaceContainer: _darkSurfaceContainer,
      surfaceContainerHigh: _darkSurfaceContainerHigh,
      surfaceContainerHighest: _darkSurfaceBright,
      surfaceBright: _darkSurfaceBright,
      surfaceDim: _darkBackground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkBackground,
      textTheme: _buildTextTheme(_onSurface, _onBackground),
      appBarTheme: AppBarTheme(
        backgroundColor: _darkBackground,
        foregroundColor: _onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _onBackground,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _outlineVariant.withValues(alpha: 0.3)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        indicatorColor: _primaryGreen.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? _primaryGreen : _onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? _primaryGreen : _onSurfaceVariant,
            size: 24,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceContainerHigh,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _outlineVariant.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryGreen, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(
          color: _onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryGreen,
          foregroundColor: _onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryGreen,
          side: const BorderSide(color: _primaryGreen),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryGreen,
        foregroundColor: _onPrimary,
        elevation: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkSurfaceBright,
        contentTextStyle: GoogleFonts.inter(color: _onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: _outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkSurfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }

  // ── Light Theme ──

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: _lightPrimary,
      onPrimary: _lightOnPrimary,
      primaryContainer: const Color(0xFFDCFCE7),
      onPrimaryContainer: const Color(0xFF14532D),
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDBEAFE),
      onSecondaryContainer: const Color(0xFF1E3A5F),
      tertiary: const Color(0xFFD97706),
      onTertiary: Colors.white,
      error: _lightError,
      onError: Colors.white,
      errorContainer: const Color(0xFFFEE2E2),
      onErrorContainer: const Color(0xFF991B1B),
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightOnSurfaceVariant,
      outline: _lightOutline,
      outlineVariant: const Color(0xFFE2E8F0),
      surfaceContainerLowest: _lightBackground,
      surfaceContainerLow: _lightSurface,
      surfaceContainer: _lightSurfaceContainer,
      surfaceContainerHigh: _lightSurfaceContainerHigh,
      surfaceContainerHighest: const Color(0xFFCBD5E1),
      surfaceBright: Colors.white,
      surfaceDim: const Color(0xFFE2E8F0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightBackground,
      textTheme: _buildTextTheme(_lightOnSurface, _lightOnBackground),
      appBarTheme: AppBarTheme(
        backgroundColor: _lightBackground,
        foregroundColor: _lightOnBackground,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _lightOnBackground,
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _lightOutline.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: _lightPrimary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _lightOutline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _lightPrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: _lightOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: _lightOutline.withValues(alpha: 0.4),
        thickness: 1,
      ),
    );
  }

  // ── Custom Colors (not in ColorScheme) ──

  /// Delay warning amber
  static Color warningColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? _tertiaryAmber
          : const Color(0xFFD97706);

  /// Success / on-time green (same as primary in dark)
  static Color successColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Danger / cancellation red
  static Color dangerColor(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  /// Flight route blue
  static Color routeColor(BuildContext context) =>
      Theme.of(context).colorScheme.secondary;

  /// Glassmorphic card decoration
  static BoxDecoration glassCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? _darkSurfaceContainer.withValues(alpha: 0.85)
          : _lightSurface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}
