import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/constants.dart';

/// App-wide theme configuration — light and dark.
///
/// Uses the bundled Inter font for modern, premium typography.
/// All components inherit from this unified theme to ensure consistency.
class AppTheme {
  AppTheme._();

  // ─── Color Seeds ────────────────────────────────────────────
  static const Color _seed = AppColors.primary;

  // ─── Light Theme ────────────────────────────────────────────
  static ThemeData get light {
    // Set the family on ThemeData itself as well as the text theme below.
    // This covers component-owned/default styles (for example TextField input
    // text and button labels) that do not always resolve through TextTheme.
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Inter',
    );
    final textTheme = _buildTextTheme(base.textTheme);

    return base.copyWith(
      brightness: Brightness.light,
      primaryColor: _seed,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border.withValues(alpha: 0.5),

      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.teal,
        onSecondary: Colors.white,
        tertiary: AppColors.accent,
        error: AppColors.error,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textDark,
      ),

      textTheme: textTheme,

      // ── AppBar ──────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(fontFamily: 'Inter',
          color: AppColors.textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(
          color: AppColors.textBody,
          size: AppSizes.iconLg,
        ),
      ),

      // ── Elevated Button ────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Outlined Button ────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          elevation: 0,
          minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          side: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Text Button ────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.base, vertical: AppSizes.sm),
          textStyle: const TextStyle(fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Input Fields ───────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.base,
          vertical: AppSizes.base,
        ),
        hintStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.textPlaceholder,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.textLabel,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      // ── Divider ────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: AppColors.border.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // ── Bottom Navigation ──────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.navInactive,
        selectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Dialog ─────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        titleTextStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),

      // ── SnackBar ──────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.secondary,
        contentTextStyle: const TextStyle(fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Chip ──────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surfaceVariant,
        labelStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.textBody,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      ),

      // ── Tab Bar ───────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ─── Dark Theme ─────────────────────────────────────────────
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Inter',
    );
    final textTheme = _buildTextTheme(base.textTheme, isDark: true);

    return base.copyWith(
      brightness: Brightness.dark,
      primaryColor: _seed,
      scaffoldBackgroundColor: AppColors.secondary,
      cardColor: AppColors.secondaryLight,
      dividerColor: Colors.white.withValues(alpha: 0.05),
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: AppColors.secondary,
        secondary: AppColors.teal,
        onSecondary: AppColors.secondary,
        tertiary: AppColors.accent,
        error: AppColors.error,
        onError: Colors.white,
        surface: AppColors.secondaryLight,
        onSurface: Colors.white,
      ),

      textTheme: textTheme,

      // ── AppBar ──────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(
          color: Colors.white70,
          size: AppSizes.iconLg,
        ),
      ),

      // ── Elevated Button ────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.secondary,
          elevation: 0,
          minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Outlined Button ────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          elevation: 0,
          minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Input Fields ───────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.base,
          vertical: AppSizes.base,
        ),
        hintStyle: const TextStyle(fontFamily: 'Inter',
          color: Colors.white24,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(fontFamily: 'Inter',
          color: Colors.white38,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(fontFamily: 'Inter',
          color: AppColors.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
      ),

      // ── Divider ────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.05),
        thickness: 1,
        space: 1,
      ),

      // ── Bottom Navigation ──────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: Colors.white24,
        selectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Dialog ─────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.secondaryLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        titleTextStyle: const TextStyle(fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),

      // ── Tab Bar ───────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryLight,
        unselectedLabelColor: Colors.white38,
        indicatorColor: AppColors.primaryLight,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ─── Text Theme ────────────────────────────────────────────
  static TextTheme _buildTextTheme(TextTheme base, {bool isDark = false}) {
    final Color bodyColor = isDark ? Colors.white70 : AppColors.textBody;
    final Color headColor = isDark ? Colors.white : AppColors.textDark;

    return base.apply(fontFamily: 'Inter').copyWith(
      // Display
      displayLarge: TextStyle(fontFamily: 'Inter',
        fontSize: 56,
        fontWeight: FontWeight.w800,
        color: headColor,
        letterSpacing: -1.5,
        height: 1.1,
      ),
      displayMedium: TextStyle(fontFamily: 'Inter',
        fontSize: 44,
        fontWeight: FontWeight.w800,
        color: headColor,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      displaySmall: TextStyle(fontFamily: 'Inter',
        fontSize: 36,
        fontWeight: FontWeight.w700,
        color: headColor,
        letterSpacing: -0.5,
        height: 1.2,
      ),

      // Headline
      headlineLarge: TextStyle(fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: headColor,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineMedium: TextStyle(fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: headColor,
        height: 1.25,
      ),
      headlineSmall: TextStyle(fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: headColor,
        height: 1.3,
      ),

      // Title
      titleLarge: TextStyle(fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: headColor,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: headColor,
      ),
      titleSmall: TextStyle(fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: headColor,
      ),

      // Body
      bodyLarge: TextStyle(fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        height: 1.5,
      ),
      bodyMedium: TextStyle(fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        height: 1.5,
      ),
      bodySmall: TextStyle(fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        height: 1.5,
      ),

      // Label
      labelLarge: TextStyle(fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(fontFamily: 'Inter',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.1,
      ),
      labelSmall: TextStyle(fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: bodyColor,
        letterSpacing: 0.3,
      ),
    );
  }
}
