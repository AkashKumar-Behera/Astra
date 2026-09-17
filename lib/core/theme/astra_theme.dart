import 'package:flutter/material.dart';

class AstraTheme {
  // Cosmic Palette Colors
  static const Color background = Color(0xFF070714);
  static const Color backgroundSurface = Color(0xFF0E0E22);
  static const Color cardSurface = Color(0xFF14132B);
  static const Color cardSurfaceLight = Color(0xFF1D1B3E);
  
  // Accents
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryLight = Color(0xFF8C7DFF);
  static const Color secondary = Color(0xFF5352ED);
  static const Color accentCyan = Color(0xFF00D2D3);
  static const Color accentOnline = Color(0xFF2ED573);
  static const Color accentOffline = Color(0xFF747D8C);
  static const Color accentDanger = Color(0xFFFF4757);

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F2F6);
  static const Color textSecondary = Color(0xFFA4B0BE);
  static const Color textMuted = Color(0xFF57606F);

  // Border & Glow
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderActive = Color(0x406C5CE7);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: cardSurface,
      ),
      useMaterial3: true,
    );
  }
}
