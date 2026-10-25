import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'tv_focusable.dart';

class TvCategoryPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final Widget? leading;
  final List<List<dynamic>>? icon;

  const TvCategoryPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.focusNode,
    this.leading,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: isSelected ? const Color(0xFFE50914) : const Color(0xFF161A24),
      focusedBackgroundColor: isSelected ? const Color(0xFFFF2233) : const Color(0xFF242A3B),
      focusedBorderColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              HugeIcon(
                icon: icon!,
                color: isSelected ? Colors.white : const Color(0xFFB0B7C6),
                size: 15,
              ),
              const SizedBox(width: 6),
            ] else if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
