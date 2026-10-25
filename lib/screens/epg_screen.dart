import 'dart:async';
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
import '../widgets/tv_channel_logo.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_nav_bar.dart';

class EpgScreen extends StatefulWidget {
  final ChannelService channelService;
  final Function(Channel channel, Program program) onPlayProgram;
  final VoidCallback onBack;
  final ValueChanged<TvNavDestination>? onNavigate;

  const EpgScreen({
    super.key,
    required this.channelService,
    required this.onPlayProgram,
    required this.onBack,
    this.onNavigate,
  });

  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  // ignore: prefer_final_fields
  int _selectedDayOffset = 0; // 0 = Today
  String _selectedCategory = 'ALL';
  String _selectedLanguage = 'ALL';
  bool _showLanguageDialog = false;
  bool _showCategoryDialog = false;
  final Map<String, List<Program>> _channelSchedules = {};
  bool _isLoading = true;

  Channel? _focusedChannel;
  Program? _focusedProgram;

  // Controllers for Synchronized 2D Navigation
  final ScrollController _horizontalTimeController = ScrollController();
  final ScrollController _verticalChannelsController = ScrollController();
  final ScrollController _verticalGridController = ScrollController();
  bool _isSyncingScroll = false;

  static const double _minuteWidth = 5.0; // 5dp per minute = 150dp per 30-minute block
  static const double _rowHeight = 72.0;
  static const double _channelColWidth = 190.0;
  static const double _totalTimelineWidth = 24 * 60 * _minuteWidth; // 7,200 dp

  DateTime get _targetDateMidnight {
    final target = DateTime.now().add(Duration(days: _selectedDayOffset));
    return DateTime(target.year, target.month, target.day, 0, 0);
  }

  @override
  void initState() {
    super.initState();
    _verticalChannelsController.addListener(_syncFromChannels);
    _verticalGridController.addListener(_syncFromGrid);
    _loadSchedules();
  }

  void _syncFromChannels() {
    if (_isSyncingScroll || !_verticalGridController.hasClients) return;
    _isSyncingScroll = true;
    _verticalGridController.jumpTo(_verticalChannelsController.offset);
    _isSyncingScroll = false;
  }

  void _syncFromGrid() {
    if (_isSyncingScroll || !_verticalChannelsController.hasClients) return;
    _isSyncingScroll = true;
    _verticalChannelsController.jumpTo(_verticalGridController.offset);
    _isSyncingScroll = false;
  }

  @override
  void dispose() {
    _verticalChannelsController.removeListener(_syncFromChannels);
    _verticalGridController.removeListener(_syncFromGrid);
    _horizontalTimeController.dispose();
    _verticalChannelsController.dispose();
    _verticalGridController.dispose();
    super.dispose();
  }

  List<Channel> _getFilteredChannels() {
    final all = (_selectedCategory == 'Premium')
        ? widget.channelService.rawChannels
        : widget.channelService.allChannels;
    return all.where((c) {
      if (_selectedCategory == 'Favorites') {
        if (!c.isFavorite) return false;
      } else if (_selectedCategory == 'Free') {
        if (c.isPremium) return false;
      } else if (_selectedCategory == 'Premium') {
        if (!c.isPremium) return false;
      } else if (_selectedCategory != 'ALL' && c.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_selectedLanguage != 'ALL' && c.language.toLowerCase() != _selectedLanguage.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);

    final channels = _getFilteredChannels();
    final batch = channels.take(40).toList();

    await Future.wait(
      batch.map((ch) async {
        final schedule = await widget.channelService.getEpgForChannel(
          ch.channelId,
          dayOffset: _selectedDayOffset,
        );
        _channelSchedules[ch.channelId] = schedule;
      }),
    );

    if (mounted) {
      final initialChannel = batch.isNotEmpty ? batch.first : null;
      final initialPrograms = initialChannel != null ? _channelSchedules[initialChannel.channelId] : null;
      final initialProgram = (initialPrograms != null && initialPrograms.isNotEmpty)
          ? initialPrograms.firstWhere((p) => p.isLive, orElse: () => initialPrograms.first)
          : initialChannel?.activeProgram;

      setState(() {
        _focusedChannel = initialChannel;
        _focusedProgram = initialProgram;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentTime();
      });
    }
  }

  void _scrollToCurrentTime() {
    if (_selectedDayOffset == 0) {
      final now = DateTime.now();
      final minutesFromMidnight = now.hour * 60 + now.minute;
      final targetOffset = (minutesFromMidnight * _minuteWidth) - 300.0;
      if (_horizontalTimeController.hasClients) {
        _horizontalTimeController.animateTo(
          targetOffset.clamp(0.0, _totalTimelineWidth - 800.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _onProgramFocused(Channel channel, Program program) {
    if (_focusedProgram?.programId != program.programId) {
      setState(() {
        _focusedChannel = channel;
        _focusedProgram = program;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = _getFilteredChannels();
    final now = DateTime.now();
    final timeStr = DateFormat('d MMM, hh:mm a').format(now);

    return PopScope(
      canPop: !_showLanguageDialog && !_showCategoryDialog,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showLanguageDialog || _showCategoryDialog) {
          setState(() {
            _showLanguageDialog = false;
            _showCategoryDialog = false;
          });
          return;
        }
        widget.onBack();
      },
      child: Scaffold(
        backgroundColor: TvColors.bgCanvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TvDimensions.overscanMargin,
                  vertical: TvDimensions.overscanMarginVertical,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unified Top Navigation Bar (Image 1 & 2 reference)
                    TvNavBar(
                      currentDestination: widget.channelService.filterOnlyFavorites
                          ? TvNavDestination.favorites
                          : TvNavDestination.epgGrid,
                      onDestinationSelected: (dest) {
                        if (dest == TvNavDestination.epgGrid) return;
                        if (dest == TvNavDestination.liveGuide) {
                          widget.onBack();
                        } else {
                          widget.onNavigate?.call(dest);
                        }
                      },
                      onQuickSwitchLiveTv: () {
                        if (_focusedChannel != null) {
                          widget.onPlayProgram(
                            _focusedChannel!,
                            _focusedProgram ?? _focusedChannel!.activeProgram,
                          );
                        } else if (channels.isNotEmpty) {
                          widget.onPlayProgram(channels.first, channels.first.activeProgram);
                        }
                      },
                      onOpenSearch: () {
                        widget.onNavigate?.call(TvNavDestination.search);
                      },
                    ),

                    // Filter Controls & Quick Action Subheader matching Image 2
                    Row(
                      children: [
                        // "Languages >" Dropdown Filter Pill (Requirement 4)
                        _buildDropdownPill(
                          label: _selectedLanguage == 'ALL' ? 'Languages' : _selectedLanguage,
                          isFiltered: _selectedLanguage != 'ALL',
                          onPressed: () => setState(() => _showLanguageDialog = true),
                        ),
                        const SizedBox(width: 10),

                        // "Categories >" Dropdown Filter Pill (Requirement 4)
                        _buildDropdownPill(
                          label: _selectedCategory == 'ALL' ? 'Categories' : _selectedCategory,
                          isFiltered: _selectedCategory != 'ALL',
                          onPressed: () => setState(() => _showCategoryDialog = true),
                        ),
                        const SizedBox(width: 14),

                  // "[Switch to LiveTV]" Blue Button (Image 2 reference)
                  TvFocusable(
                    onPressed: () {
                      if (_focusedChannel != null) {
                        widget.onPlayProgram(
                          _focusedChannel!,
                          _focusedProgram ?? _focusedChannel!.activeProgram,
                        );
                      } else if (channels.isNotEmpty) {
                        widget.onPlayProgram(channels.first, channels.first.activeProgram);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: const Color(0xFF2E63FF),
                    focusedBackgroundColor: const Color(0xFF1E50F0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedPlay,
                          color: Colors.white,
                          size: 15,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Switch to LiveTV',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Date & Time Display (Image 2 reference: "26 Sep, 11:45 AM")
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Sub-categories Bar matching Reference Image 2:
              // "Most Popular", "Star Plus", "Hindi", "Sports", "Drama", "News", "Entertainment", "Comedy", "Marathi"
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildSubCategoryPill('ALL', 'Most Popular'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('ENTERTAINMENT', 'Entertainment'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('NEWS', 'News'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('SPORTS', 'Sports'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('MOVIES', 'Movies'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('KIDS', 'Kids'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('MUSIC', 'Music'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('INFOTAINMENT', 'Infotainment'),
                    const SizedBox(width: 8),
                    _buildSubCategoryPill('DEVOTIONAL', 'Devotional'),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Program Inspection Mini Guide matching Reference Image 3
              if (_focusedProgram != null && _focusedChannel != null)
                _buildProgramInspectionCard(_focusedChannel!, _focusedProgram!),

              const SizedBox(height: 10),

              // 2D Synchronized Timeline Grid matching Reference Image 2
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: TvColors.accentCyan),
                            SizedBox(height: 12),
                            Text('Loading EPG Guide...', style: TvTypography.body),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Channel Column (Number + Logo)
                          SizedBox(
                            width: _channelColWidth,
                            child: Column(
                              children: [
                                // Top Header "Today"
                                Container(
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    color: TvColors.bgSurface2,
                                    borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
                                    border: Border(
                                      bottom: BorderSide(color: TvColors.borderSubtle),
                                      right: BorderSide(color: TvColors.borderSubtle, width: 2),
                                    ),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: const Text(
                                    'Today',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),

                                // Channel list cells (Image 2 reference: [138] [logo])
                                Expanded(
                                  child: ListView.builder(
                                    controller: _verticalChannelsController,
                                    cacheExtent: 1000.0,
                                    itemCount: channels.length,
                                    itemBuilder: (context, index) {
                                      final ch = channels[index];
                                      final isSelected = ch.channelId == _focusedChannel?.channelId;

                                      return Container(
                                        height: _rowHeight,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isSelected ? TvColors.bgSurface3 : TvColors.bgSurface1,
                                          border: Border(
                                            bottom: const BorderSide(color: TvColors.borderSubtle),
                                            right: const BorderSide(color: TvColors.borderSubtle, width: 2),
                                            left: isSelected
                                                ? const BorderSide(color: Color(0xFF2E63FF), width: 4)
                                                : BorderSide.none,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Channel Number (Image 2 reference: 138, 616, 136)
                                            Container(
                                              width: 36,
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.5),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${ch.channelNo}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Channel Logo
                                            Expanded(
                                              child: Center(
                                                child: TvChannelLogo(
                                                  channel: ch,
                                                  height: 36,
                                                  fit: BoxFit.contain,
                                                ),
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

                          // Right Column: Horizontal 24-Hour Timeline Grid
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _horizontalTimeController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: _totalTimelineWidth,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Sticky 24-Hour Time Ruler Bar (30-min intervals)
                                    Stack(
                                      children: [
                                        Container(
                                          height: 38,
                                          color: TvColors.bgSurface2,
                                          child: Row(
                                            children: List.generate(48, (i) {
                                              final intervalMinutes = i * 30;
                                              final intervalTime = _targetDateMidnight.add(Duration(minutes: intervalMinutes));
                                              return Container(
                                                width: 30 * _minuteWidth,
                                                padding: const EdgeInsets.only(left: 8),
                                                alignment: Alignment.centerLeft,
                                                decoration: const BoxDecoration(
                                                  border: Border(
                                                    left: BorderSide(color: TvColors.borderSubtle),
                                                    bottom: BorderSide(color: TvColors.borderSubtle),
                                                  ),
                                                ),
                                                child: Text(
                                                  DateFormat('hh:mm a').format(intervalTime),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: TvColors.textSecondary,
                                                  ),
                                                ),
                                              );
                                            }),
                                          ),
                                        ),

                                        // Vertical Time Needle Marker (Image 2 reference)
                                        if (_selectedDayOffset == 0)
                                          Builder(builder: (context) {
                                            final nowMinutes = now.hour * 60 + now.minute;
                                            final markerPos = nowMinutes * _minuteWidth;

                                            return Positioned(
                                              left: markerPos - 6,
                                              top: 0,
                                              bottom: 0,
                                              child: Column(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.white,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Container(
                                                      width: 2,
                                                      color: Colors.white.withValues(alpha: 0.8),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ),

                                    // Program Grid Rows (Image 2 reference)
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          ListView.builder(
                                            controller: _verticalGridController,
                                            cacheExtent: 1000.0,
                                            itemCount: channels.length,
                                            itemBuilder: (context, chIndex) {
                                              final ch = channels[chIndex];
                                              final programs = _channelSchedules[ch.channelId] ?? [];

                                              return Container(
                                                height: _rowHeight,
                                                decoration: const BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(color: TvColors.borderSubtle),
                                                  ),
                                                ),
                                                child: Stack(
                                                  children: programs.map((prog) {
                                                    final startMin = prog.startTime.difference(_targetDateMidnight).inMinutes;
                                                    final durMin = prog.duration.inMinutes.clamp(15, 360);
                                                    final leftPos = (startMin * _minuteWidth).toDouble();
                                                    final cardWidth = (durMin * _minuteWidth).toDouble();

                                                    final isLive = prog.isLive && _selectedDayOffset == 0;
                                                    final isFocused = _focusedProgram?.programId == prog.programId &&
                                                        _focusedChannel?.channelId == ch.channelId;

                                                    return Positioned(
                                                      left: leftPos,
                                                      top: 4,
                                                      bottom: 4,
                                                      width: cardWidth - 4,
                                                      child: TvFocusable(
                                                        onFocusChange: (hasF) {
                                                          if (hasF) _onProgramFocused(ch, prog);
                                                        },
                                                        onPressed: () => widget.onPlayProgram(ch, prog),
                                                        borderRadius: BorderRadius.circular(8),
                                                        backgroundColor: isLive
                                                            ? const Color(0xFF2E63FF).withValues(alpha: 0.25)
                                                            : (isFocused ? TvColors.bgSurface3 : TvColors.bgSurface1),
                                                        focusedBackgroundColor: const Color(0xFF2E63FF),
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Text(
                                                              prog.title,
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                fontWeight: isLive ? FontWeight.w800 : FontWeight.w600,
                                                                color: Colors.white,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              '${DateFormat('hh:mm a').format(prog.startTime)} - ${DateFormat('hh:mm a').format(prog.endTime)}',
                                                              style: const TextStyle(
                                                                fontSize: 10,
                                                                color: TvColors.textSecondary,
                                                              ),
                                                              maxLines: 1,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),

      // Language Selection Modal
      if (_showLanguageDialog)
        _buildSelectionModal(
          title: 'Select Broadcast Language',
          options: widget.channelService.languages,
          selected: _selectedLanguage,
          onSelected: (val) {
            setState(() {
              _selectedLanguage = val;
              _showLanguageDialog = false;
            });
            _loadSchedules();
          },
          onClose: () => setState(() => _showLanguageDialog = false),
        ),

      // Category Selection Modal
      if (_showCategoryDialog)
        _buildSelectionModal(
          title: 'Select Channel Category',
          options: widget.channelService.categories,
          selected: _selectedCategory,
          onSelected: (val) {
            setState(() {
              _selectedCategory = val;
              _showCategoryDialog = false;
            });
            _loadSchedules();
          },
          onClose: () => setState(() => _showCategoryDialog = false),
        ),
    ],
  ),
),
);
}

  /// Program Inspection Card inspired by Reference Image 3
  Widget _buildProgramInspectionCard(Channel channel, Program prog) {
    final timeFormat = DateFormat('hh:mm a');
    final isLive = prog.isLive && _selectedDayOffset == 0;

    return Container(
      height: 115,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TvColors.bgSurface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TvColors.borderSubtle),
      ),
      child: Row(
        children: [
          // Left: Currently Playing Show Poster Image (Image 3 reference)
          Container(
            width: 130,
            decoration: BoxDecoration(
              color: TvColors.bgSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (prog.thumbnailUrl != null && prog.thumbnailUrl!.isNotEmpty)
                  Image.network(
                    prog.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: TvChannelLogo(channel: channel, height: 32, fit: BoxFit.contain),
                    ),
                  )
                else
                  Center(
                    child: TvChannelLogo(channel: channel, height: 32, fit: BoxFit.contain),
                  ),

                // Bottom progress / tag (Image 3 reference: "45 min remaining", "Currently Playing")
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.black.withValues(alpha: 0.75),
                    child: Text(
                      isLive ? 'Currently Playing' : (prog.isPast ? 'Catchup' : 'Upcoming'),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Center: Channel & Program Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (channel.logoUrl.isNotEmpty) ...[
                      TvChannelLogo(channel: channel, height: 20, fit: BoxFit.contain),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '< ${channel.channelNo} ${channel.channelName} >',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: TvColors.accentCyan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isLive) const TvLiveBadge(size: 6),
                  ],
                ),
                const SizedBox(height: 4),

                Text(
                  prog.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),

                Text(
                  '${timeFormat.format(prog.startTime)} - ${timeFormat.format(prog.endTime)} • ${prog.genre?.isNotEmpty == true ? prog.genre : channel.category}',
                  style: const TextStyle(fontSize: 12, color: TvColors.textSecondary),
                ),
              ],
            ),
          ),

          // Right: Action CTA Button
          TvFocusable(
            onPressed: () => widget.onPlayProgram(channel, prog),
            borderRadius: BorderRadius.circular(10),
            backgroundColor: const Color(0xFF2E63FF),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HugeIcon(icon: HugeIcons.strokeRoundedPlay, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  isLive ? 'Watch Live' : 'Play Show',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownPill({
    required String label,
    required bool isFiltered,
    required VoidCallback onPressed,
  }) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      backgroundColor: isFiltered ? const Color(0xFF1E3A8A) : Colors.white.withValues(alpha: 0.08),
      focusedBackgroundColor: const Color(0xFF2E63FF),
      focusedBorderColor: TvColors.accentCyan,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isFiltered ? TvColors.accentCyan : Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          HugeIcon(
            icon: HugeIcons.strokeRoundedArrowDown01,
            color: isFiltered ? TvColors.accentCyan : Colors.white70,
            size: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionModal({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    required VoidCallback onClose,
  }) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 460),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TvColors.bgSurface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E63FF), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                TvFocusable(
                  onPressed: onClose,
                  padding: const EdgeInsets.all(4),
                  child: const Text('✕', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final opt = options[index];
                  final isSelected = opt.toLowerCase() == selected.toLowerCase();

                  return TvFocusable(
                    onPressed: () => onSelected(opt),
                    backgroundColor: isSelected ? const Color(0xFF2E63FF) : TvColors.bgSurface1,
                    focusedBackgroundColor: const Color(0xFF1E3A8A),
                    focusedBorderColor: TvColors.accentCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          opt == 'ALL' ? 'All' : opt,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        if (isSelected) const Text('✔', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubCategoryPill(String categoryCode, String label) {
    final isSelected = _selectedCategory.toUpperCase() == categoryCode;

    return TvFocusable(
      onPressed: () {
        setState(() => _selectedCategory = categoryCode);
        _loadSchedules();
      },
      borderRadius: BorderRadius.circular(6),
      backgroundColor: isSelected ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFFC0C4CC),
        ),
      ),
    );
  }
}
