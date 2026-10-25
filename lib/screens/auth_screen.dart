import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/tv_focusable.dart';

/// Authentic JioTV+ TV Authentication Screen matching official design:
/// - Radiant dark curved-red background
/// - Top-left JioTV+ logo (Red Jio circle + bold white TV+)
/// - Top-right "Explore as Guest" option
/// - "Login to JioTV+" title and "Enter your mobile number to continue" subtitle
/// - Red-bordered input field with "+91" prefix and divider
/// - Centered 3x4 circular keypad with 1-9, Backspace, 0, Red Arrow Submit
/// - Full D-pad TV remote navigation and physical remote 0-9 key support
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
  final FocusNode _key1FocusNode = FocusNode(debugLabel: 'FirstNumpadKey');
  final FocusNode _submitFocusNode = FocusNode(debugLabel: 'SubmitButton');
  final FocusNode _guestButtonFocusNode = FocusNode(debugLabel: 'GuestButton');
  final FocusNode _firstOtpKeyFocusNode = FocusNode(debugLabel: 'FirstOtpKey');

  @override
  void initState() {
    super.initState();
    // Register physical TV remote key listener
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);

    // Initial focus on Key '1' as shown in the official reference design
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _key1FocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _resendTimer?.cancel();
    _key1FocusNode.dispose();
    _submitFocusNode.dispose();
    _guestButtonFocusNode.dispose();
    _firstOtpKeyFocusNode.dispose();
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

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final digit = _getDigitFromKey(key);
    if (digit != null) {
      _handleDigitInput(digit);
      return true;
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _handleBackspace();
      return true;
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
        _key1FocusNode.requestFocus();
      }
    });
  }

  String _formatPhoneNumber(String num) {
    if (num.length <= 5) return num;
    return '${num.substring(0, 5)} ${num.substring(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image with Curved Red Waves
          Image.asset(
            'assets/images/auth_splash_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
          ),

          // Top Bar: Logo & Guest Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // JioTV+ Brand Logo
                  Image.asset(
                    'assets/images/jiotv_plus_logo.png',
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _buildFallbackHeaderLogo(),
                  ),

                  // Explore as Guest Button
                  TvFocusable(
                    focusNode: _guestButtonFocusNode,
                    onPressed: widget.onLoginSuccess,
                    borderRadius: BorderRadius.circular(20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    focusedBackgroundColor: Colors.white.withValues(alpha: 0.22),
                    focusedBorderColor: const Color(0xFFFF1E42),
                    focusedGlowColor: const Color(0x66FF1E42),
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
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Centered Content: Form & Keypad
          Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: _isOtpStage ? _buildOtpStage() : _buildMobileStage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHeaderLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFFE50914),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            'Jio',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'TV+',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Step 1: Mobile Number Input & 3x4 Circular Keypad
  Widget _buildMobileStage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title
        const Text(
          'Login to JioTV+',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),

        const SizedBox(height: 8),

        // Subtitle
        const Text(
          'Enter your mobile number to continue',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),

        const SizedBox(height: 24),

        // Mobile Input Field Container (Red border matching Image 1)
        Container(
          width: 390,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xCC080A10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFF1E42),
              width: 1.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33FF1E42),
                blurRadius: 12,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Row(
            children: [
              // Country Code
              const Text(
                '+91',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),

              const SizedBox(width: 14),

              // Vertical Divider
              Container(
                width: 1,
                height: 24,
                color: Colors.white.withValues(alpha: 0.25),
              ),

              const SizedBox(width: 14),

              // Phone Number Display or Placeholder
              Expanded(
                child: Text(
                  _mobileNumber.isEmpty ? '98765 43210' : _formatPhoneNumber(_mobileNumber),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _mobileNumber.isEmpty
                        ? const Color(0xFF6E6E78)
                        : Colors.white,
                  ),
                ),
              ),

              if (_mobileNumber.isNotEmpty)
                GestureDetector(
                  onTap: _handleClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.cancel,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Error message if any
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF334B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Centered 3x4 Circular Keypad
        _buildCircularKeypad(isOtp: false),
      ],
    );
  }

  /// Step 2: 6-Digit OTP Verification Stage
  Widget _buildOtpStage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title
        const Text(
          'Login to JioTV+',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),

        const SizedBox(height: 8),

        // Subtitle with Edit option
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter OTP sent to +91 ${_formatPhoneNumber(_mobileNumber)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _handleChangeNumber,
              child: const Text(
                'Edit',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF1E42),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 6 Separated OTP Digit Boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            final isFilled = index < _enteredOtp.length;
            final isCurrent = index == _enteredOtp.length;
            final digit = isFilled ? _enteredOtp[index] : '';

            return Container(
              width: 44,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xCC080A10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent
                      ? const Color(0xFFFF1E42)
                      : (isFilled ? Colors.white70 : const Color(0xFF2C2D35)),
                  width: isCurrent ? 2.0 : 1.2,
                ),
                boxShadow: isCurrent
                    ? const [
                        BoxShadow(
                          color: Color(0x4DFF1E42),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 10),

        // Resend Timer / Action
        GestureDetector(
          onTap: _resendCountdown == 0 && !_isLoading ? _requestOtp : null,
          child: Text(
            _resendCountdown > 0
                ? 'Resend OTP in ${_resendCountdown}s'
                : 'Resend OTP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _resendCountdown == 0
                  ? const Color(0xFFFF1E42)
                  : Colors.white38,
            ),
          ),
        ),

        // Error message if any
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF334B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Keypad for OTP entry
        _buildCircularKeypad(isOtp: true),
      ],
    );
  }

  /// 3x4 Circular Keypad (matching the layout in Image 1):
  /// Row 1: 1, 2, 3
  /// Row 2: 4, 5, 6
  /// Row 3: 7, 8, 9
  /// Row 4: Backspace, 0, Red Arrow Submit
  Widget _buildCircularKeypad({required bool isOtp}) {
    const buttonSize = 58.0;
    const hSpacing = 18.0;
    const vSpacing = 14.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: 1, 2, 3
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleKey(
              digit: '1',
              size: buttonSize,
              focusNode: isOtp ? _firstOtpKeyFocusNode : _key1FocusNode,
              autofocus: true,
              onPressed: () => _handleDigitInput('1'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '2',
              size: buttonSize,
              onPressed: () => _handleDigitInput('2'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '3',
              size: buttonSize,
              onPressed: () => _handleDigitInput('3'),
            ),
          ],
        ),
        const SizedBox(height: vSpacing),

        // Row 2: 4, 5, 6
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleKey(
              digit: '4',
              size: buttonSize,
              onPressed: () => _handleDigitInput('4'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '5',
              size: buttonSize,
              onPressed: () => _handleDigitInput('5'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '6',
              size: buttonSize,
              onPressed: () => _handleDigitInput('6'),
            ),
          ],
        ),
        const SizedBox(height: vSpacing),

        // Row 3: 7, 8, 9
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleKey(
              digit: '7',
              size: buttonSize,
              onPressed: () => _handleDigitInput('7'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '8',
              size: buttonSize,
              onPressed: () => _handleDigitInput('8'),
            ),
            const SizedBox(width: hSpacing),
            _CircleKey(
              digit: '9',
              size: buttonSize,
              onPressed: () => _handleDigitInput('9'),
            ),
          ],
        ),
        const SizedBox(height: vSpacing),

        // Row 4: Backspace, 0, Submit Arrow
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Backspace Key
            _CircleKey(
              icon: Icons.backspace_outlined,
              size: buttonSize,
              onPressed: _handleBackspace,
            ),
            const SizedBox(width: hSpacing),

            // 0 Key
            _CircleKey(
              digit: '0',
              size: buttonSize,
              onPressed: () => _handleDigitInput('0'),
            ),
            const SizedBox(width: hSpacing),

            // Submit Arrow Key (Solid Red Circle)
            _CircleKey(
              key: const ValueKey('auth_submit_button'),
              icon: Icons.arrow_forward_rounded,
              isSubmit: true,
              isLoading: _isLoading,
              size: buttonSize,
              focusNode: _submitFocusNode,
              onPressed: _isLoading
                  ? () {}
                  : (isOtp ? _submitOtp : _requestOtp),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular Key widget conforming to Android TV 10-foot D-pad guidelines
/// and matching Image 1 (focused red glowing ring, dark circular surface, solid red submit).
class _CircleKey extends StatefulWidget {
  final String? digit;
  final IconData? icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final double size;
  final bool isSubmit;
  final bool isLoading;

  const _CircleKey({
    super.key,
    this.digit,
    this.icon,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.size = 58,
    this.isSubmit = false,
    this.isLoading = false,
  });

  @override
  State<_CircleKey> createState() => _CircleKeyState();
}

class _CircleKeyState extends State<_CircleKey> {
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveNode => widget.focusNode ?? _internalFocusNode!;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }
    _effectiveNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _effectiveNode.removeListener(_onFocusChange);
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted && _isFocused != _effectiveNode.hasFocus) {
      setState(() => _isFocused = _effectiveNode.hasFocus);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isAction = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
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
    final scale = _isFocused ? (_isPressed ? 1.02 : 1.08) : 1.0;

    return Focus(
      focusNode: _effectiveNode,
      autofocus: widget.autofocus,
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
              color: widget.isSubmit
                  ? const Color(0xFFE50914)
                  : (_isFocused ? const Color(0xFF221216) : const Color(0xFF1E1E22)),
              border: Border.all(
                color: _isFocused
                    ? (widget.isSubmit ? Colors.white : const Color(0xFFFF1E42))
                    : Colors.transparent,
                width: 2.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.isSubmit
                            ? const Color(0x99FF1E42)
                            : const Color(0x66FF1E42),
                        blurRadius: 14,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : (widget.digit != null
                      ? Text(
                          widget.digit!,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          color: Colors.white,
                          size: widget.isSubmit ? 24 : 20,
                        )),
            ),
          ),
        ),
      ),
    );
  }
}
