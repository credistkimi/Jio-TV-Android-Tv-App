import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:video_player/video_player.dart';
import '../models/channel.dart';
import '../services/channel_service.dart';
import '../services/storage_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../theme/tv_typography.dart';
import '../widgets/tv_badge.dart';
import '../widgets/tv_channel_logo.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  final ChannelService channelService;
  final StorageService storageService;
  final ValueChanged<Channel> onOpenPlayer;
  final ValueChanged<TvNavDestination> onNavigate;

  const HomeScreen({
    super.key,
    required this.channelService,
    required this.storageService,
    required this.onOpenPlayer,
    required this.onNavigate,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Channel? _activeChannel;
  VideoPlayerController? _previewController;
  Timer? _previewDebounce;
  bool _isVideoPlaying = false;

  // Active Category & Channel tracking for Row-Swapping Stage
  int _currentCategoryIndex = 0;
  int _currentChannelIndex = 0;

  late final FocusNode _heroWatchLiveFocusNode;
  late final FocusNode _heroFavoriteFocusNode;
  late final FocusNode _heroInfoFocusNode;

  final Map<String, FocusNode> _channelFocusNodes = {};

  FocusNode _getChannelFocusNode(int categoryIndex, int channelIndex) {
    final key = '$categoryIndex:$channelIndex';
    return _channelFocusNodes.putIfAbsent(
      key,
      () => FocusNode(debugLabel: 'ChannelCard_${categoryIndex}_$channelIndex'),
    );
  }

  final ScrollController _channelRowScrollController = ScrollController();

  final int _heroCarouselIndex = 0;

  @override
  void initState() {
    super.initState();
    _heroWatchLiveFocusNode = FocusNode(debugLabel: 'HeroWatchLive');
    _heroFavoriteFocusNode = FocusNode(debugLabel: 'HeroFavorite');
    _heroInfoFocusNode = FocusNode(debugLabel: 'HeroInfo');
    widget.channelService.addListener(_onChannelServiceChanged);
    _syncActiveChannel();
  }

  @override
  void dispose() {
    widget.channelService.removeListener(_onChannelServiceChanged);
    _previewDebounce?.cancel();
    _previewController?.dispose();
    _channelRowScrollController.dispose();
    _heroWatchLiveFocusNode.dispose();
    _heroFavoriteFocusNode.dispose();
    _heroInfoFocusNode.dispose();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    _channelFocusNodes.clear();
    super.dispose();
  }

  void _onChannelServiceChanged() {
    if (!mounted) return;
    _syncActiveChannel();
    setState(() {});
  }

  Map<String, List<Channel>> _getFilteredGroupedChannels() {
    return widget.channelService.channelsByCategory;
  }

  List<String> _getCategoryKeys() {
    return _getFilteredGroupedChannels().keys.toList();
  }

  void _syncActiveChannel() {
    final grouped = _getFilteredGroupedChannels();
    final categories = grouped.keys.toList();
    if (categories.isEmpty) return;

    if (_currentCategoryIndex >= categories.length) {
      _currentCategoryIndex = 0;
    }

    final catName = categories[_currentCategoryIndex];
    final channels = grouped[catName] ?? [];

    if (channels.isNotEmpty) {
      if (_currentChannelIndex >= channels.length) {
        _currentChannelIndex = 0;
      }
      final target = channels[_currentChannelIndex];
      if (_activeChannel?.channelId != target.channelId) {
        _activeChannel = target;
        _schedulePreviewForChannel(target);
      }
    }
  }

  void _focusActiveChannelCard() {
    final grouped = _getFilteredGroupedChannels();
    final categories = grouped.keys.toList();
    if (categories.isEmpty) return;
    final catName = categories[_currentCategoryIndex.clamp(0, categories.length - 1)];
    final channels = grouped[catName] ?? [];
    if (channels.isEmpty) return;

    final targetIdx = _currentChannelIndex.clamp(0, channels.length - 1);
    final node = _getChannelFocusNode(_currentCategoryIndex, targetIdx);
    node.requestFocus();
  }

  /// Switch the active row to [newIndex] without scrolling the page down.
  /// The slot at `| Category name | | Channel |` immediately becomes the new category.
  void _changeCategory(int newIndex) {
    final categories = _getCategoryKeys();
    if (categories.isEmpty) return;
    if (newIndex < 0 || newIndex >= categories.length) return;
    if (newIndex == _currentCategoryIndex) return;

    final grouped = _getFilteredGroupedChannels();
    final newCatName = categories[newIndex];
    final channels = grouped[newCatName] ?? [];

    setState(() {
      _currentCategoryIndex = newIndex;
    });

    if (channels.isNotEmpty) {
      final targetIdx = _currentChannelIndex.clamp(0, channels.length - 1);
      _currentChannelIndex = targetIdx;
      final newChannel = channels[targetIdx];
      setState(() {
        _activeChannel = newChannel;
        _isVideoPlaying = false; // Show poster immediately
      });
      _schedulePreviewForChannel(newChannel);
    }

    // Smoothly focus channel card in the newly selected category row
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (channels.isNotEmpty) {
        final targetIdx = _currentChannelIndex.clamp(0, channels.length - 1);
        final node = _getChannelFocusNode(newIndex, targetIdx);
        node.requestFocus();
      }
    });
  }

  /// Triggered whenever remote D-Pad focus changes to another channel card.
  /// 1. Immediately updates the container to show this channel's poster/artwork.
  /// 2. Cancels any existing preview video and timer.
  /// 3. After the configured delay (from Settings, default 1s), plays the preview video.
  void _onChannelFocused(Channel channel) {
    if (_activeChannel?.channelId == channel.channelId) return;

    setState(() {
      _activeChannel = channel;
      _isVideoPlaying = false; // Show poster immediately
    });

    _schedulePreviewForChannel(channel);
  }

  void _schedulePreviewForChannel(Channel channel) {
    _previewDebounce?.cancel();
    _previewController?.dispose();
    _previewController = null;

    final isAutoplayEnabled = widget.storageService.getAutoplayPreview();
    if (!isAutoplayEnabled) {
      return;
    }

    final delaySeconds = widget.storageService.getPreviewAutoplayDelay();
    final delayMs = (delaySeconds * 1000).round();

    _previewDebounce = Timer(Duration(milliseconds: delayMs), () {
      if (mounted && _activeChannel?.channelId == channel.channelId) {
        _startPreviewForChannel(channel);
      }
    });
  }

  Future<void> _startPreviewForChannel(Channel channel) async {
    final streamUrl = await widget.channelService.resolvePlaybackUrl(channel);
    if (!mounted || _activeChannel?.channelId != channel.channelId) return;

    final oldController = _previewController;
    final uri = Uri.tryParse(streamUrl) ?? Uri.parse(streamUrl);
    final hdnea = uri.queryParameters['hdnea'] ?? uri.queryParameters['__hdnea__'] ?? '';
    final headers = <String, String>{
      'User-Agent': 'plaYtv/7.1.8 (Linux;Android 8.1.0) ExoPlayerLib/2.11.7',
      'Accept': '*/*',
      if (hdnea.isNotEmpty) 'Cookie': '__hdnea__=$hdnea',
    };

    debugPrint('[HomeScreen] Starting video preview for ${channel.channelName} after delay');
    final newController = VideoPlayerController.networkUrl(uri, httpHeaders: headers);

    try {
      await newController.initialize();
      await newController.setVolume(0.0);
      await newController.setLooping(true);
      await newController.play();

      if (mounted && _activeChannel?.channelId == channel.channelId) {
        setState(() {
          _previewController = newController;
          _isVideoPlaying = true;
        });
        oldController?.dispose();
      } else {
        newController.dispose();
      }
    } catch (e) {
      debugPrint('[HomeScreen] Video preview failed for ${channel.channelName}: $e');
      newController.dispose();
    }
  }

  void _showChannelInfoDialog(BuildContext context, Channel channel) {
    final prog = channel.activeProgram;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1B1612),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF2E241E)),
        ),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvChannelLogo(channel: channel, height: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel.channelName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                        Text(
                          'Channel ${channel.channelNo} • ${channel.category} • ${channel.language}',
                          style: const TextStyle(fontSize: 12, color: TvColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (channel.isHd) const TvHdBadge(),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF2E241E)),
              const SizedBox(height: 12),
              Text(
                prog.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                prog.synopsis.isNotEmpty
                    ? prog.synopsis
                    : 'Watch live continuous broadcast with crystal-clear 1080p full HD streaming and 7-day catchup playback on JioTV+ TV.',
                style: const TextStyle(fontSize: 13, color: Color(0xFFC7BFB5), height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvFocusable(
                    onPressed: () => Navigator.of(ctx).pop(),
                    borderRadius: BorderRadius.circular(10),
                    backgroundColor: const Color(0xFF2A221C),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  TvFocusable(
                    autofocus: true,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      widget.onOpenPlayer(channel);
                    },
                    borderRadius: BorderRadius.circular(10),
                    backgroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedPlay, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('Watch Live', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<List<dynamic>> _getCategoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('fav')) return HugeIcons.strokeRoundedStar;
    if (lower.contains('trend') || lower.contains('live') || lower.contains('what')) return HugeIcons.strokeRoundedFire;
    if (lower.contains('sport')) return HugeIcons.strokeRoundedPlay;
    if (lower.contains('movie') || lower.contains('cinema')) return HugeIcons.strokeRoundedFilm01;
    if (lower.contains('news') || lower.contains('business')) return HugeIcons.strokeRoundedNews;
    if (lower.contains('kid')) return HugeIcons.strokeRoundedSparkles;
    if (lower.contains('music')) return HugeIcons.strokeRoundedMusicNote01;
    if (lower.contains('info') || lower.contains('docu')) return HugeIcons.strokeRoundedCompass01;
    if (lower.contains('devo')) return HugeIcons.strokeRoundedSun01;
    return HugeIcons.strokeRoundedTv01;
  }

  @override
  Widget build(BuildContext context) {
    final channelService = widget.channelService;
    final groupedChannels = _getFilteredGroupedChannels();
    final categories = groupedChannels.keys.toList();

    final activeChannel = _activeChannel ??
        (channelService.currentChannel != null &&
                (!channelService.filterOnlyFavorites || channelService.currentChannel!.isFavorite)
            ? channelService.currentChannel
            : (channelService.allChannels.isNotEmpty ? channelService.allChannels.first : null));

    final currentCategoryName = categories.isNotEmpty && _currentCategoryIndex < categories.length
        ? categories[_currentCategoryIndex]
        : 'Trending & Live Now';
    final currentChannels = categories.isNotEmpty && _currentCategoryIndex < categories.length
        ? (groupedChannels[currentCategoryName] ?? [])
        : <Channel>[];

    final hasNextCategory = categories.isNotEmpty && (_currentCategoryIndex + 1 < categories.length);
    final nextCategoryName = hasNextCategory ? categories[_currentCategoryIndex + 1] : '';
    final nextChannels = hasNextCategory ? (groupedChannels[nextCategoryName] ?? []) : <Channel>[];

    return Scaffold(
      backgroundColor: TvColors.bgCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TvDimensions.overscanMargin,
            vertical: 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Navigation Bar
              TvNavBar(
                currentDestination: channelService.filterOnlyFavorites
                    ? TvNavDestination.favorites
                    : TvNavDestination.liveGuide,
                onDestinationSelected: (dest) {
                  if (dest == TvNavDestination.favorites) {
                    channelService.toggleFavoritesFilter();
                  } else {
                    widget.onNavigate(dest);
                  }
                },
                onQuickSwitchLiveTv: () {
                  if (activeChannel != null) {
                    widget.onOpenPlayer(activeChannel);
                  }
                },
                onOpenSearch: () {
                  widget.onNavigate(TvNavDestination.search);
                },
              ),

              const SizedBox(height: 4),

              // 2. FIXED CONTAINER (User Requirement: Maintains fixed keyline position)
              // | Container |
              if (activeChannel != null)
                _buildFixedHeroContainer(activeChannel),

              const SizedBox(height: 10),

              // 3. ROW-SWAPPING VIEWPORT STAGE (User Requirement: Maintains fixed keyline position)
              // | Category name |
              // | Channel |
              // and other bottom Channel row shown based on height
              Expanded(
                child: categories.isEmpty
                    ? Center(
                        child: Text(
                          channelService.isLoading ? 'Loading channels from Jio TV...' : 'No channels available.',
                          style: TvTypography.body,
                        ),
                      )
                    : ClipRect(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Current Active Row (In-place swap on UP/DOWN, zero downward scroll)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 140),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              child: KeyedSubtree(
                                key: ValueKey('active_category_$_currentCategoryIndex'),
                                child: _buildActiveCategorySection(
                                  categoryName: currentCategoryName,
                                  channels: currentChannels,
                                  totalCategories: categories.length,
                                ),
                              ),
                            ),

                            // Next Row (Shown based on available height underneath)
                            if (hasNextCategory) ...[
                              const SizedBox(height: 6),
                              Expanded(
                                child: _buildPeekNextCategorySection(
                                  categoryName: nextCategoryName,
                                  channels: nextChannels,
                                  onPromote: () => _changeCategory(_currentCategoryIndex + 1),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fixed Hero Banner Container (Matching Image 1 Reference)
  /// Always fixed at the top; immediately shows show poster when channel focus changes,
  /// and then starts live video preview after delay (1s default, configurable in Settings).
  Widget _buildFixedHeroContainer(Channel channel) {
    final prog = channel.activeProgram;

    return Container(
      height: 235,
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF262C3D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Preview (when playing) OR Show Poster / Backdrop (immediately shown)
          if (_isVideoPlaying && _previewController != null && _previewController!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _previewController!.value.size.width,
                height: _previewController!.value.size.height,
                child: VideoPlayer(_previewController!),
              ),
            )
          else ...[
            if (prog.thumbnailUrl != null && prog.thumbnailUrl!.isNotEmpty)
              Image.network(
                prog.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPosterFallback(channel),
              )
            else
              _buildPosterFallback(channel),
          ],

          // 2. High-contrast gradient vignette so text & buttons are crisp (Image 1 reference)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.95),
                  Colors.black.withValues(alpha: 0.80),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 0.75, 1.0],
              ),
            ),
          ),

          // 3. Foreground Hero Content (Image 1 reference)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                // Left Column: Channel info, Title, Meta, Synopsis & Action Buttons
                Expanded(
                  flex: 65,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Broadcaster Logo & LIVE Pill
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: TvChannelLogo(
                              channel: channel,
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const TvLiveBadge(),
                          if (channel.isHd) ...[
                            const SizedBox(width: 6),
                            const TvHdBadge(fontSize: 10),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Large Title (Matching Image 1: "Aaj Tak Live Broadcast")
                      Text(
                        prog.title,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),

                      // Meta Tags (Matching Image 1: "News | Hindi | 2026 | U/A 13+")
                      Text(
                        '${channel.category} | ${channel.language} | 2026 | U/A 13+',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFC0C4CC),
                        ),
                      ),
                      const SizedBox(height: 5),

                      // Synopsis Description (Matching Image 1)
                      Text(
                        prog.synopsis.isNotEmpty
                            ? prog.synopsis
                            : 'Watch live continuous broadcast of ${channel.channelName} in HD quality with catchup support on JioTV+ TV.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFA5ACB8),
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Action Buttons (Matching Image 1: [Watch Live] [+ Add to Favorites] [More Info])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Watch Live Button (White pill button)
                          TvFocusable(
                            focusNode: _heroWatchLiveFocusNode,
                            onPressed: () => widget.onOpenPlayer(channel),
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _focusActiveChannelCard();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            borderRadius: BorderRadius.circular(24),
                            backgroundColor: Colors.white,
                            focusedBackgroundColor: const Color(0xFFE50914),
                            focusedBorderColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedPlay,
                                  color: Colors.black,
                                  size: 15,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Watch Live',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Add to Favorites Button (Glass pill button)
                          TvFocusable(
                            focusNode: _heroFavoriteFocusNode,
                            onPressed: () {
                              widget.channelService.toggleFavorite(channel);
                              setState(() {});
                            },
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _focusActiveChannelCard();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            borderRadius: BorderRadius.circular(24),
                            backgroundColor: Colors.white.withValues(alpha: 0.12),
                            focusedBackgroundColor: Colors.white.withValues(alpha: 0.25),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: channel.isFavorite
                                      ? HugeIcons.strokeRoundedStar
                                      : HugeIcons.strokeRoundedPlusSign,
                                  color: channel.isFavorite ? TvColors.reminderYellow : Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  channel.isFavorite ? 'In Favorites' : 'Add to Favorites',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // More Info Button (Glass pill button)
                          TvFocusable(
                            focusNode: _heroInfoFocusNode,
                            onPressed: () => _showChannelInfoDialog(context, channel),
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _focusActiveChannelCard();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            borderRadius: BorderRadius.circular(24),
                            backgroundColor: Colors.white.withValues(alpha: 0.12),
                            focusedBackgroundColor: Colors.white.withValues(alpha: 0.25),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedInformationCircle,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'More Info',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right Area: Carousel Indicator Dots (Image 1 reference)
                Expanded(
                  flex: 35,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (dotIndex) {
                          final isCurrent = dotIndex == _heroCarouselIndex;
                          return Container(
                            width: isCurrent ? 18 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterFallback(Channel channel) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E2230),
            const Color(0xFF0F1219),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 60),
          child: Opacity(
            opacity: 0.25,
            child: TvChannelLogo(
              channel: channel,
              height: 110,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  /// Primary Active Category Section
  /// Holds the fixed stage keyline slot:
  /// | Category name |
  /// | Channle |
  /// When DOWN is pressed on remote:
  /// Current Row becomes Next Row, and previous row is swapped out without downward scrolling!
  Widget _buildActiveCategorySection({
    required String categoryName,
    required List<Channel> channels,
    required int totalCategories,
  }) {
    final icon = _getCategoryIcon(categoryName);
    final isTrending = categoryName.toLowerCase().contains('trend') || categoryName.toLowerCase().contains('what');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category Header (Matching Image 1: "Trending & Live Now 🔴 LIVE   View All >")
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              HugeIcon(
                icon: icon,
                color: isTrending ? const Color(0xFFE50914) : TvColors.accentCyan,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                isTrending ? "Trending & Live Now" : categoryName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              if (isTrending) ...[
                const SizedBox(width: 8),
                const TvLiveBadge(),
              ],
              const Spacer(),
              const Text(
                'View All >',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: TvColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Horizontal Channel Cards Row
        SizedBox(
          height: 165,
          child: ListView.separated(
            controller: _channelRowScrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            physics: const ClampingScrollPhysics(),
            cacheExtent: 1500,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            itemCount: channels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final ch = channels[index];
              final prog = ch.activeProgram;
              final isCurrentActive = ch.channelId == _activeChannel?.channelId;
              final fn = _getChannelFocusNode(_currentCategoryIndex, index);

              return TvFocusable(
                focusNode: fn,
                autofocus: _currentCategoryIndex == 0 && index == 0,
                scale: 1.02,
                scrollAlignment: 0.18,
                focusedBorderColor: TvColors.focusRingRed,
                focusedGlowColor: TvColors.focusGlowRed,
                onFocusChange: (hasF) {
                  if (hasF) {
                    _currentChannelIndex = index;
                    _onChannelFocused(ch);
                  }
                },
                // Remote D-Pad Navigation:
                // DOWN -> Advance Current Row to Next Category smoothly
                // UP -> Retreat Current Row to Previous Category (or exit up to Hero Action Buttons if at top)
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  // Prevent escaping past left/right ends of the row
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index == 0) {
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight && index == channels.length - 1) {
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    if (_currentCategoryIndex < totalCategories - 1) {
                      _changeCategory(_currentCategoryIndex + 1);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.handled; // Absorbed at last category
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    if (_currentCategoryIndex > 0) {
                      _changeCategory(_currentCategoryIndex - 1);
                      return KeyEventResult.handled;
                    }
                    // When on first category row, move focus UP to Hero banner action buttons
                    _heroWatchLiveFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                onPressed: () => widget.onOpenPlayer(ch),
                borderRadius: BorderRadius.circular(14),
                backgroundColor: isCurrentActive ? const Color(0xFF22283A) : const Color(0xFF141722),
                padding: const EdgeInsets.all(9),
                child: SizedBox(
                  width: 205,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Card Top Bar: LIVE badge & Favorite Star
                      Row(
                        children: [
                          const TvLiveBadge(),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              widget.channelService.toggleFavorite(ch);
                              setState(() {});
                            },
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedStar,
                              color: ch.isFavorite ? TvColors.reminderYellow : TvColors.textDisabled,
                              size: 15,
                            ),
                          ),
                          if (ch.isHd) ...[
                            const SizedBox(width: 4),
                            const TvHdBadge(fontSize: 8),
                          ],
                        ],
                      ),

                      // Card Center: Show Artwork or Channel Logo
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1F2C),
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
                                    child: TvChannelLogo(channel: ch, height: 38, fit: BoxFit.contain),
                                  ),
                                )
                              else
                                Center(
                                  child: TvChannelLogo(channel: ch, height: 38, fit: BoxFit.contain),
                                ),
                              if (prog.thumbnailUrl != null && prog.thumbnailUrl!.isNotEmpty && ch.logoUrl.isNotEmpty)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: TvChannelLogo(
                                      channel: ch,
                                      height: 16,
                                      width: 16,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Card Bottom: Channel & Category | Language
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ch.channelName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${ch.category} | ${ch.language}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: TvColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Secondary Peek Next Category Section
  /// "and other bottom Channle row will be shown based on the height"
  /// Displayed under the current row; tapping or pressing DOWN smoothly promotes it to Current Row.
  Widget _buildPeekNextCategorySection({
    required String categoryName,
    required List<Channel> channels,
    required VoidCallback onPromote,
  }) {
    final icon = _getCategoryIcon(categoryName);

    return Opacity(
      opacity: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Next Category Header
          Row(
            children: [
              HugeIcon(
                icon: icon,
                color: TvColors.textSecondary,
                size: 15,
              ),
              const SizedBox(width: 8),
              Text(
                categoryName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC0C4CC),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Next Row ↓',
                  style: TextStyle(fontSize: 10, color: TvColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Horizontal Peek Cards (Non-focus stealing preview; tapping promotes to active)
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const ClampingScrollPhysics(),
              cacheExtent: 1200,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final ch = channels[index];
                return GestureDetector(
                  onTap: onPromote,
                  child: Container(
                    width: 205,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141722),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF202534)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const TvLiveBadge(),
                            const Spacer(),
                            if (ch.isHd) const TvHdBadge(fontSize: 8),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: TvChannelLogo(channel: ch, height: 32, fit: BoxFit.contain),
                          ),
                        ),
                        Text(
                          ch.channelName,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
