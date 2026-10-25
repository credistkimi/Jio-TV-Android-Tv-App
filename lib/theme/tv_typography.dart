import 'package:flutter/material.dart';
import 'tv_colors.dart';

/// 10-Foot TV Typography Scale.
/// Sizes calibrated for viewing from a 10-foot distance (minimum 14sp, standard body 20sp).
class TvTypography {
  TvTypography._();

  static const TextStyle displayHero = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    color: TvColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const TextStyle screenTitle = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: TvColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionHeading = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: TvColors.textPrimary,
  );

  static const TextStyle cardPrimary = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: TvColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: TvColors.textSecondary,
    height: 1.3,
  );

  static const TextStyle bodyBold = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: TvColors.textPrimary,
  );

  static const TextStyle timeCode = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: TvColors.textSecondary,
  );

  static const TextStyle badge = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );
}
