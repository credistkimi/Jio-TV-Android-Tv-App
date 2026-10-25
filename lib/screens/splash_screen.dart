import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme/tv_colors.dart';

/// Premium 10-Foot Splash Screen for Android TV & Web.
/// Features a cinematic left-to-right reveal animation of "JioTV+"
/// synchronized with an ambient stereo chime sound effect.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  final Duration duration;
  final bool playSound;

  const SplashScreen({
    super.key,
    required this.onFinish,
    this.duration = const Duration(milliseconds: 2400),
    this.playSound = true,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _revealAnimation;
  late final Animation<double> _shimmerAnimation;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _glowPulse;

  AudioPlayer? _audioPlayer;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Left-to-right reveal factor (0.0 -> 1.0)
    _revealAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.08, 0.65, curve: Curves.easeOutCubic),
    );

    // Light shimmer streak sweeping across the text
    _shimmerAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.35, 0.85, curve: Curves.easeInOutCubic),
    );

    // Subtitle fade and slide in
    _subtitleFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.60, 0.95, curve: Curves.easeOut),
    );

    // Subtle glow scale
    _glowPulse = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeInOut),
      ),
    );

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_hasFinished) {
        _hasFinished = true;
        widget.onFinish();
      }
    });

    _playSplashSound();
    _animController.forward();
  }

  Future<void> _playSplashSound() async {
    if (!widget.playSound || kIsWeb && !kDebugMode) {
      // Browsers often require initial user interaction before audio playback
    }
    try {
      _audioPlayer = AudioPlayer();
      // Configure audio player for non-looping splash chime
      await _audioPlayer?.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer?.setVolume(0.85);
      await _audioPlayer?.play(AssetSource('audio/splash_sound.wav'));
    } catch (e) {
      // Audio playback errors (e.g. headless tests or browser audio policy)
      // must never block the visual splash sequence.
      debugPrint('ℹ️ [SplashScreen] Audio playback notice: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    try {
      _audioPlayer?.stop();
      _audioPlayer?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: TvColors.bgCanvas,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient Atmospheric Glows
          AnimatedBuilder(
            animation: _glowPulse,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned(
                    top: size.height * 0.25,
                    left: size.width * 0.35,
                    child: Container(
                      width: 320 * _glowPulse.value,
                      height: 320 * _glowPulse.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            TvColors.accentPrimary.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: size.height * 0.20,
                    right: size.width * 0.30,
                    child: Container(
                      width: 280 * _glowPulse.value,
                      height: 280 * _glowPulse.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            TvColors.accentCyan.withValues(alpha: 0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Main Center Stage
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Left-to-Right "JioTV+" Reveal
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    return _buildLeftToRightJioTvLogo(
                      reveal: _revealAnimation.value,
                      shimmer: _shimmerAnimation.value,
                    );
                  },
                ),

                const SizedBox(height: 20),

                // Subtitle
                FadeTransition(
                  opacity: _subtitleFade,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(_subtitleFade),
                    child: Column(
                      children: [
                        Text(
                          'BIG SCREEN LIVE ENTERTAINMENT',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.5,
                            color: TvColors.accentCyan.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '1,000+ Live Channels • 7-Day Catch-up • Full HD',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            color: TvColors.textSecondary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
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

  /// Builds the JioTV+ logo with a left-to-right reveal clip and sweeping light shimmer.
  Widget _buildLeftToRightJioTvLogo({
    required double reveal,
    required double shimmer,
  }) {
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: reveal, // Reveals logo smoothly from Left to Right
        child: ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            // Light streak that sweeps from left to right as the chime rings
            final sweepPos = (shimmer * 2.0) - 0.5;
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                (sweepPos - 0.25).clamp(0.0, 1.0),
                sweepPos.clamp(0.0, 1.0),
                (sweepPos + 0.25).clamp(0.0, 1.0),
              ],
              colors: const [
                Colors.white,
                Color(0xFFE2F4FF),
                Colors.white,
              ],
            ).createShader(bounds);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // JioTV+ Primary Brand Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0078FF), // Jio Electric Blue
                      Color(0xFF004CB8), // Deep Royal Blue
                      Color(0xFFE50914), // Red edge
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: TvColors.accentPrimary.withValues(alpha: 0.5),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: TvColors.accentCyan.withValues(alpha: 0.25),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Jio',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'TV',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 2),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [TvColors.accentCyan, Colors.white],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              // LIVE Broadcast Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: TvColors.liveRed,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: TvColors.liveRed.withValues(alpha: 0.6),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.0,
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
