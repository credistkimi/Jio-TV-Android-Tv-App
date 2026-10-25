import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../widgets/tv_focusable.dart';

/// Modern Centered 1-Column TV Login Screen inspired by leading streaming platforms.
/// Features a sleek frosted glass container, dynamic compact D-pad keypad,
/// and full physical remote control support.
class AuthScreen extends StatefulWidget {
  final ApiService apiService;
  final StorageService storageService;
  final VoidCallback onLoginSuccess;

  const AuthScreen({
    super.key,
    required this.apiService,
    required this.storageService,
    required this.onLoginSuccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String _mobileNumber = '';
  String _enteredOtp = '';
  bool _isOtpStage = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Resend OTP countdown
  int _resendCountdown = 30;
  Timer? _resendTimer;

  // TV D-Pad Focus Nodes
  final FocusNode _firstKeyFocusNode = FocusNode(debugLabel: 'FirstNumpadKey');
  final FocusNode _getOtpFocusNode = FocusNode(debugLabel: 'GetOtpButton');
  final FocusNode _firstOtpKeyFocusNode = FocusNode(debugLabel: 'FirstOtpKey');
  final FocusNode _verifyOtpFocusNode = FocusNode(debugLabel: 'VerifyOtpButton');
  final FocusNode _guestButtonFocusNode = FocusNode(debugLabel: 'GuestButton');

  @override
  void initState() {
    super.initState();
    // Register global hardware keyboard / physical remote listener
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    // Initial focus on the first numpad key so D-pad remote works immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstKeyFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _resendTimer?.cancel();
    _firstKeyFocusNode.dispose();
    _getOtpFocusNode.dispose();
    _firstOtpKeyFocusNode.dispose();
    _verifyOtpFocusNode.dispose();
    _guestButtonFocusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_resendCountdown > 0) {
          setState(() => _resendCountdown--);
        } else {
          timer.cancel();
        }
      }
    });
  }

  void _handleDigitInput(String digit) {
    setState(() {
      _errorMessage = null;
      if (!_isOtpStage) {
        if (_mobileNumber.length < 10) {
          _mobileNumber += digit;
          // Auto-focus Get OTP button once 10 digits are filled
          if (_mobileNumber.length == 10) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _getOtpFocusNode.requestFocus();
              }
            });
          }
        }
      } else {
        if (_enteredOtp.length < 6) {
          _enteredOtp += digit;
          if (_enteredOtp.length == 6) {
            _submitOtp();
          }
        }
      }
    });
  }

  void _handleBackspace() {
    setState(() {
      _errorMessage = null;
      if (!_isOtpStage) {
        if (_mobileNumber.isNotEmpty) {
          _mobileNumber = _mobileNumber.substring(0, _mobileNumber.length - 1);
        }
      } else {
        if (_enteredOtp.isNotEmpty) {
          _enteredOtp = _enteredOtp.substring(0, _enteredOtp.length - 1);
        }
      }
    });
  }

  void _handleClear() {
    setState(() {
      _errorMessage = null;
      if (!_isOtpStage) {
        _mobileNumber = '';
      } else {
        _enteredOtp = '';
      }
    });
  }

  /// Global key event handler for physical TV remote number buttons (0-9) and Backspace
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final digit = _getDigitFromKey(key);
    if (digit != null) {
      _handleDigitInput(digit);
      return true; // Consumed
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _handleBackspace();
      return true; // Consumed
    }
    return false;
  }

  String? _getDigitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) return '0';
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) return '1';
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) return '2';
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) return '3';
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) return '4';
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) return '5';
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) return '6';
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) return '7';
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) return '8';
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) return '9';
    return null;
  }

  Future<void> _requestOtp() async {
    if (_mobileNumber.length != 10) {
      setState(() => _errorMessage = 'Please enter a complete 10-digit mobile number');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await widget.apiService.sendMobileOtp(_mobileNumber);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res['success'] == true) {
          _isOtpStage = true;
          _enteredOtp = '';
          _startResendTimer();
        } else {
          _errorMessage = res['message'] ?? 'Failed to send OTP. Please check your connection.';
        }
      });
      if (res['success'] == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _firstOtpKeyFocusNode.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _submitOtp() async {
    if (_enteredOtp.length != 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit OTP code');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await widget.apiService.verifyMobileOtp(_mobileNumber, _enteredOtp);
    if (mounted) {
      setState(() => _isLoading = false);
      final token = res['token'] as String?;
      if (token != null && token.isNotEmpty) {
        await widget.storageService.saveAuthSession(
          ssoToken: token,
          accessToken: res['accessToken'] as String?,
          refreshToken: res['refreshToken'] as String?,
          crmId: res['crmId'] as String?,
          uniqueId: res['uniqueId'] as String?,
          mobileNumber: _mobileNumber,
        );
        widget.onLoginSuccess();
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Invalid OTP code. Please retry.';
        });
      }
    }
  }

  void _handleChangeNumber() {
    setState(() {
      _isOtpStage = false;
      _enteredOtp = '';
      _errorMessage = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstKeyFocusNode.requestFocus();
      }
    });
  }

  String _formatPhoneNumber(String num) {
    if (num.length <= 5) return num;
    return '${num.substring(0, 5)} ${num.substring(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final isCompact = screenHeight < 680;

    return Scaffold(
      backgroundColor: TvColors.bgCanvas,
      body: Stack(
        children: [
          // Ambient Atmospheric Background Glows
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    TvColors.accentPrimary.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    TvColors.accentCyan.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Minimal Top Bar with Guest Mode Action
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TvDimensions.overscanMargin,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Mini Brand Indicator
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [TvColors.accentPrimary, Color(0xFF004CB8)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'JioTV+',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: TvColors.liveRed,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Explore as Guest Button
                      TvFocusable(
                        focusNode: _guestButtonFocusNode,
                        onPressed: widget.onLoginSuccess,
                        borderRadius: BorderRadius.circular(20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        backgroundColor: TvColors.bgSurface2.withValues(alpha: 0.8),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Explore as Guest',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 6),
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowRight01,
                              color: Colors.white,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Centered 1-Column Modern Login Card
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact ? 420 : 440,
                          ),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: isCompact ? 16 : 22,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xE6111520), // Frosted dark surface
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  blurRadius: 32,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: TvColors.accentPrimary.withValues(alpha: 0.08),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                            child: _isOtpStage
                                ? _buildOtpStage(isCompact)
                                : _buildMobileNumberStage(isCompact),
                          ),
                        ),
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

  /// Step 1: Mobile Number Input & Dynamic Compact D-Pad Keypad
  Widget _buildMobileNumberStage(bool isCompact) {
    final isComplete = _mobileNumber.length == 10;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card Header
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: TvColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: TvColors.accentPrimary.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedSmartPhone01,
                      color: TvColors.accentCyan,
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'MOBILE SIGN IN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: TvColors.accentCyan,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 6 : 8),
              Text(
                'Enter your Mobile Number',
                style: TextStyle(
                  fontSize: isCompact ? 18 : 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Access 1,000+ live HD channels & catchup',
                style: TextStyle(
                  fontSize: 12,
                  color: TvColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: isCompact ? 10 : 14),

        // Modern Compact Phone Input Display
        Container(
          height: isCompact ? 44 : 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: TvColors.bgSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isComplete
                  ? TvColors.accentCyan
                  : TvColors.accentPrimary.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Country Code
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '🇮🇳 +91',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Mobile Digits
              Expanded(
                child: Text(
                  _mobileNumber.isEmpty ? '10-digit number' : _formatPhoneNumber(_mobileNumber),
                  style: TextStyle(
                    fontSize: isCompact ? 17 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _mobileNumber.isEmpty ? TvColors.textDisabled : Colors.white,
                  ),
                ),
              ),

              // Clear Button
              if (_mobileNumber.isNotEmpty)
                GestureDetector(
                  onTap: _handleClear,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: TvColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Error message banner
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: TvColors.liveRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TvColors.liveRed.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedAlertCircle,
                  color: TvColors.liveRed,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TvColors.liveRed,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: isCompact ? 8 : 12),

        // Dynamic Compact Numpad (height constrained for 10-foot TV)
        _buildDynamicNumpad(isCompact),

        SizedBox(height: isCompact ? 10 : 14),

        // Primary Action: "Get OTP"
        TvFocusable(
          focusNode: _getOtpFocusNode,
          onPressed: _isLoading ? null : _requestOtp,
          borderRadius: BorderRadius.circular(10),
          padding: EdgeInsets.symmetric(vertical: isCompact ? 11 : 13),
          backgroundColor: isComplete ? TvColors.accentPrimary : TvColors.bgSurface2,
          focusedBackgroundColor: isComplete ? TvColors.accentPrimary : TvColors.bgSurface3,
          focusedBorderColor: TvColors.focusRing,
          focusedGlowColor: isComplete
              ? TvColors.accentPrimary.withValues(alpha: 0.5)
              : TvColors.focusGlow,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Get OTP',
                        style: TextStyle(
                          fontSize: isCompact ? 14 : 15,
                          fontWeight: FontWeight.w900,
                          color: isComplete ? Colors.white : TvColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedArrowRight01,
                        color: isComplete ? Colors.white : TvColors.textSecondary,
                        size: 16,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Step 2: 6-Digit OTP Verification Stage
  Widget _buildOtpStage(bool isCompact) {
    final isComplete = _enteredOtp.length == 6;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: TvColors.accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: TvColors.accentCyan.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedLockPassword,
                      color: TvColors.accentCyan,
                      size: 13,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'STEP 2 OF 2',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: TvColors.accentCyan,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 6 : 8),
              Text(
                'Enter 6-Digit OTP',
                style: TextStyle(
                  fontSize: isCompact ? 18 : 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sent to +91 ${_formatPhoneNumber(_mobileNumber)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TvColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _handleChangeNumber,
                    child: const Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: TvColors.accentCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: isCompact ? 10 : 14),

        // 6 Separated OTP Digit Boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            final isFilled = index < _enteredOtp.length;
            final isCurrent = index == _enteredOtp.length;
            final digit = isFilled ? _enteredOtp[index] : '';

            return Container(
              width: isCompact ? 38 : 42,
              height: isCompact ? 42 : 46,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isFilled ? TvColors.bgSurface2 : TvColors.bgCanvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrent
                      ? TvColors.accentCyan
                      : (isFilled ? TvColors.accentPrimary : TvColors.borderSubtle),
                  width: isCurrent ? 2 : 1.2,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: TvColors.accentCyan.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  digit,
                  style: TextStyle(
                    fontSize: isCompact ? 18 : 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          }),
        ),

        // Error message if any
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: TvColors.liveRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TvColors.liveRed.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const HugeIcon(
                  icon: HugeIcons.strokeRoundedAlertCircle,
                  color: TvColors.liveRed,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TvColors.liveRed,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: isCompact ? 8 : 12),

        // Dynamic Compact Numpad
        _buildDynamicNumpad(isCompact),

        SizedBox(height: isCompact ? 10 : 14),

        // Action Row: Resend & Submit
        Row(
          children: [
            // Resend
            Expanded(
              flex: 4,
              child: TvFocusable(
                onPressed: _resendCountdown == 0 && !_isLoading ? _requestOtp : null,
                borderRadius: BorderRadius.circular(10),
                padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 12),
                backgroundColor: TvColors.bgSurface2,
                child: Center(
                  child: Text(
                    _resendCountdown > 0 ? '${_resendCountdown}s' : 'Resend OTP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _resendCountdown == 0 ? TvColors.accentCyan : TvColors.textDisabled,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Submit
            Expanded(
              flex: 6,
              child: TvFocusable(
                focusNode: _verifyOtpFocusNode,
                onPressed: _isLoading ? null : _submitOtp,
                borderRadius: BorderRadius.circular(10),
                padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 12),
                backgroundColor: isComplete ? TvColors.accentPrimary : TvColors.bgSurface2,
                focusedBackgroundColor: isComplete ? TvColors.accentPrimary : TvColors.bgSurface3,
                focusedBorderColor: TvColors.focusRing,
                focusedGlowColor: isComplete
                    ? TvColors.accentPrimary.withValues(alpha: 0.5)
                    : TvColors.focusGlow,
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : Text(
                          'Verify & Sign In',
                          style: TextStyle(
                            fontSize: isCompact ? 13 : 14,
                            fontWeight: FontWeight.w900,
                            color: isComplete ? Colors.white : TvColors.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Dynamic Compact D-Pad Keypad: adapts button height and padding
  /// so it stays well under the screen viewport height on all TVs.
  Widget _buildDynamicNumpad(bool isCompact) {
    final keyHeight = isCompact ? 34.0 : 38.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNumpadRow(['1', '2', '3'], keyHeight),
        const SizedBox(height: 5),
        _buildNumpadRow(['4', '5', '6'], keyHeight),
        const SizedBox(height: 5),
        _buildNumpadRow(['7', '8', '9'], keyHeight),
        const SizedBox(height: 5),
        Row(
          children: [
            // Clear Key
            Expanded(
              child: _buildKey(
                height: keyHeight,
                child: const Text(
                  'CLEAR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: TvColors.textSecondary,
                  ),
                ),
                onPressed: _handleClear,
              ),
            ),
            const SizedBox(width: 6),

            // 0 Key
            Expanded(
              child: _buildKey(
                height: keyHeight,
                child: const Text(
                  '0',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                onPressed: () => _handleDigitInput('0'),
              ),
            ),
            const SizedBox(width: 6),

            // Backspace Key
            Expanded(
              child: _buildKey(
                height: keyHeight,
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.white,
                  size: 16,
                ),
                onPressed: _handleBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumpadRow(List<String> digits, double height) {
    return Row(
      children: digits.map((d) {
        final isFirst = d == '1';
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _buildKey(
              height: height,
              focusNode: isFirst
                  ? (_isOtpStage ? _firstOtpKeyFocusNode : _firstKeyFocusNode)
                  : null,
              autofocus: isFirst,
              child: Text(
                d,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              onPressed: () => _handleDigitInput(d),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey({
    required Widget child,
    required VoidCallback onPressed,
    required double height,
    FocusNode? focusNode,
    bool autofocus = false,
  }) {
    return SizedBox(
      height: height,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(8),
        padding: EdgeInsets.zero,
        backgroundColor: TvColors.bgSurface2,
        focusedBackgroundColor: TvColors.bgSurface3,
        focusedBorderColor: TvColors.focusRing,
        focusedGlowColor: TvColors.focusGlow,
        child: Center(child: child),
      ),
    );
  }
}
