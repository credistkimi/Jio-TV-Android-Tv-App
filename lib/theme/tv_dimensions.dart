import 'package:flutter/material.dart';

/// Overscan Safe Zones & TV Physical Dimensions.
class TvDimensions {
  TvDimensions._();

  // Overscan protection: 48dp (5%) margin from screen edges
  static const double overscanMargin = 48.0;
  static const double overscanMarginVertical = 36.0;

  // Focus Ring
  static const double focusBorderWidth = 2.0;
  static const double focusBorderRadius = 12.0;
  static const double focusScaleStandard = 1.02;
  static const double focusScaleLarge = 1.02;
  static const Duration focusAnimationDuration = Duration(milliseconds: 150);
  static const Curve focusAnimationCurve = Curves.easeOutCubic;

  // TV Cards
  static const double channelCardWidth = 240.0;
  static const double channelCardHeight = 150.0;
  static const double categoryPillHeight = 44.0;
  static const double navBarHeight = 56.0;

  // EPG Grid
  static const double epgChannelColumnWidth = 220.0;
  static const double epgMinuteWidth = 8.0; // 8dp per minute (240dp per 30m block)
  static const double epgRowHeight = 84.0;

  // OSD Timeout
  static const Duration osdTimeout = Duration(seconds: 5);
}
