import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// Authentic 10-Foot Splash Screen for JioTV+ TV.
/// Matches the official TV splash screen design:
/// - Radiant dark curved-red background
/// - Centered JioTV+ brand logo (Red Jio circle + bold white TV+)
/// - Red circular loading spinner
/// - Synchronized ambient chime audio playback
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
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  AudioPlayer? _audioPlayer;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
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
    if (!widget.playSound || (kIsWeb && !kDebugMode)) {
      return;
    }
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer?.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer?.setVolume(0.85);
      await _audioPlayer?.play(AssetSource('audio/splash_sound.wav'));
    } catch (e) {
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background with Curved Red Glowing Waves
          Image.asset(
            'assets/images/auth_splash_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),

          // Centered Brand Logo & Circular Spinner
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand Logo
                    _buildBrandLogo(),

                    const SizedBox(height: 38),

                    // Red Circular Loading Spinner
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandLogo() {
    return Image.asset(
      'assets/images/jiotv_plus_logo.png',
      height: 84,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _buildFallbackLogo(),
    );
  }

  Widget _buildFallbackLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFE50914),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            'Jio',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.white,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Text(
          'TV+',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
