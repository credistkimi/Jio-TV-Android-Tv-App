import 'package:flutter/material.dart';

/// TV UI Color Palette conforming to the 10-Foot Design Specification.
/// Deep blacks to prevent eye strain and OLED burn-in in living rooms.
class TvColors {
  TvColors._();

  // Background Canvas & Surfaces
  static const Color bgCanvas = Color(0xFF08090C);
  static const Color bgSurface1 = Color(0xFF12151D);
  static const Color bgSurface2 = Color(0xFF1D2230);
  static const Color bgSurface3 = Color(0xFF282F42);
  static const Color bgOverlay = Color(0xD908090C); // 85% opacity

  // Focus & Highlights
  static const Color focusRing = Color(0xFFFFFFFF);
  static const Color focusRingRed = Color(0xFFE50914);
  static const Color focusGlow = Color(0x730078FF); // 45% Jio Blue Glow
  static const Color focusGlowRed = Color(0x55E50914);
  static const Color focusGlowCyan = Color(0x7300D2FF);

  // Brand & Semantic Accents
  static const Color accentPrimary = Color(0xFF0078FF); // Jio Blue
  static const Color accentCyan = Color(0xFF00D2FF);
  static const Color liveRed = Color(0xFFFF0033); // Pulsing Broadcast Red
  static const Color catchupCyan = Color(0xFF00D2FF);
  static const Color reminderYellow = Color(0xFFFFB300);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF262C3D);
  static const Color borderFocused = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFF1A1F2B);

  // Typography Contrast Levels
  static const Color textPrimary = Color(0xFFFFFFFF); // 100%
  static const Color textSecondary = Color(0xFF9DA3B4); // 70%
  static const Color textMuted = Color(0xFF6B7285); // 50%
  static const Color textDisabled = Color(0xFF4F5568); // 38%
}
