import 'package:flutter/material.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_typography.dart';

/// Pulsing "🔴 LIVE" status badge.
class TvLiveBadge extends StatefulWidget {
  final double size;

  const TvLiveBadge({super.key, this.size = 12.0});

  @override
  State<TvLiveBadge> createState() => _TvLiveBadgeState();
}

class _TvLiveBadgeState extends State<TvLiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: TvColors.liveRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TvColors.liveRed.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: const BoxDecoration(
                      color: TvColors.liveRed,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: TvColors.liveRed,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TvTypography.badge,
          ),
        ],
      ),
    );
  }
}

/// "⏪ CATCHUP" feature badge.
class TvCatchupBadge extends StatelessWidget {
  const TvCatchupBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TvColors.accentCyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TvColors.accentCyan.withValues(alpha: 0.5), width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '⏪',
            style: TextStyle(fontSize: 11),
          ),
          SizedBox(width: 4),
          Text(
            'CATCHUP',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TvColors.accentCyan,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// "HD" video quality badge.
class TvHdBadge extends StatelessWidget {
  final String label;
  final double fontSize;

  const TvHdBadge({super.key, this.label = 'HD', this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
