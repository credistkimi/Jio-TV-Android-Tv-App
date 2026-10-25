import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../models/channel.dart';
import '../models/program.dart';
import '../services/channel_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../theme/tv_typography.dart';
import '../widgets/tv_badge.dart';
import '../widgets/tv_category_pill.dart';
import '../widgets/tv_channel_logo.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_nav_bar.dart';

class CatchupScreen extends StatefulWidget {
  final ChannelService channelService;
  final Function(Channel channel, Program program) onPlayProgram;
  final VoidCallback onBack;
  final ValueChanged<TvNavDestination>? onNavigate;

  const CatchupScreen({
    super.key,
    required this.channelService,
    required this.onPlayProgram,
    required this.onBack,
    this.onNavigate,
  });

  @override
  State<CatchupScreen> createState() => _CatchupScreenState();
}

class _CatchupScreenState extends State<CatchupScreen> {
  late Channel _selectedChannel;
  int _selectedDayOffset = -1; // Default to Yesterday (-1)
  String _selectedCategory = 'ALL';
  List<Program> _pastPrograms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final channels = _getAvailableChannels();
    _selectedChannel = widget.channelService.currentChannel ??
        (channels.isNotEmpty
            ? channels.first
            : Channel(
                channelId: '144',
                channelNo: 144,
                channelName: 'Colors HD',
                logoUrl: '',
                streamUrl: '',
                category: 'Entertainment',
                language: 'Hindi',
              ));
    _loadCatchupPrograms();
  }

  List<Channel> _getAvailableChannels() {
    final all = widget.channelService.allChannels;
    if (_selectedCategory == 'ALL') return all;
    return all.where((c) => c.category.toLowerCase() == _selectedCategory.toLowerCase()).toList();
  }

  Future<void> _loadCatchupPrograms() async {
    setState(() => _isLoading = true);
    final programs = await widget.channelService.getEpgForChannel(
      _selectedChannel.channelId,
      dayOffset: _selectedDayOffset,
    );
    final sorted = programs.reversed.toList();
    if (mounted) {
      setState(() {
        _pastPrograms = sorted;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM');
    final timeFormat = DateFormat('hh:mm a');
    final channels = _getAvailableChannels();
    final categories = widget.channelService.categories.take(8).toList();

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
              // 1. Top Navigation Bar
              TvNavBar(
                currentDestination: widget.channelService.filterOnlyFavorites
                    ? TvNavDestination.favorites
                    : TvNavDestination.catchup,
                onDestinationSelected: (dest) {
                  if (dest == TvNavDestination.catchup) return;
                  if (dest == TvNavDestination.liveGuide) {
                    widget.onBack();
                  } else {
                    widget.onNavigate?.call(dest);
                  }
                },
                onQuickSwitchLiveTv: () {
                  widget.onPlayProgram(_selectedChannel, _selectedChannel.activeProgram);
                },
                onOpenSearch: () {
                  widget.onNavigate?.call(TvNavDestination.search);
                },
              ),

              // 2. Category Quick-Filter Bar
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  physics: const BouncingScrollPhysics(),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = _selectedCategory == cat;
                    return TvCategoryPill(
                      label: cat == 'ALL' ? 'All Channels' : cat,
                      isSelected: isSelected,
                      onPressed: () {
                        setState(() => _selectedCategory = cat);
                        final filtered = _getAvailableChannels();
                        if (filtered.isNotEmpty && !filtered.any((c) => c.channelId == _selectedChannel.channelId)) {
                          setState(() => _selectedChannel = filtered.first);
                          _loadCatchupPrograms();
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // 3. Main Split-Pane Body: Left (Channels Rail) + Right (Catchup Shows)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT COLUMN: Actual Channels Rail with Logos & Numbers (Width 280dp)
                    SizedBox(
                      width: 280,
                      child: Container(
                        decoration: BoxDecoration(
                          color: TvColors.bgSurface1,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: TvColors.borderSubtle),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              color: Colors.black.withValues(alpha: 0.3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'SELECT CHANNEL',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: TvColors.textSecondary,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  Text(
                                    '${channels.length}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: TvColors.accentCyan,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: channels.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: TvColors.borderSubtle),
                                physics: const BouncingScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final ch = channels[index];
                                  final isSelected = ch.channelId == _selectedChannel.channelId;

                                  return TvFocusable(
                                    autofocus: index == 0,
                                    onPressed: () {
                                      setState(() => _selectedChannel = ch);
                                      _loadCatchupPrograms();
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    backgroundColor: isSelected ? TvColors.bgSurface3 : Colors.transparent,
                                    focusedBackgroundColor: const Color(0xFF1E3A8A),
                                    focusedBorderColor: TvColors.accentCyan,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        // Channel Logo
                                        Container(
                                          width: 38,
                                          height: 38,
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: TvChannelLogo(
                                            channel: ch,
                                            height: 28,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        // Channel Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${ch.channelNo} • ${ch.channelName}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Text(
                                                    ch.category,
                                                    style: const TextStyle(fontSize: 10, color: TvColors.textSecondary),
                                                  ),
                                                  if (ch.isHd) ...[
                                                    const SizedBox(width: 4),
                                                    const TvHdBadge(fontSize: 7),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        if (isSelected)
                                          const HugeIcon(
                                            icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                                            color: TvColors.accentCyan,
                                            size: 16,
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // RIGHT COLUMN: 7-Day Day Selector + Past Broadcast Programs List
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Channel Header with 7-Day Archive Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: TvColors.bgSurface1,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: TvColors.borderSubtle),
                            ),
                            child: Row(
                              children: [
                                TvChannelLogo(
                                  channel: _selectedChannel,
                                  height: 24,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${_selectedChannel.channelName} • 7-Day Catchup Episodes',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const TvCatchupBadge(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // 7-Day Day Selector Pills
                          SizedBox(
                            height: 44,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                              physics: const BouncingScrollPhysics(),
                              itemCount: 7,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final offset = -(index + 1);
                                final date = DateTime.now().add(Duration(days: offset));
                                final isSelected = _selectedDayOffset == offset;
                                final label = index == 0 ? 'Yesterday' : dateFormat.format(date);

                                return TvCategoryPill(
                                  label: label,
                                  isSelected: isSelected,
                                  onPressed: () {
                                    setState(() => _selectedDayOffset = offset);
                                    _loadCatchupPrograms();
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Past Programs List with Poster Artwork
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: TvColors.accentCyan))
                                : _pastPrograms.isEmpty
                                    ? const Center(
                                        child: Text('No catchup episodes recorded for this channel and date.',
                                            style: TvTypography.body),
                                      )
                                    : ListView.separated(
                                        clipBehavior: Clip.none,
                                        itemCount: _pastPrograms.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                                        physics: const BouncingScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          final prog = _pastPrograms[index];

                                          return TvFocusable(
                                            onPressed: () => widget.onPlayProgram(_selectedChannel, prog),
                                            borderRadius: BorderRadius.circular(12),
                                            backgroundColor: TvColors.bgSurface1,
                                            focusedBackgroundColor: TvColors.bgSurface3,
                                            focusedBorderColor: const Color(0xFF2E63FF),
                                            padding: const EdgeInsets.all(10),
                                            child: Row(
                                              children: [
                                                // Program Thumbnail
                                                Container(
                                                  width: 110,
                                                  height: 64,
                                                  decoration: BoxDecoration(
                                                    color: TvColors.bgSurface2,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  clipBehavior: Clip.antiAlias,
                                                  child: prog.thumbnailUrl != null && prog.thumbnailUrl!.isNotEmpty
                                                      ? Image.network(
                                                          prog.thumbnailUrl!,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Center(
                                                            child: TvChannelLogo(
                                                              channel: _selectedChannel,
                                                              height: 28,
                                                              fit: BoxFit.contain,
                                                            ),
                                                          ),
                                                        )
                                                      : Center(
                                                          child: TvChannelLogo(
                                                            channel: _selectedChannel,
                                                            height: 28,
                                                            fit: BoxFit.contain,
                                                          ),
                                                        ),
                                                ),
                                                const SizedBox(width: 14),

                                                // Time & Duration
                                                SizedBox(
                                                  width: 150,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '${timeFormat.format(prog.startTime)} - ${timeFormat.format(prog.endTime)}',
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w800,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        '${prog.duration.inMinutes} mins • ${prog.genre?.isNotEmpty == true ? prog.genre : _selectedChannel.category}',
                                                        style: const TextStyle(fontSize: 11, color: TvColors.textSecondary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 14),

                                                // Title & Description
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        prog.title,
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.w800,
                                                          color: Colors.white,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      if (prog.synopsis.isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          prog.synopsis,
                                                          style: const TextStyle(fontSize: 12, color: TvColors.textSecondary),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),

                                                // Play Replay Button
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2E63FF),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      HugeIcon(
                                                        icon: HugeIcons.strokeRoundedPlay,
                                                        color: Colors.white,
                                                        size: 14,
                                                      ),
                                                      SizedBox(width: 6),
                                                      Text(
                                                        'REPLAY',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w800,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
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
}
