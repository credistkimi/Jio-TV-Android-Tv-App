import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../theme/tv_typography.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_channel_logo.dart';

class SearchScreen extends StatefulWidget {
  final ChannelService channelService;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onBack;

  const SearchScreen({
    super.key,
    required this.channelService,
    required this.onOpenPlayer,
    required this.onBack,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _searchQuery = '';
  final ScrollController _gridScrollController = ScrollController();

  static const List<List<String>> _keyboardKeys = [
    ['A', 'B', 'C', 'D', 'E', 'F'],
    ['G', 'H', 'I', 'J', 'K', 'L'],
    ['M', 'N', 'O', 'P', 'Q', 'R'],
    ['S', 'T', 'U', 'V', 'W', 'X'],
    ['Y', 'Z', '1', '2', '3', '4'],
    ['5', '6', '7', '8', '9', '0'],
  ];

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  void _onKeyPress(String key) {
    setState(() {
      _searchQuery += key;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_searchQuery.isNotEmpty) {
        _searchQuery = _searchQuery.substring(0, _searchQuery.length - 1);
      }
    });
  }

  void _onClear() {
    setState(() {
      _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channelService.searchChannels(_searchQuery);
    final isTrending = _searchQuery.trim().isEmpty;

    return Scaffold(
      backgroundColor: TvColors.bgCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TvDimensions.overscanMargin,
            vertical: TvDimensions.overscanMarginVertical,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Search Bar (Image 5 reference)
              Row(
                children: [
                  // Back button
                  TvFocusable(
                    onPressed: widget.onBack,
                    borderRadius: BorderRadius.circular(20),
                    backgroundColor: TvColors.bgSurface2,
                    padding: const EdgeInsets.all(10),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Mic Icon Button
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedPlay,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Search Input Pill
                  Expanded(
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _searchQuery.isNotEmpty
                              ? TvColors.accentCyan
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            color: TvColors.textSecondary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Search anything: shows, movies, episodes or keywords'
                                  : _searchQuery,
                              style: TextStyle(
                                fontSize: 16,
                                fontStyle: _searchQuery.isEmpty ? FontStyle.italic : FontStyle.normal,
                                color: _searchQuery.isEmpty ? TvColors.textDisabled : Colors.white,
                                fontWeight: _searchQuery.isEmpty ? FontWeight.w400 : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            TvFocusable(
                              onPressed: _onClear,
                              borderRadius: BorderRadius.circular(12),
                              backgroundColor: Colors.transparent,
                              padding: const EdgeInsets.all(4),
                              child: const HugeIcon(
                                icon: HugeIcons.strokeRoundedCancel01,
                                color: TvColors.textSecondary,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Main Body: Left Keyboard (Image 5) vs Right Results Grid
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Side: 6-Column Keyboard (Image 5 reference)
                    SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._keyboardKeys.map((row) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: row.map((char) {
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: TvFocusable(
                                        onPressed: () => _onKeyPress(char),
                                        borderRadius: BorderRadius.circular(6),
                                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Center(
                                          child: Text(
                                            char,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          }),

                          const SizedBox(height: 4),

                          // Bottom Controls: Space, Backspace, Clear, OK
                          Row(
                            children: [
                              // Space
                              Expanded(
                                flex: 3,
                                child: TvFocusable(
                                  onPressed: () => _onKeyPress(' '),
                                  borderRadius: BorderRadius.circular(6),
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: const Center(
                                    child: Text(
                                      '␣ SPACE',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Backspace
                              Expanded(
                                flex: 2,
                                child: TvFocusable(
                                  onPressed: _onBackspace,
                                  borderRadius: BorderRadius.circular(6),
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: const Center(
                                    child: HugeIcon(
                                      icon: HugeIcons.strokeRoundedDelete02,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Clear
                              Expanded(
                                flex: 2,
                                child: TvFocusable(
                                  onPressed: _onClear,
                                  borderRadius: BorderRadius.circular(6),
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: const Center(
                                    child: Text(
                                      'Clear',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Right Side: "Trending" / Search Results Grid (Image 5 reference)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTrending
                                ? 'Trending Channels & Shows'
                                : 'Search Results (${channels.length} channels)',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          Expanded(
                            child: channels.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No matching channels or shows found.',
                                      style: TvTypography.body,
                                    ),
                                  )
                                : GridView.builder(
                                    controller: _gridScrollController,
                                    clipBehavior: Clip.none,
                                    padding: const EdgeInsets.all(4),
                                    physics: const BouncingScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4,
                                      childAspectRatio: 1.6,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: channels.length,
                                    itemBuilder: (context, index) {
                                      final channel = channels[index];
                                      return _buildChannelCard(channel);
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelCard(Channel channel) {
    return TvFocusable(
      onPressed: () => widget.onOpenPlayer(channel),
      borderRadius: BorderRadius.circular(12),
      backgroundColor: TvColors.bgSurface1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TvColors.bgSurface2,
                  TvColors.bgSurface1,
                ],
              ),
            ),
          ),

          // Channel Logo / Show Artwork
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: channel.currentProgram?.thumbnailUrl != null &&
                      channel.currentProgram!.thumbnailUrl!.isNotEmpty
                  ? Image.network(
                      channel.currentProgram!.thumbnailUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => TvChannelLogo(
                        channel: channel,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                    )
                  : TvChannelLogo(
                      channel: channel,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
            ),
          ),

          // Top Badges
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${channel.channelNo}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: TvColors.liveRed,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '● LIVE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Bottom Title Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Text(
                channel.channelName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
