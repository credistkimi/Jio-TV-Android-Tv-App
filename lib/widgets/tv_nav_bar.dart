import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../theme/tv_colors.dart';
import 'tv_focusable.dart';

enum TvNavDestination {
  liveGuide, // For You
  epgGrid,   // Digital TV
  catchup,   // Catch Up TV
  favorites, // Favorites
  movies,    // Retained for category filter navigation
  shows,
  kids,
  music,
  sports,
  search,    // Search
  account,   // Account & Settings
  auth,      // Login
}

class TvNavBar extends StatefulWidget {
  final TvNavDestination currentDestination;
  final ValueChanged<TvNavDestination> onDestinationSelected;
  final VoidCallback? onQuickSwitchLiveTv;
  final VoidCallback? onOpenSearch;

  const TvNavBar({
    super.key,
    required this.currentDestination,
    required this.onDestinationSelected,
    this.onQuickSwitchLiveTv,
    this.onOpenSearch,
  });

  @override
  State<TvNavBar> createState() => _TvNavBarState();
}

class _TvNavBarState extends State<TvNavBar> {
  late Timer _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updateClock());
  }

  void _updateClock() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('hh:mm a').format(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Jio tv+ Brand Logo (Image 1 reference)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE50914), Color(0xFFC70000)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Jio',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      ' tv+',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // 2. Red YouTube / LiveTV Quick Switcher Button with Tooltip (Image 1 reference)
          TvFocusable(
            onPressed: widget.onQuickSwitchLiveTv ?? () => widget.onDestinationSelected(TvNavDestination.liveGuide),
            borderRadius: BorderRadius.circular(20),
            backgroundColor: const Color(0xFFE50914),
            padding: const EdgeInsets.all(8),
            child: const Tooltip(
              message: 'Switch to LiveTV in One click',
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedPlay,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Search Icon Button (Image 1 reference)
          TvFocusable(
            onPressed: widget.onOpenSearch ?? () => widget.onDestinationSelected(TvNavDestination.search),
            borderRadius: BorderRadius.circular(20),
            backgroundColor: widget.currentDestination == TvNavDestination.search
                ? TvColors.accentCyan.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(8),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedSearch01,
              color: widget.currentDestination == TvNavDestination.search
                  ? TvColors.accentCyan
                  : Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),

          // 4. Horizontal Scrollable Navigation Pills (Image 1 reference)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildNavPill(
                    destination: TvNavDestination.liveGuide,
                    label: 'For You',
                  ),
                  const SizedBox(width: 8),
                  _buildNavPill(
                    destination: TvNavDestination.epgGrid,
                    label: 'Digital TV',
                  ),
                  const SizedBox(width: 8),
                  _buildNavPill(
                    destination: TvNavDestination.catchup,
                    label: 'Catch Up TV',
                  ),
                  const SizedBox(width: 8),
                  _buildNavPill(
                    destination: TvNavDestination.favorites,
                    label: 'Favorites',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 5. Right Icons: Notification Bell, Account/Settings & Clock (Image 1 reference)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Bell
              TvFocusable(
                onPressed: () {},
                borderRadius: BorderRadius.circular(20),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(8),
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedNotification01,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),

              // Settings / Account
              TvFocusable(
                onPressed: () => widget.onDestinationSelected(TvNavDestination.account),
                borderRadius: BorderRadius.circular(20),
                backgroundColor: widget.currentDestination == TvNavDestination.account
                    ? TvColors.accentCyan.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(8),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedSettings02,
                  color: widget.currentDestination == TvNavDestination.account
                      ? TvColors.accentCyan
                      : Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),

              // Digital Clock
              Text(
                _currentTime,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: TvColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavPill({
    required TvNavDestination destination,
    required String label,
  }) {
    final isSelected = widget.currentDestination == destination;

    return TvFocusable(
      onPressed: () => widget.onDestinationSelected(destination),
      borderRadius: BorderRadius.circular(20),
      backgroundColor: isSelected ? Colors.white : Colors.transparent,
      focusedBackgroundColor: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
          color: isSelected ? Colors.black : const Color(0xFFD0D3D9),
        ),
      ),
    );
  }
}
