import 'package:flutter/material.dart';

class AstraTheme {
  // Pure OLED Black / Deep Purple Cosmic Palette
  static const Color background = Color(0xFF07060E);
  static const Color backgroundSurface = Color(0xFF0D0B18);
  static const Color cardSurface = Color(0xFF131124);
  static const Color cardSurfaceLight = Color(0xFF1C1936);
  static const Color glassFill = Color(0x6015122B);
  
  // Electric Accents
  static const Color primary = Color(0xFF8B5CF6); // Electric Violet
  static const Color primaryLight = Color(0xFFA78BFA); // Light Lilac
  static const Color secondary = Color(0xFF6366F1); // Cosmic Indigo
  static const Color accentCyan = Color(0xFF38BDF8); // Nebula Cyan
  static const Color accentOnline = Color(0xFF10B981); // Emerald Live
  static const Color accentOffline = Color(0xFF6B7280); // Muted
  static const Color accentDanger = Color(0xFFF43F5E); // Crimson Rose

  // High-Contrast Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Subtle Cosmic Borders & Glows
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderActive = Color(0x608B5CF6);
  static const Color borderGlow = Color(0x35A78BFA);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cosmicBackgroundGradient = LinearGradient(
    colors: [Color(0xFF0D0B18), Color(0xFF07060E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient glassBorderGradient = LinearGradient(
    colors: [
      Color(0x60A78BFA),
      Color(0x206366F1),
      Color(0x05FFFFFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: cardSurface,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardSurfaceLight,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      useMaterial3: true,
    );
  }
}
