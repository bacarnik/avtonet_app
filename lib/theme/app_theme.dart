import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// avtonetFinder Principal Design Identity
abstract final class AppTheme {
  // Brand Accents
  static const Color brandPurple = Color(0xFF673AB7);
  static const Color brandPurpleAccent = Color(0xFF7E57C2);

  // Dark Palette (Absolute Slate)
  static const Color darkBackground = Color(0xFF121214);
  static const Color darkSurface = Color(0xFF1A1A1E);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB0B3B8);
  static const Color darkBorder = Color(0xFF2C2C30);

  // Light Palette (Clean Gray)
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF111111);
  static const Color lightTextSecondary = Color(0xFF6C757D);
  static const Color lightBorder = Color(0xFFE0E0E0);

  // RESTORED CONSTANTS for compatibility with external widgets
  static const Color textMuted = darkTextSecondary;
  static const Color darkTextMuted = lightTextSecondary;
  static const Color borderGrey = darkBorder;
  static const Color white = Colors.white;

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: lightBackground,
        surface: lightSurface,
        textPrimary: lightTextPrimary,
        textSecondary: lightTextSecondary,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: darkBackground,
        surface: darkSurface,
        textPrimary: darkTextPrimary,
        textSecondary: darkTextSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isDark = brightness == Brightness.dark;
    final borderColor = isDark ? darkBorder : lightBorder;
    
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandPurple,
        brightness: brightness,
        primary: brandPurple,
        onPrimary: Colors.white,
        secondary: brandPurpleAccent,
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: borderColor,
        surfaceContainerHighest: isDark ? darkSurface : Colors.grey[200]!,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      // REFACTORED: Updated for Material 3 Compatibility (Flutter 3.22+)
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brandPurple, width: 2),
        ),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: textPrimary),
        menuStyle: MenuStyle(
          backgroundColor: MaterialStateProperty.all(surface),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: brandPurple,
        unselectedItemColor: textSecondary,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
      ),
    );
  }
}
