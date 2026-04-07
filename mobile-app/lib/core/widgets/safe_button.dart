import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Large tap-target emergency button widget.
/// Designed for high-stress situations where precision tapping is difficult.
class SafeButton extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final String label;
  final IconData? icon;
  final double size;
  final Color? color;
  final Color? textColor;
  final bool isActive;
  final bool showPulse;
  final bool hapticFeedback;

  const SafeButton({
    super.key,
    required this.onPressed,
    this.onLongPress,
    required this.label,
    this.icon,
    this.size = AppTheme.emergencyButtonSize,
    this.color,
    this.textColor,
    this.isActive = false,
    this.showPulse = false,
    this.hapticFeedback = true,
  });

  /// Factory for the primary emergency trigger button.
  factory SafeButton.emergency({
    Key? key,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
    bool isActive = false,
  }) {
    return SafeButton(
      key: key,
      onPressed: onPressed,
      onLongPress: onLongPress,
      label: isActive ? 'ACTIVE' : 'SOS',
      icon: Icons.shield,
      size: AppTheme.emergencyButtonSize,
      color: AppTheme.emergencyRed,
      textColor: Colors.white,
      isActive: isActive,
      showPulse: isActive,
      hapticFeedback: true,
    );
  }

  /// Factory for a cancel button during countdown.
  factory SafeButton.cancel({
    Key? key,
    required VoidCallback onPressed,
  }) {
    return SafeButton(
      key: key,
      onPressed: onPressed,
      label: 'CANCEL',
      icon: Icons.close,
      size: 80,
      color: Colors.grey.shade700,
      textColor: Colors.white,
      hapticFeedback: true,
    );
  }

  @override
  State<SafeButton> createState() => _SafeButtonState();
}

class _SafeButtonState extends State<SafeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.showPulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SafeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.showPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handlePress() {
    if (widget.hapticFeedback) {
      HapticFeedback.heavyImpact();
    }
    widget.onPressed();
  }

  void _handleLongPress() {
    if (widget.onLongPress == null) return;
    if (widget.hapticFeedback) {
      HapticFeedback.vibrate();
    }
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.color ?? AppTheme.primaryColor;

    Widget button = GestureDetector(
      onTap: _handlePress,
      onLongPress: widget.onLongPress != null ? _handleLongPress : null,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: buttonColor,
          boxShadow: [
            BoxShadow(
              color: buttonColor.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null)
              Icon(
                widget.icon,
                color: widget.textColor ?? Colors.white,
                size: widget.size * 0.3,
              ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.textColor ?? Colors.white,
                fontSize: widget.size * 0.14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.showPulse) {
      button = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: child,
          );
        },
        child: button,
      );
    }

    // Ensure minimum accessible touch target.
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: button,
    );
  }
}
