import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../models/channel.dart';
import '../models/program.dart';
import '../services/channel_service.dart';
import '../theme/tv_dimensions.dart';
import '../widgets/tv_channel_logo.dart';

/// Authentic JioTV+ TV Player Screen matching official design and Android TV guidelines:
/// - Top Bar: JioTV+ logo, < Back, TV Guide, Channel Info, Digital Clock
/// - Middle Left: Live badge, Channel No: Channel Name, Program Title, Genre/Language/Rating
/// - Center Controls:
///     Circular: Favorite, Prev, Play/Pause (Red Glowing Ring), Next, Volume/Mute
///     Pills: Quality, Audio, Subtitles, Guide, Aspect Ratio
/// - Timeline: Start/End times, Red progress bar with white scrubber knob,
///     Now Playing & Next program cards
/// - Bottom: "Similar Channels (Genre)" carousel with red focus borders
/// - Strict 3-zone Android TV D-Pad hierarchy:
///     Zone 1 (Top Bar) <-> Zone 2 (Controls Row) <-> Zone 3 (Carousel)
class PlayerScreen extends StatefulWidget {
  final Channel initialChannel;
  final Program? targetProgram;
  final ChannelService channelService;
  final VoidCallback onBack;

  const PlayerScreen({
    super.key,
    required this.initialChannel,
    this.targetProgram,
    required this.channelService,
    required this.onBack,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Channel _currentChannel;
  VideoPlayerController? _controller;
  bool _isPlaying = true;
  bool _isMuted = false;
  bool _isOsdVisible = true;
  bool _isMiniGuideVisible = false;
  Timer? _osdTimer;

  // Diagnostics and Error State
  bool _isConnecting = true;
  String? _errorMessage;
  String? _lastAttemptedUrl;
  bool _showDebugOverlay = false;

  // Video aspect ratio mode: BoxFit.contain (default fit) vs BoxFit.cover (16:9 fill)
  BoxFit _aspectRatioFit = BoxFit.contain;

  // Selected Quality, Audio & Subtitle
  String _selectedQuality = 'Auto (1080p)';
  String _selectedAudio = 'Hindi [Original]';
  String _selectedSubtitle = 'Off';
  bool _showQualityDialog = false;
  bool _showAudioDialog = false;
  bool _showSubtitleDialog = false;
  bool _showChannelInfoDialog = false;

  // EPG schedule for Mini Guide
  List<Program> _miniGuideSchedule = [];

  // ==================== Android TV Focus Nodes ====================
  // Zone 1: Top Bar
  late final FocusNode _topBackFocusNode;
  late final FocusNode _topTvGuideFocusNode;
  late final FocusNode _topChannelInfoFocusNode;

  // Zone 2: Controls Row
  late final FocusNode _favoriteFocusNode;
  late final FocusNode _prevChannelFocusNode;
  late final FocusNode _playPauseFocusNode;
  late final FocusNode _nextChannelFocusNode;
  late final FocusNode _volumeFocusNode;
  late final FocusNode _qualityFocusNode;
  late final FocusNode _audioFocusNode;
  late final FocusNode _subtitlesFocusNode;
  late final FocusNode _guideFocusNode;
  late final FocusNode _aspectRatioFocusNode;

  // Zone 3: Similar Channels Carousel
  final List<FocusNode> _carouselFocusNodes = [];
  final ScrollController _carouselScrollController = ScrollController();
  int _focusedCarouselIndex = 0;

  @override
  void initState() {
    super.initState();
    // Zone 1
    _topBackFocusNode = FocusNode(debugLabel: 'TopBack');
    _topTvGuideFocusNode = FocusNode(debugLabel: 'TopTvGuide');
    _topChannelInfoFocusNode = FocusNode(debugLabel: 'TopChannelInfo');

    // Zone 2
    _favoriteFocusNode = FocusNode(debugLabel: 'PlayerFavorite');
    _prevChannelFocusNode = FocusNode(debugLabel: 'PlayerPrev');
    _playPauseFocusNode = FocusNode(debugLabel: 'PlayerPlayPause');
    _nextChannelFocusNode = FocusNode(debugLabel: 'PlayerNext');
    _volumeFocusNode = FocusNode(debugLabel: 'PlayerVolume');
    _qualityFocusNode = FocusNode(debugLabel: 'PlayerQuality');
    _audioFocusNode = FocusNode(debugLabel: 'PlayerAudio');
    _subtitlesFocusNode = FocusNode(debugLabel: 'PlayerSubtitles');
    _guideFocusNode = FocusNode(debugLabel: 'PlayerGuide');
    _aspectRatioFocusNode = FocusNode(debugLabel: 'PlayerAspectRatio');

    _currentChannel = widget.initialChannel;
    _startPlayback();
    _loadMiniGuideSchedule();
    _resetOsdTimer();

    // Default Android TV initial focus on primary action: Play/Pause
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _osdTimer?.cancel();
    _controller?.dispose();
    _carouselScrollController.dispose();

    _topBackFocusNode.dispose();
    _topTvGuideFocusNode.dispose();
    _topChannelInfoFocusNode.dispose();

    _favoriteFocusNode.dispose();
    _prevChannelFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _nextChannelFocusNode.dispose();
    _volumeFocusNode.dispose();
    _qualityFocusNode.dispose();
    _audioFocusNode.dispose();
    _subtitlesFocusNode.dispose();
    _guideFocusNode.dispose();
    _aspectRatioFocusNode.dispose();

    for (final node in _carouselFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  Future<void> _loadMiniGuideSchedule() async {
    final schedule = await widget.channelService.getEpgForChannel(_currentChannel.channelId);
    if (mounted) {
      setState(() {
        _miniGuideSchedule = schedule;
      });
    }
  }

  Future<void> _startPlayback() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });
    final streamUrl = await widget.channelService.resolvePlaybackUrl(
      _currentChannel,
      program: widget.targetProgram,
    );
    _initPlayer(streamUrl);
  }

  Map<String, String> _buildPlayerHeaders(String streamUrl) {
    final uri = Uri.tryParse(streamUrl);
    final hdnea = uri?.queryParameters['hdnea'] ?? uri?.queryParameters['__hdnea__'] ?? '';
    return {
      'User-Agent': 'plaYtv/7.1.8 (Linux;Android 8.1.0) ExoPlayerLib/2.11.7',
      'Accept': '*/*',
      if (hdnea.isNotEmpty) 'Cookie': '__hdnea__=$hdnea',
    };
  }

  Future<void> _initPlayer(String streamUrl) async {
    _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _isConnecting = true;
        _errorMessage = null;
        _lastAttemptedUrl = streamUrl;
      });
    }

    final headers = _buildPlayerHeaders(streamUrl);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      httpHeaders: headers,
    );
    _controller = controller;

    controller.addListener(() {
      if (controller.value.hasError && mounted) {
        final err = controller.value.errorDescription ?? 'Unknown runtime streaming error';
        setState(() {
          _isConnecting = false;
          _errorMessage = _interpretErrorMessage(err, streamUrl);
        });
      }
    });

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      try {
        await controller.play();
      } catch (playErr) {
        await controller.setVolume(0.0);
        await controller.play();
      }

      if (mounted) {
        setState(() {
          _isPlaying = true;
          _isConnecting = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      final cleanName = _currentChannel.channelName
          .trim()
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
      final cdnUrl = 'https://jiotvcod.cdn.jio.com/bpk-tv/${cleanName}_MOB/Live/index.m3u8';

      if (streamUrl != cdnUrl) {
        final fallbackHeaders = _buildPlayerHeaders(cdnUrl);
        final fallbackController = VideoPlayerController.networkUrl(
          Uri.parse(cdnUrl),
          httpHeaders: fallbackHeaders,
        );
        _controller = fallbackController;

        try {
          await fallbackController.initialize();
          await fallbackController.setLooping(true);
          await fallbackController.setVolume(_isMuted ? 0.0 : 1.0);
          try {
            await fallbackController.play();
          } catch (_) {
            await fallbackController.setVolume(0.0);
            await fallbackController.play();
          }
          if (mounted) {
            setState(() {
              _isPlaying = true;
              _isConnecting = false;
              _errorMessage = null;
            });
          }
          return;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = _interpretErrorMessage(e.toString(), streamUrl);
        });
      }
    }
  }

  String _interpretErrorMessage(String rawError, String url) {
    if (rawError.contains('MEDIA_ERR_SRC_NOT_SUPPORTED') ||
        rawError.contains('DEMUXER_ERROR') ||
        rawError.contains('format not supported')) {
      return 'Desktop Web Browser Limitation.\n'
          'Desktop Chrome lacks native HLS (.m3u8) demuxing.\n'
          'Deploy to Android TV, Google TV, or an Android device for native ExoPlayer playback.';
    } else if (rawError.contains('403') || rawError.contains('Forbidden')) {
      return 'Stream Access Denied (HTTP 403 Forbidden).\n'
          'Live streams on Jio CDN are protected by Akamai EdgeAuth.\n'
          'Please ensure you are signed in with an active Jio mobile number to obtain signed playback tokens.';
    } else if (rawError.contains('400')) {
      return 'Playback Request Rejected (HTTP 400 Bad Request).\n'
          'The JioTV Playback API requires a valid subscriber session and parameters.';
    } else if (rawError.contains('CORS') || rawError.contains('Cross-Origin') || rawError.contains('Failed to fetch')) {
      return 'Network / CORS Policy Error.\n'
          'Browsers block cross-origin requests to Jio streaming CDNs on localhost.\n'
          'Please run on Android TV, mobile device, or with a backend proxy.';
    }
    return 'Stream playback error: $rawError';
  }

  void _switchChannel(Channel channel) async {
    setState(() {
      _currentChannel = channel;
      _isOsdVisible = true;
    });
    widget.channelService.tuneChannel(channel);
    _loadMiniGuideSchedule();
    final streamUrl = await widget.channelService.resolvePlaybackUrl(channel);
    _initPlayer(streamUrl);
    _resetOsdTimer();
  }

  void _tunePrevious() {
    widget.channelService.previousChannel();
    if (widget.channelService.currentChannel != null) {
      _switchChannel(widget.channelService.currentChannel!);
    }
  }

  void _tuneNext() {
    widget.channelService.nextChannel();
    if (widget.channelService.currentChannel != null) {
      _switchChannel(widget.channelService.currentChannel!);
    }
  }

  void _togglePlayPause() {
    if (_controller != null && _controller!.value.isInitialized) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        setState(() => _isPlaying = false);
      } else {
        _controller!.play();
        setState(() => _isPlaying = true);
      }
    }
    _resetOsdTimer();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller?.setVolume(_isMuted ? 0.0 : 1.0);
    });
    _resetOsdTimer();
  }

  void _toggleAspectRatio() {
    setState(() {
      _aspectRatioFit = (_aspectRatioFit == BoxFit.contain) ? BoxFit.cover : BoxFit.contain;
    });
    _resetOsdTimer();
  }

  void _resetOsdTimer() {
    _osdTimer?.cancel();
    final hasOpenDialog = _showQualityDialog ||
        _showAudioDialog ||
        _showSubtitleDialog ||
        _showChannelInfoDialog;

    if (_isOsdVisible && !hasOpenDialog) {
      _osdTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) {
          setState(() {
            _isOsdVisible = false;
            _isMiniGuideVisible = false;
          });
        }
      });
    }
  }

  void _toggleOsd() {
    setState(() {
      _isOsdVisible = !_isOsdVisible;
      if (!_isOsdVisible) _isMiniGuideVisible = false;
    });
    if (_isOsdVisible) {
      _resetOsdTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playPauseFocusNode.canRequestFocus) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
  }

  // ==================== Android TV Remote Hardware Handler ====================
  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    _resetOsdTimer();

    // 1. Modal dialog key handling: Escape / Back dismisses dialog
    if (_showQualityDialog || _showAudioDialog || _showSubtitleDialog || _showChannelInfoDialog) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        setState(() {
          _showQualityDialog = false;
          _showAudioDialog = false;
          _showSubtitleDialog = false;
          _showChannelInfoDialog = false;
        });
        _playPauseFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 2. Hardware TV Remote Back / Escape Key
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_isMiniGuideVisible) {
        setState(() => _isMiniGuideVisible = false);
        return KeyEventResult.handled;
      }
      if (_isOsdVisible) {
        setState(() => _isOsdVisible = false);
        return KeyEventResult.handled;
      }
      widget.onBack();
      return KeyEventResult.handled;
    }

    // 3. Physical Channel Up / Down keys
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      _tunePrevious();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      _tuneNext();
      return KeyEventResult.handled;
    }

    // 4. When OSD is HIDDEN:
    // Left/Right tunes previous/next. Center/Up/Down shows OSD and focuses Play/Pause.
    if (!_isOsdVisible) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _tunePrevious();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _tuneNext();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _toggleOsd();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final activeProgram = widget.targetProgram ?? _currentChannel.activeProgram;
    final now = DateTime.now();
    final timeFormat = DateFormat('hh:mm a');

    // Similar channels in same category (Image reference)
    final similarChannels = widget.channelService.allChannels
        .where((c) => c.channelId != _currentChannel.channelId && c.category == _currentChannel.category)
        .take(12)
        .toList();

    // Synchronize carousel focus nodes length
    while (_carouselFocusNodes.length < similarChannels.length) {
      final idx = _carouselFocusNodes.length;
      _carouselFocusNodes.add(FocusNode(debugLabel: 'CarouselChannel_$idx'));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showQualityDialog || _showAudioDialog || _showSubtitleDialog || _showChannelInfoDialog) {
          setState(() {
            _showQualityDialog = false;
            _showAudioDialog = false;
            _showSubtitleDialog = false;
            _showChannelInfoDialog = false;
          });
        } else if (_isMiniGuideVisible) {
          setState(() => _isMiniGuideVisible = false);
        } else if (_isOsdVisible) {
          setState(() => _isOsdVisible = false);
        } else {
          widget.onBack();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleRemoteKey,
          child: GestureDetector(
            onTap: _toggleOsd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ==================== 1. VIDEO LAYER ====================
                Center(
                  child: (_controller != null && _controller!.value.isInitialized)
                      ? SizedBox.expand(
                          child: FittedBox(
                            fit: _aspectRatioFit,
                            child: SizedBox(
                              width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1920,
                              height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 1080,
                              child: VideoPlayer(_controller!),
                            ),
                          ),
                        )
                      : (_errorMessage != null)
                          ? _buildErrorView()
                          : _buildConnectingView(),
                ),

                // ==================== 2. WATERMARK (Top Right) ====================
                if (!_isOsdVisible)
                  Positioned(
                    top: 24,
                    right: 36,
                    child: Opacity(
                      opacity: 0.85,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TvChannelLogo(
                            channel: _currentChannel,
                            height: 44,
                            fit: BoxFit.contain,
                          ),
                          if (_currentChannel.isHd) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'HD',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // ==================== 3. TOP BAR (Zone 1) ====================
                if (_isOsdVisible)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TvDimensions.overscanMargin,
                        vertical: 18,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xEB06070B),
                            Color(0x9906070B),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          // JioTV+ Brand Logo
                          Image.asset(
                            'assets/images/jiotv_plus_logo.png',
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _buildFallbackTopLogo(),
                          ),
                          const SizedBox(width: 16),

                          // < Back Button
                          _PlayerTopBarButton(
                            focusNode: _topBackFocusNode,
                            icon: Icons.chevron_left_rounded,
                            label: 'Back',
                            onPressed: widget.onBack,
                            onFocusChange: (f) {
                              if (f) _resetOsdTimer();
                            },
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _playPauseFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                _topTvGuideFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                          ),
                          const SizedBox(width: 10),

                          // [grid] TV Guide Button
                          _PlayerTopBarButton(
                            focusNode: _topTvGuideFocusNode,
                            icon: Icons.grid_view_rounded,
                            label: 'TV Guide',
                            isActive: _isMiniGuideVisible,
                            onPressed: () {
                              setState(() => _isMiniGuideVisible = !_isMiniGuideVisible);
                              _resetOsdTimer();
                            },
                            onFocusChange: (f) {
                              if (f) _resetOsdTimer();
                            },
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _playPauseFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                _topBackFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                _topChannelInfoFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                          ),
                          const SizedBox(width: 10),

                          // (i) Channel Info Button
                          _PlayerTopBarButton(
                            focusNode: _topChannelInfoFocusNode,
                            icon: Icons.info_outline_rounded,
                            label: 'Channel Info',
                            onPressed: () {
                              setState(() => _showChannelInfoDialog = true);
                              _resetOsdTimer();
                            },
                            onFocusChange: (f) {
                              if (f) _resetOsdTimer();
                            },
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) return KeyEventResult.ignored;
                              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                _qualityFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                _topTvGuideFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                          ),

                          const Spacer(),

                          // Clock
                          Text(
                            timeFormat.format(now),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ==================== 4. WATERMARK WITH HD (Top Right in OSD) ====================
                if (_isOsdVisible)
                  Positioned(
                    top: 72,
                    right: TvDimensions.overscanMargin,
                    child: Opacity(
                      opacity: 0.9,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TvChannelLogo(
                            channel: _currentChannel,
                            height: 48,
                            fit: BoxFit.contain,
                          ),
                          if (_currentChannel.isHd) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'HD',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // ==================== 5. MINI TV GUIDE OVERLAY ====================
                if (_isOsdVisible && _isMiniGuideVisible)
                  Positioned(
                    bottom: 24,
                    left: TvDimensions.overscanMargin,
                    right: TvDimensions.overscanMargin,
                    child: _buildMiniGuide(activeProgram, now, timeFormat),
                  ),

                // ==================== 6. BOTTOM OSD HUD (Zones 2 & 3) ====================
                if (_isOsdVisible && !_isMiniGuideVisible)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TvDimensions.overscanMargin,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xFA06070B),
                            Color(0xEB06070B),
                            Color(0x9906070B),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---------------- Row A: Info & Playback Controls (Zone 2) ----------------
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Middle Left Info
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // LIVE Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE50914),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 5),
                                          const Text(
                                            'LIVE',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    // Channel Number & Title
                                    Text(
                                      '${_currentChannel.channelNo}: ${_currentChannel.channelName}',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),

                                    // Program Subtitle
                                    Text(
                                      activeProgram.title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),

                                    // Metadata
                                    Text(
                                      '${_currentChannel.category}  |  ${_currentChannel.language}  |  U/A 7+',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 16),

                              // Playback Controls Row (Zone 2)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 1. Favorite Button (♡)
                                  _PlayerCircleButton(
                                    focusNode: _favoriteFocusNode,
                                    icon: _currentChannel.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    iconColor: _currentChannel.isFavorite ? const Color(0xFFE50914) : Colors.white,
                                    onPressed: () async {
                                      await widget.channelService.toggleFavorite(_currentChannel);
                                      setState(() {});
                                      _resetOsdTimer();
                                    },
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topBackFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _prevChannelFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // 2. Previous Channel (|◀)
                                  _PlayerCircleButton(
                                    focusNode: _prevChannelFocusNode,
                                    icon: Icons.skip_previous_rounded,
                                    onPressed: _tunePrevious,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topBackFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _favoriteFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _playPauseFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // 3. Play / Pause Button (Centerpiece with Radiant Red Glow Ring)
                                  _PlayerCircleButton(
                                    focusNode: _playPauseFocusNode,
                                    size: 54,
                                    iconSize: 28,
                                    isPrimaryPlayPause: true,
                                    icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    onPressed: _togglePlayPause,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topBackFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _prevChannelFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _nextChannelFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // 4. Next Channel (▶|)
                                  _PlayerCircleButton(
                                    focusNode: _nextChannelFocusNode,
                                    icon: Icons.skip_next_rounded,
                                    onPressed: _tuneNext,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topTvGuideFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _playPauseFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _volumeFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 10),

                                  // 5. Volume / Mute Button (🔊)
                                  _PlayerCircleButton(
                                    focusNode: _volumeFocusNode,
                                    icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                    onPressed: _toggleMute,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topTvGuideFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _nextChannelFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _qualityFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 18),

                                  // 6. Quality Pill Button
                                  _PlayerPillButton(
                                    focusNode: _qualityFocusNode,
                                    icon: Icons.settings_outlined,
                                    label: 'Quality',
                                    onPressed: () {
                                      setState(() => _showQualityDialog = true);
                                      _resetOsdTimer();
                                    },
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topChannelInfoFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _volumeFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _audioFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // 7. Audio Pill Button
                                  _PlayerPillButton(
                                    focusNode: _audioFocusNode,
                                    icon: Icons.volume_up_outlined,
                                    label: 'Audio',
                                    onPressed: () {
                                      setState(() => _showAudioDialog = true);
                                      _resetOsdTimer();
                                    },
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topChannelInfoFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _qualityFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _subtitlesFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // 8. Subtitles Pill Button
                                  _PlayerPillButton(
                                    focusNode: _subtitlesFocusNode,
                                    icon: Icons.subtitles_outlined,
                                    label: 'Subtitles',
                                    onPressed: () {
                                      setState(() => _showSubtitleDialog = true);
                                      _resetOsdTimer();
                                    },
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topChannelInfoFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _audioFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _guideFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // 9. Guide Pill Button
                                  _PlayerPillButton(
                                    focusNode: _guideFocusNode,
                                    icon: Icons.calendar_today_outlined,
                                    label: 'Guide',
                                    isActive: _isMiniGuideVisible,
                                    onPressed: () {
                                      setState(() => _isMiniGuideVisible = !_isMiniGuideVisible);
                                      _resetOsdTimer();
                                    },
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topChannelInfoFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _subtitlesFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                        _aspectRatioFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                  const SizedBox(width: 8),

                                  // 10. Aspect Ratio / Fullscreen Button
                                  _PlayerPillButton(
                                    focusNode: _aspectRatioFocusNode,
                                    icon: Icons.aspect_ratio_rounded,
                                    onPressed: _toggleAspectRatio,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onKeyEvent: (node, event) {
                                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                        _topChannelInfoFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                        _focusCarousel();
                                        return KeyEventResult.handled;
                                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                        _guideFocusNode.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      return KeyEventResult.ignored;
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // ---------------- Row B: Timeline & Now Playing / Next ----------------
                          _buildTimelineRow(activeProgram, timeFormat),

                          const SizedBox(height: 14),

                          // ---------------- Row C: Similar Channels Carousel (Zone 3) ----------------
                          Text(
                            'Similar Channels (${_currentChannel.category})',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),

                          SizedBox(
                            height: 104,
                            child: ListView.separated(
                              controller: _carouselScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: similarChannels.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final simChannel = similarChannels[index];
                                final fNode = _carouselFocusNodes[index];

                                return _SimilarChannelCard(
                                  channel: simChannel,
                                  focusNode: fNode,
                                  onPressed: () => _switchChannel(simChannel),
                                  onFocusChange: (hasF) {
                                    if (hasF) {
                                      _focusedCarouselIndex = index;
                                      _resetOsdTimer();
                                      Scrollable.ensureVisible(
                                        context,
                                        alignment: 0.3,
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                      );
                                    }
                                  },
                                  onKeyEvent: (node, event) {
                                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                      _playPauseFocusNode.requestFocus();
                                      return KeyEventResult.handled;
                                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
                                      _carouselFocusNodes[index - 1].requestFocus();
                                      return KeyEventResult.handled;
                                    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                                        index < similarChannels.length - 1) {
                                      _carouselFocusNodes[index + 1].requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ==================== 7. MODAL DIALOGS ====================
                // Quality Dialog
                if (_showQualityDialog)
                  _buildSelectionModal(
                    title: 'Select Video Quality',
                    options: ['Auto (1080p)', 'High (1080p)', 'Medium (720p)', 'Low (480p)'],
                    selected: _selectedQuality,
                    onSelected: (val) {
                      setState(() {
                        _selectedQuality = val;
                        _showQualityDialog = false;
                      });
                      _qualityFocusNode.requestFocus();
                      _resetOsdTimer();
                    },
                    onClose: () {
                      setState(() => _showQualityDialog = false);
                      _qualityFocusNode.requestFocus();
                    },
                  ),

                // Audio Dialog
                if (_showAudioDialog)
                  _buildSelectionModal(
                    title: 'Select Audio Language',
                    options: ['Hindi [Original]', 'English', 'Tamil', 'Telugu'],
                    selected: _selectedAudio,
                    onSelected: (val) {
                      setState(() {
                        _selectedAudio = val;
                        _showAudioDialog = false;
                      });
                      _audioFocusNode.requestFocus();
                      _resetOsdTimer();
                    },
                    onClose: () {
                      setState(() => _showAudioDialog = false);
                      _audioFocusNode.requestFocus();
                    },
                  ),

                // Subtitle Dialog
                if (_showSubtitleDialog)
                  _buildSelectionModal(
                    title: 'Subtitles & Closed Captions',
                    options: ['Off', 'English [CC]', 'Hindi [CC]'],
                    selected: _selectedSubtitle,
                    onSelected: (val) {
                      setState(() {
                        _selectedSubtitle = val;
                        _showSubtitleDialog = false;
                      });
                      _subtitlesFocusNode.requestFocus();
                      _resetOsdTimer();
                    },
                    onClose: () {
                      setState(() => _showSubtitleDialog = false);
                      _subtitlesFocusNode.requestFocus();
                    },
                  ),

                // Channel Info Dialog
                if (_showChannelInfoDialog)
                  _buildChannelInfoModal(activeProgram),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _focusCarousel() {
    if (_carouselFocusNodes.isNotEmpty) {
      final targetIdx = _focusedCarouselIndex.clamp(0, _carouselFocusNodes.length - 1);
      _carouselFocusNodes[targetIdx].requestFocus();
    }
  }

  Widget _buildTimelineRow(Program activeProgram, DateFormat timeFormat) {
    final now = DateTime.now();
    final totalDuration = activeProgram.endTime.difference(activeProgram.startTime).inSeconds;
    final elapsed = now.difference(activeProgram.startTime).inSeconds;
    final progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.45;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline bar with start and end times
        Row(
          children: [
            Text(
              timeFormat.format(activeProgram.startTime),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final knobLeft = (barWidth * progress) - 6;

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      // Background Track
                      Container(
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Red Progress Bar
                      Container(
                        height: 3.5,
                        width: barWidth * progress,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // White Scrubber Knob
                      Positioned(
                        left: knobLeft.clamp(0.0, barWidth - 12),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(width: 12),
            Text(
              timeFormat.format(activeProgram.endTime),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Now Playing & Next Programs Display
        Row(
          children: [
            // "Now Playing" Label & Card
            const Text(
              'Now Playing',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFF223F)),
            ),
            const SizedBox(width: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xCC12151E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvChannelLogo(channel: _currentChannel, height: 20, fit: BoxFit.contain),
                  const SizedBox(width: 8),
                  Text(
                    activeProgram.title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${timeFormat.format(activeProgram.startTime)} – ${timeFormat.format(activeProgram.endTime)}',
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 20),

            // "Next" Label & Program
            Text(
              'Next',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(width: 8),
            Text(
              _miniGuideSchedule.length > 1 ? _miniGuideSchedule[1].title : 'Desh Duniya',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Text(
              _miniGuideSchedule.length > 1
                  ? '${timeFormat.format(_miniGuideSchedule[1].startTime)} – ${timeFormat.format(_miniGuideSchedule[1].endTime)}'
                  : '08:00 PM – 08:30 PM',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniGuide(Program activeProgram, DateTime now, DateFormat timeFormat) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFA0E1018),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Left: Channel Logo & Poster Container
          Container(
            width: 140,
            decoration: BoxDecoration(
              color: const Color(0xFF1B1E2B),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Center(
              child: TvChannelLogo(
                channel: _currentChannel,
                height: 52,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Right: Schedule Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '< ${_currentChannel.channelNo} ${_currentChannel.channelName} >',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    Text(
                      timeFormat.format(now),
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Active Program (Blue Bar)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E63FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activeProgram.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        '${timeFormat.format(activeProgram.startTime)} - ${timeFormat.format(activeProgram.endTime)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Next Show
                if (_miniGuideSchedule.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _miniGuideSchedule[1].title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                        Text(
                          '${timeFormat.format(_miniGuideSchedule[1].startTime)} - ${timeFormat.format(_miniGuideSchedule[1].endTime)}',
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackTopLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0xFFE50914),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            'Jio',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'TV+',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
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
        width: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF141722),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF1E42), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                GestureDetector(
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...options.map((opt) {
              final isSelected = opt == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ModalOptionTile(
                  title: opt,
                  isSelected: isSelected,
                  onPressed: () => onSelected(opt),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelInfoModal(Program activeProgram) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF141722),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF1E42), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TvChannelLogo(channel: _currentChannel, height: 40, fit: BoxFit.contain),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentChannel.channelNo}: ${_currentChannel.channelName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        activeProgram.title,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() => _showChannelInfoDialog = false);
                    _topChannelInfoFocusNode.requestFocus();
                  },
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 14),

            _buildInfoRow('Genre', _currentChannel.category),
            _buildInfoRow('Language', _currentChannel.language),
            _buildInfoRow('Video Quality', _currentChannel.isHd ? '1080p Full HD (60fps)' : 'Standard Definition'),
            _buildInfoRow('Audio Track', _selectedAudio),
            _buildInfoRow('Subtitles', _selectedSubtitle),
            _buildInfoRow('Broadcast', 'Live Jio HLS CDN Stream'),

            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  setState(() => _showChannelInfoDialog = false);
                  _topChannelInfoFocusNode.requestFocus();
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.white60)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildConnectingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvChannelLogo(
              channel: _currentChannel,
              height: 56,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
            if (_isConnecting) ...[
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(color: Color(0xFFE50914), strokeWidth: 3),
              ),
              const SizedBox(height: 14),
              Text('Connecting to ${_currentChannel.channelName}...',
                  style: const TextStyle(fontSize: 14, color: Colors.white70)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvChannelLogo(
                channel: _currentChannel,
                height: 52,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Unable to Play ${_currentChannel.channelName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Stream playback failed.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _startPlayback,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Stream'),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: widget.onBack,
                    child: const Text('Back to Guide'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showDebugOverlay = !_showDebugOverlay),
                    child: Text(_showDebugOverlay ? 'Hide Debug' : 'Debug Info',
                        style: const TextStyle(color: Colors.white54)),
                  ),
                ],
              ),

              if (_showDebugOverlay) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('TECHNICAL DEBUG LOGS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.amber)),
                      const SizedBox(height: 6),
                      Text('Channel ID: ${_currentChannel.channelId}',
                          style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      Text('Last Target URL: ${_lastAttemptedUrl ?? "None"}',
                          style: const TextStyle(fontSize: 10, color: Colors.white60)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== TV UI WIDGETS ====================

/// Circular Media Button with Red Glow Focus & Android TV Remote Support
class _PlayerCircleButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;
  final double size;
  final double iconSize;
  final Color iconColor;
  final bool isPrimaryPlayPause;

  const _PlayerCircleButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
    this.onKeyEvent,
    this.onFocusChange,
    this.size = 42,
    this.iconSize = 20,
    this.iconColor = Colors.white,
    this.isPrimaryPlayPause = false,
  });

  @override
  State<_PlayerCircleButton> createState() => _PlayerCircleButtonState();
}

class _PlayerCircleButtonState extends State<_PlayerCircleButton> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != widget.focusNode.hasFocus) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      widget.onFocusChange?.call(_isFocused);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res != KeyEventResult.ignored) return res;
    }

    final isAction = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isAction) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onPressed();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isFocused ? (_isPressed ? 1.02 : (widget.isPrimaryPlayPause ? 1.12 : 1.08)) : 1.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isPrimaryPlayPause
                  ? (_isFocused ? const Color(0xFF261014) : const Color(0xE614161F))
                  : (_isFocused ? const Color(0xFF261014) : const Color(0xCC181A22)),
              border: Border.all(
                color: widget.isPrimaryPlayPause
                    ? (_isFocused ? Colors.white : const Color(0xFFFF1E42))
                    : (_isFocused ? const Color(0xFFFF1E42) : Colors.white.withValues(alpha: 0.1)),
                width: widget.isPrimaryPlayPause ? 2.5 : (_isFocused ? 2.0 : 1.0),
              ),
              boxShadow: (widget.isPrimaryPlayPause || _isFocused)
                  ? [
                      BoxShadow(
                        color: const Color(0x66FF1E42),
                        blurRadius: _isFocused ? 16 : 10,
                        spreadRadius: _isFocused ? 2 : 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                widget.icon,
                color: widget.iconColor,
                size: widget.iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill Action Button for Quality, Audio, Subtitles, Guide, Aspect Ratio
class _PlayerPillButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String? label;
  final bool isActive;
  final VoidCallback onPressed;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;

  const _PlayerPillButton({
    required this.focusNode,
    required this.icon,
    this.label,
    this.isActive = false,
    required this.onPressed,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  State<_PlayerPillButton> createState() => _PlayerPillButtonState();
}

class _PlayerPillButtonState extends State<_PlayerPillButton> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != widget.focusNode.hasFocus) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      widget.onFocusChange?.call(_isFocused);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res != KeyEventResult.ignored) return res;
    }

    final isAction = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isAction) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onPressed();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isFocused ? (_isPressed ? 1.02 : 1.06) : 1.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: widget.label != null ? 12 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: widget.isActive
                  ? const Color(0xFF2E63FF)
                  : (_isFocused ? const Color(0xFF261014) : const Color(0xCC181A22)),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFFFF1E42)
                    : (widget.isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.1)),
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? const [
                      BoxShadow(
                        color: Color(0x66FF1E42),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 17),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top Bar Action Pill (< Back, TV Guide, Channel Info)
class _PlayerTopBarButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;

  const _PlayerTopBarButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onPressed,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  State<_PlayerTopBarButton> createState() => _PlayerTopBarButtonState();
}

class _PlayerTopBarButtonState extends State<_PlayerTopBarButton> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != widget.focusNode.hasFocus) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      widget.onFocusChange?.call(_isFocused);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res != KeyEventResult.ignored) return res;
    }

    final isAction = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isAction) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onPressed();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isFocused ? (_isPressed ? 1.02 : 1.06) : 1.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: widget.isActive
                  ? const Color(0xFF2E63FF)
                  : (_isFocused ? const Color(0xFF261014) : const Color(0x8014161F)),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFFFF1E42)
                    : (widget.isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.15)),
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? const [
                      BoxShadow(
                        color: Color(0x66FF1E42),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Similar Channel Carousel Card with Glowing Red Focus Ring (Zone 3)
class _SimilarChannelCard extends StatefulWidget {
  final Channel channel;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocusChange;
  final FocusOnKeyEventCallback? onKeyEvent;

  const _SimilarChannelCard({
    required this.channel,
    required this.focusNode,
    required this.onPressed,
    this.onFocusChange,
    this.onKeyEvent,
  });

  @override
  State<_SimilarChannelCard> createState() => _SimilarChannelCardState();
}

class _SimilarChannelCardState extends State<_SimilarChannelCard> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != widget.focusNode.hasFocus) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
      widget.onFocusChange?.call(_isFocused);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onKeyEvent != null) {
      final res = widget.onKeyEvent!(node, event);
      if (res != KeyEventResult.ignored) return res;
    }

    final isAction = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isAction) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onPressed();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isFocused ? (_isPressed ? 1.02 : 1.06) : 1.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 122,
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _isFocused ? const Color(0xFF1E1418) : const Color(0xEB11141D),
              border: Border.all(
                color: _isFocused ? const Color(0xFFFF1E42) : Colors.white.withValues(alpha: 0.08),
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? const [
                      BoxShadow(
                        color: Color(0x66FF1E42),
                        blurRadius: 14,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                // Live Tag
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '● LIVE',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),

                // Channel Logo in Center
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                    child: TvChannelLogo(
                      channel: widget.channel,
                      height: 38,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Channel No & Name
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.channel.channelNo}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70),
                      ),
                      Text(
                        widget.channel.channelName,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalOptionTile extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onPressed;

  const _ModalOptionTile({
    required this.title,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  State<_ModalOptionTile> createState() => _ModalOptionTileState();
}

class _ModalOptionTileState extends State<_ModalOptionTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFFE50914)
                : (_isFocused ? Colors.white24 : Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              if (widget.isSelected) const Icon(Icons.check_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
