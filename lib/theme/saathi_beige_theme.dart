import 'package:flutter/material.dart';

/// Warm beige / sand palette for premium voice-first UI.
abstract final class SaathiBeige {
  static const Color cream = Color(0xFFF5F1EB);
  static const Color sand = Color(0xFFEAE3D9);
  static const Color charcoal = Color(0xFF2D2A26);
  static const Color muted = Color(0xFF6B6560);
  static const Color accent = Color(0xFFC4A574);
  static const Color accentDeep = Color(0xFF9A7B4F);
  static const Color surface = Color(0xFFF0EBE3);
  static const Color surfaceElevated = Color(0xFFFAF7F2);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cream, sand],
  );

  static ThemeData lightTheme() {
    final base = ColorScheme.light(
      primary: accentDeep,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: charcoal,
      surface: surface,
      onSurface: charcoal,
      surfaceContainerHighest: surfaceElevated,
      onSurfaceVariant: muted,
      outline: Color(0xFFD4CBC0),
      shadow: Color(0x1A2D2A26),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: Typography.blackMountainView
          .apply(
            bodyColor: charcoal,
            displayColor: charcoal,
          ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceElevated.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        shadowColor: const Color(0x142D2A26),
      ),
    );
  }
}
