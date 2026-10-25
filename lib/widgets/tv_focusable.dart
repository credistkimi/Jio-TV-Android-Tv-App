import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';

/// TV Focusable Wrapper Widget.
/// Implements Android TV 10-foot focus physics conforming to official guidelines:
/// - Smooth elevation & scale transform with cubic-bezier curve.
/// - 3dp high-contrast white/accent focus ring.
/// - Deep drop-glow shadow for depth perception.
/// - Handles TV remote D-Pad Center / Select / Enter / Space / Gamepad A activation.
/// - Automatic smooth scroll-into-view (Scrollable.ensureVisible) so focused elements
///   never get clipped or lost offscreen.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scale;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? focusedBackgroundColor;
  final Color? focusedBorderColor;
  final Color? focusedGlowColor;
  final bool showFocusRing;
  final bool enabled;
  final bool autoEnsureVisible;
  final double scrollAlignment;
  final FocusOnKeyEventCallback? onKeyEvent;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scale = TvDimensions.focusScaleStandard,
    this.borderRadius,
    this.padding,
    this.backgroundColor,
    this.focusedBackgroundColor,
    this.focusedBorderColor,
    this.focusedGlowColor,
    this.showFocusRing = true,
    this.enabled = true,
    this.autoEnsureVisible = true,
    this.scrollAlignment = 0.15,
    this.onKeyEvent,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode!;
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode(debugLabel: 'TvFocusableNode');
    }
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)?.removeListener(_handleFocusChange);
      if (widget.focusNode == null && _internalFocusNode == null) {
        _internalFocusNode = FocusNode(debugLabel: 'TvFocusableNode');
      } else if (widget.focusNode != null && _internalFocusNode != null) {
        _internalFocusNode!.dispose();
        _internalFocusNode = null;
      }
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    final hasFocus = _effectiveFocusNode.hasFocus;
    if (_isFocused != hasFocus) {
      setState(() {
        _isFocused = hasFocus;
      });
      widget.onFocusChange?.call(_isFocused);

      if (_isFocused && widget.autoEnsureVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _effectiveFocusNode.hasFocus) {
            Scrollable.ensureVisible(
              context,
              alignment: widget.scrollAlignment,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;

    if (widget.onKeyEvent != null) {
      final customResult = widget.onKeyEvent!(node, event);
      if (customResult != KeyEventResult.ignored) {
        return customResult;
      }
    }

    final isActionKey = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;

    if (isActionKey) {
      if (event is KeyDownEvent) {
        setState(() => _isPressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(TvDimensions.focusBorderRadius);
    final currentScale = _isFocused ? (widget.scale * (_isPressed ? 0.97 : 1.0)) : 1.0;
    final ringColor = widget.focusedBorderColor ?? TvColors.focusRing;
    final glowColor = widget.focusedGlowColor ?? TvColors.focusGlow;

    return Focus(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: currentScale,
          duration: TvDimensions.focusAnimationDuration,
          curve: TvDimensions.focusAnimationCurve,
          child: AnimatedContainer(
            duration: TvDimensions.focusAnimationDuration,
            curve: TvDimensions.focusAnimationCurve,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _isFocused
                  ? (widget.focusedBackgroundColor ?? widget.backgroundColor ?? Colors.transparent)
                  : (widget.backgroundColor ?? Colors.transparent),
              borderRadius: effectiveRadius,
              border: (widget.showFocusRing && _isFocused)
                  ? Border.all(
                      color: ringColor,
                      width: TvDimensions.focusBorderWidth,
                    )
                  : Border.all(
                      color: Colors.transparent,
                      width: TvDimensions.focusBorderWidth,
                    ),
              boxShadow: (_isFocused && widget.showFocusRing)
                  ? [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
