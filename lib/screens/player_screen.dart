import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../models/channel.dart';
import '../models/program.dart';
import '../services/channel_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../theme/tv_typography.dart';
import '../widgets/tv_badge.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/tv_channel_logo.dart';

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
  bool _isOsdVisible = true;
  bool _isMiniGuideVisible = false; // Mode matching Image 3 vs Image 4
  Timer? _osdTimer;

  // Diagnostics and Error State
  bool _isConnecting = true;
  String? _errorMessage;
  String? _lastAttemptedUrl;
  bool _showDebugOverlay = false;

  // Selected Quality & Audio
  String _selectedQuality = 'Auto (1080p)';
  String _selectedAudio = 'Hindi [Original]';
  bool _showQualityDialog = false;
  bool _showAudioDialog = false;

  // Dedicated TV Focus Nodes for D-pad remote navigation
  late final FocusNode _playPauseFocusNode;
  late final FocusNode _settingsFocusNode;
  late final FocusNode _audioFocusNode;
  late final FocusNode _favoriteFocusNode;
  late final FocusNode _guideFocusNode;

  // EPG schedule for Mini Guide (Image 3 reference)
  List<Program> _miniGuideSchedule = [];

  @override
  void initState() {
    super.initState();
    _playPauseFocusNode = FocusNode(debugLabel: 'PlayerPlayPause');
    _settingsFocusNode = FocusNode(debugLabel: 'PlayerSettings');
    _audioFocusNode = FocusNode(debugLabel: 'PlayerAudio');
    _favoriteFocusNode = FocusNode(debugLabel: 'PlayerFavorite');
    _guideFocusNode = FocusNode(debugLabel: 'PlayerGuide');

    _currentChannel = widget.initialChannel;
    _startPlayback();
    _loadMiniGuideSchedule();
    _resetOsdTimer();
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
    debugPrint('==================== [PlayerScreen] Init Player ====================');
    debugPrint('[PlayerScreen] Target Channel: [${_currentChannel.channelNo}] ${_currentChannel.channelName} (ID: ${_currentChannel.channelId})');
    debugPrint('[PlayerScreen] Resolving stream URL: $streamUrl');

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
    debugPrint('[PlayerScreen] Player Request Headers: $headers');

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      httpHeaders: headers,
    );
    _controller = controller;

    // Attach runtime listener for asynchronous playback errors
    controller.addListener(() {
      if (controller.value.hasError && mounted) {
        final err = controller.value.errorDescription ?? 'Unknown runtime streaming error';
        debugPrint('❌ [PlayerScreen] VideoPlayerController runtime error: $err');
        setState(() {
          _isConnecting = false;
          _errorMessage = _interpretErrorMessage(err, streamUrl);
        });
      }
    });

    try {
      debugPrint('[PlayerScreen] Calling controller.initialize()...');
      await controller.initialize();
      debugPrint('✅ [PlayerScreen] VideoPlayerController initialized successfully! Aspect ratio: ${controller.value.aspectRatio}');

      await controller.setLooping(true);
      try {
        await controller.play();
      } catch (playErr) {
        debugPrint('⚠️ [PlayerScreen] Autoplay failed, trying muted playback: $playErr');
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
    } catch (e, stack) {
      debugPrint('❌ [PlayerScreen] Primary stream initialization failed with error: $e');
      debugPrint('StackTrace: $stack');

      // If primary playback fails, attempt direct live broadcast CDN stream without mock videos
      final cleanName = _currentChannel.channelName
          .trim()
          .replaceAll(RegExp(r'\s+'), '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
      final cdnUrl = 'https://jiotvcod.cdn.jio.com/bpk-tv/${cleanName}_MOB/Live/index.m3u8';

      if (streamUrl != cdnUrl) {
        debugPrint('⚠️ [PlayerScreen] Attempting direct CDN stream fallback: $cdnUrl');
        final fallbackHeaders = _buildPlayerHeaders(cdnUrl);
        final fallbackController = VideoPlayerController.networkUrl(
          Uri.parse(cdnUrl),
          httpHeaders: fallbackHeaders,
        );
        _controller = fallbackController;

        fallbackController.addListener(() {
          if (fallbackController.value.hasError && mounted) {
            final err = fallbackController.value.errorDescription ?? 'Runtime playback stream error';
            debugPrint('❌ [PlayerScreen] Fallback controller runtime error: $err');
            setState(() {
              _isConnecting = false;
              _errorMessage = _interpretErrorMessage(err, cdnUrl);
            });
          }
        });

        try {
          await fallbackController.initialize();
          debugPrint('✅ [PlayerScreen] Fallback CDN stream initialized successfully!');
          await fallbackController.setLooping(true);
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
        } catch (fallbackErr) {
          debugPrint('❌ [PlayerScreen] Fallback CDN stream failed: $fallbackErr');
          debugPrint('💡 [PlayerScreen] Direct CDN stream on Jio COD returns 403 Forbidden without valid Akamai token (?hdnea=...).');
        }
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = _interpretErrorMessage(e.toString(), streamUrl);
        });
      }
    }

    if (mounted) setState(() {});
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

  void _resetOsdTimer() {
    _osdTimer?.cancel();
    if (_isOsdVisible && !_showQualityDialog && !_showAudioDialog) {
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

  @override
  void dispose() {
    _osdTimer?.cancel();
    _controller?.dispose();
    _playPauseFocusNode.dispose();
    _settingsFocusNode.dispose();
    _audioFocusNode.dispose();
    _favoriteFocusNode.dispose();
    _guideFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleRemoteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Reset OSD timer on any user interaction so HUD doesn't close mid-navigation
    _resetOsdTimer();

    // 1. Modal dialog key handling
    if (_showQualityDialog || _showAudioDialog) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        setState(() {
          _showQualityDialog = false;
          _showAudioDialog = false;
        });
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

    // 3. Physical Channel Up / Down keys (PageUp / PageDown / ChannelUp / ChannelDown)
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      widget.channelService.previousChannel();
      if (widget.channelService.currentChannel != null) {
        _switchChannel(widget.channelService.currentChannel!);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.channelDown) {
      widget.channelService.nextChannel();
      if (widget.channelService.currentChannel != null) {
        _switchChannel(widget.channelService.currentChannel!);
      }
      return KeyEventResult.handled;
    }

    // 4. When OSD is HIDDEN:
    // Left / Right switches channel. Center / Up / Down shows OSD & focuses primary action button.
    if (!_isOsdVisible) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.channelService.previousChannel();
        if (widget.channelService.currentChannel != null) {
          _switchChannel(widget.channelService.currentChannel!);
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        widget.channelService.nextChannel();
        if (widget.channelService.currentChannel != null) {
          _switchChannel(widget.channelService.currentChannel!);
        }
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

    // 5. When OSD IS VISIBLE:
    // Do NOT swallow arrowLeft, arrowRight, arrowUp, or arrowDown!
    // Return ignored so that D-pad traverses focus into Settings, Audio, Favorite, and Similar Channels carousel!
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final activeProgram = widget.targetProgram ?? _currentChannel.activeProgram;
    final now = DateTime.now();
    final timeFormat = DateFormat('hh:mm a');
    final dateFormat = DateFormat('EEE d MMM');

    // Similar channels in same category (Image 4 reference)
    final similarChannels = widget.channelService.allChannels
        .where((c) => c.channelId != _currentChannel.channelId && c.category == _currentChannel.category)
        .take(12)
        .toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isMiniGuideVisible) {
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
                // 1. VIDEO LAYER
                Center(
                  child: (_controller != null && _controller!.value.isInitialized)
                      ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        )
                      : (_errorMessage != null)
                          ? _buildErrorView()
                          : _buildConnectingView(),
                ),

                // 2. TOP GRADIENT & TOP BUTTONS (Image 3 reference: "Switch to JioTV+", "TV GUIDE")
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
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          // Top Back Button
                          TvFocusable(
                            onPressed: widget.onBack,
                            borderRadius: BorderRadius.circular(20),
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedArrowLeft01,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Back',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // "TV GUIDE" button (Image 3 reference)
                          TvFocusable(
                            onPressed: () {
                              setState(() => _isMiniGuideVisible = !_isMiniGuideVisible);
                              _resetOsdTimer();
                            },
                            borderRadius: BorderRadius.circular(20),
                            backgroundColor: _isMiniGuideVisible
                                ? const Color(0xFF2E63FF)
                                : Colors.black.withValues(alpha: 0.6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: const Row(
                              children: [
                                Text(
                                  'TV GUIDE',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Sync button (Image 3 reference)
                          TvFocusable(
                            onPressed: () => _switchChannel(_currentChannel),
                            borderRadius: BorderRadius.circular(20),
                            backgroundColor: const Color(0xFF2E63FF),
                            padding: const EdgeInsets.all(8),
                            child: const HugeIcon(
                              icon: HugeIcons.strokeRoundedPlay,
                              color: Colors.white,
                              size: 14,
                            ),
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

                // 3. MINI TV GUIDE OVERLAY (Image 3 Reference)
                if (_isOsdVisible && _isMiniGuideVisible)
                  Positioned(
                    bottom: 24,
                    left: TvDimensions.overscanMargin,
                    right: TvDimensions.overscanMargin,
                    child: Container(
                      height: 190,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          // Left: Show Poster Card (Image 3 reference: Anupamaa poster)
                          Container(
                            width: 150,
                            decoration: BoxDecoration(
                              color: TvColors.bgSurface2,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (activeProgram.thumbnailUrl != null && activeProgram.thumbnailUrl!.isNotEmpty)
                                  Image.network(
                                    activeProgram.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: TvChannelLogo(
                                        channel: _currentChannel,
                                        height: 40,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                else
                                  Center(
                                    child: TvChannelLogo(
                                      channel: _currentChannel,
                                      height: 40,
                                      fit: BoxFit.contain,
                                    ),
                                  ),

                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    color: Colors.black.withValues(alpha: 0.8),
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '45 min remaining',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                        Text(
                                          'Currently Playing',
                                          style: TextStyle(fontSize: 9, color: TvColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Center & Right: Schedule Rows (Image 3 reference: < 115 Star Plus HD >, Anupamaa highlighted in blue)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '< ${_currentChannel.channelNo} ${_currentChannel.channelName} >',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '${dateFormat.format(now)} ${timeFormat.format(now)}',
                                      style: const TextStyle(fontSize: 13, color: TvColors.textSecondary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                // Currently Playing Highlighted Blue Bar (Image 3 reference)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2E63FF),
                                    borderRadius: BorderRadius.circular(10),
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

                                // Next Upcoming Show (Image 3 reference: "Jhanak 01:00 PM - 02:00 PM")
                                if (_miniGuideSchedule.length > 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(10),
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
                                          style: const TextStyle(fontSize: 12, color: TvColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),

                                const Spacer(),
                                const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('🔴', style: TextStyle(fontSize: 10)),
                                      SizedBox(width: 4),
                                      Text(
                                        'LiveTV',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
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

                // 4. BOTTOM OSD HUD MATCHING REFERENCE IMAGE 4
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
                            Color(0xFA08090C),
                            Color(0xCC08090C),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Channel & Program Title Row (Image 4 reference: "625: News 18 India", "Aar Paar", "12:28 PM")
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_currentChannel.channelNo}: ${_currentChannel.channelName}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    activeProgram.title,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    timeFormat.format(now),
                                    style: const TextStyle(fontSize: 12, color: TvColors.textSecondary),
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // Action Controls: Play/Pause, Quality, Audio, Favorite, TV Guide, HD, LIVE
                              Row(
                                children: [
                                  // 1. Play / Pause Button
                                  TvFocusable(
                                    focusNode: _playPauseFocusNode,
                                    autofocus: true,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onPressed: () {
                                      if (_controller != null && _controller!.value.isInitialized) {
                                        if (_controller!.value.isPlaying) {
                                          _controller!.pause();
                                          setState(() => _isPlaying = false);
                                        } else {
                                          _controller!.play();
                                          setState(() => _isPlaying = true);
                                        }
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: _isPlaying ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _isPlaying ? 'Pause' : 'Play',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 2. Video Quality / Settings
                                  TvFocusable(
                                    focusNode: _settingsFocusNode,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onPressed: () => setState(() => _showQualityDialog = true),
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedSettings02,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Quality',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 3. Audio & Subtitles
                                  TvFocusable(
                                    focusNode: _audioFocusNode,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onPressed: () => setState(() => _showAudioDialog = true),
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedVolumeHigh,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Audio',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 4. Favorite Toggle Button
                                  TvFocusable(
                                    focusNode: _favoriteFocusNode,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onPressed: () async {
                                      await widget.channelService.toggleFavorite(_currentChannel);
                                      setState(() {});
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedStar,
                                          color: _currentChannel.isFavorite ? TvColors.reminderYellow : Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _currentChannel.isFavorite ? 'Favorited' : 'Favorite',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: _currentChannel.isFavorite ? TvColors.reminderYellow : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // 5. TV Guide Toggle
                                  TvFocusable(
                                    focusNode: _guideFocusNode,
                                    onFocusChange: (f) {
                                      if (f) _resetOsdTimer();
                                    },
                                    onPressed: () {
                                      setState(() => _isMiniGuideVisible = !_isMiniGuideVisible);
                                      _resetOsdTimer();
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: _isMiniGuideVisible
                                        ? const Color(0xFF2E63FF)
                                        : Colors.white.withValues(alpha: 0.12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        HugeIcon(
                                          icon: HugeIcons.strokeRoundedCalendar03,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Guide',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // HD Badge
                                  if (_currentChannel.isHd) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                      ),
                                      child: const Text(
                                        'HD',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],

                                  // LIVE Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: TvColors.liveRed,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      '● LIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Timeline Progress Bar with Program Tag Badge (Image 4 reference)
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: activeProgram.progressFraction,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  color: const Color(0xFF2E63FF),
                                  minHeight: 4,
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E50F0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${timeFormat.format(activeProgram.startTime)} | ${activeProgram.title}',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // "Similar Channels" Section Header (Image 4 reference)
                          Row(
                            children: [
                              const HugeIcon(
                                icon: HugeIcons.strokeRoundedTv01,
                                color: TvColors.accentCyan,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Similar Channels (${_currentChannel.category})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // "Similar Channels" Carousel (Image 4 reference)
                          SizedBox(
                            height: 90,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: similarChannels.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final simChannel = similarChannels[index];

                                return TvFocusable(
                                  onPressed: () => _switchChannel(simChannel),
                                  onFocusChange: (hasF) {
                                    if (hasF) _resetOsdTimer();
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  backgroundColor: TvColors.bgSurface2,
                                  focusedBackgroundColor: TvColors.bgSurface3,
                                  focusedBorderColor: TvColors.accentCyan,
                                  padding: const EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 135,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Channel Number Badge
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.7),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${simChannel.channelNo}',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                                            ),
                                          ),
                                        ),

                                        // LIVE Badge
                                        const Positioned(
                                          top: 0,
                                          right: 0,
                                          child: TvLiveBadge(size: 6),
                                        ),

                                        // Center Logo
                                        Center(
                                          child: TvChannelLogo(
                                            channel: simChannel,
                                            height: 42,
                                            fit: BoxFit.contain,
                                          ),
                                        ),

                                        // Bottom Channel Name
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            color: Colors.black.withValues(alpha: 0.6),
                                            child: Text(
                                              simChannel.channelName,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
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
                    ),
                  ),

                // 5. QUALITY MODAL
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
                      _resetOsdTimer();
                    },
                    onClose: () => setState(() => _showQualityDialog = false),
                  ),

                // 6. AUDIO MODAL
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
                      _resetOsdTimer();
                    },
                    onClose: () => setState(() => _showAudioDialog = false),
                  ),
              ],
            ),
          ),
        ),
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
        width: 380,
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
            ...options.map((opt) {
              final isSelected = opt == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TvFocusable(
                  onPressed: () => onSelected(opt),
                  backgroundColor: isSelected ? const Color(0xFF2E63FF) : TvColors.bgSurface1,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(opt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      if (isSelected) const Text('✔', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
  Widget _buildConnectingView() {
    return Container(
      color: TvColors.bgCanvas,
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
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: TvColors.accentPrimary, strokeWidth: 3),
              ),
              const SizedBox(height: 14),
              Text('Connecting to ${_currentChannel.channelName}...', style: TvTypography.cardPrimary),
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
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedAlertCircle,
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
                  color: TvColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusable(
                    autofocus: true,
                    onPressed: () => _startPlayback(),
                    backgroundColor: const Color(0xFF2E63FF),
                    focusedBackgroundColor: const Color(0xFF4A7DFF),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    borderRadius: BorderRadius.circular(8),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(icon: HugeIcons.strokeRoundedReload, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Retry Stream', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TvFocusable(
                    onPressed: widget.onBack,
                    backgroundColor: TvColors.bgSurface2,
                    focusedBackgroundColor: const Color(0xFF323B4E),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    borderRadius: BorderRadius.circular(8),
                    child: const Text('Back to Guide', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  TvFocusable(
                    onPressed: () => setState(() => _showDebugOverlay = !_showDebugOverlay),
                    backgroundColor: Colors.white10,
                    focusedBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    borderRadius: BorderRadius.circular(8),
                    child: Text(_showDebugOverlay ? 'Hide Debug' : 'Debug Info', style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                      const Text('TECHNICAL DEBUG LOGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.amber)),
                      const SizedBox(height: 6),
                      Text('Channel ID: ${_currentChannel.channelId}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      Text('Last Target URL: ${_lastAttemptedUrl ?? "None"}', style: const TextStyle(fontSize: 10, color: Colors.white60)),
                      const SizedBox(height: 4),
                      const Text('Jio Playback API Note: Direct streams require Akamai token (?hdnea=...). Direct access without auth returns 403 Forbidden.', style: TextStyle(fontSize: 10, color: Colors.white54)),
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
