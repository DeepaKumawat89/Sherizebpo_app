import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import '../core/theme/app_decorations.dart';

/// Production-grade button with loading state, icon support,
/// gradient primary variant, and premium press animation.
enum CustomButtonVariant { primary, outlined, text, success, danger }

class CustomButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final CustomButtonVariant variant;
  final IconData? icon;
  final double? width;
  final double height;
  final double? fontSize;

  const CustomButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.variant = CustomButtonVariant.primary,
    this.icon,
    this.width,
    this.height = AppSizes.buttonHeight,
    this.fontSize,
  }) : super(key: key);

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.03,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  bool get _effectiveDisabled =>
      widget.isDisabled || widget.isLoading || widget.onPressed == null;

  LinearGradient get _gradient {
    switch (widget.variant) {
      case CustomButtonVariant.success:
        return AppDecorations.accentGradient;
      case CustomButtonVariant.danger:
        return AppDecorations.roseGradient;
      default:
        return AppDecorations.primaryGradient;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.variant) {
      case CustomButtonVariant.outlined:
        return _buildOutlined();
      case CustomButtonVariant.text:
        return _buildText();
      case CustomButtonVariant.primary:
      case CustomButtonVariant.success:
      case CustomButtonVariant.danger:
        return _buildGradient();
    }
  }

  Widget _buildGradient() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AnimatedBuilder(
      animation: _scaleCtrl,
      builder: (context, child) {
        final scale = 1.0 - _scaleCtrl.value;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: _effectiveDisabled ? null : (_) => _scaleCtrl.forward(),
        onTapUp: _effectiveDisabled ? null : (_) => _scaleCtrl.reverse(),
        onTapCancel: _effectiveDisabled ? null : () => _scaleCtrl.reverse(),
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: _effectiveDisabled
                ? LinearGradient(
                    colors: isDark 
                        ? [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.1)]
                        : [AppColors.surfaceVariant, AppColors.border],
                  )
                : _gradient,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            boxShadow: _effectiveDisabled || isDark
                ? null
                : AppDecorations.primaryShadow(alpha: 0.2),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              onTap: _effectiveDisabled ? null : widget.onPressed,
              child: Center(
                child: _buildChild(
                  _effectiveDisabled 
                      ? (isDark ? Colors.white24 : AppColors.textPlaceholder) 
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlined() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryLight : AppColors.primary;

    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height,
      child: OutlinedButton(
        onPressed: _effectiveDisabled ? null : widget.onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: _effectiveDisabled
                ? (isDark ? Colors.white12 : AppColors.border)
                : primaryColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          foregroundColor: primaryColor,
          backgroundColor: isDark 
              ? Colors.white.withValues(alpha: 0.02)
              : AppColors.primarySoft.withValues(alpha: 0.3),
        ),
        child: _buildChild(
          _effectiveDisabled 
              ? (isDark ? Colors.white12 : AppColors.textPlaceholder) 
              : primaryColor,
        ),
      ),
    );
  }

  Widget _buildText() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryLight : AppColors.primary;

    return TextButton(
      onPressed: _effectiveDisabled ? null : widget.onPressed,
      child: _buildChild(
        _effectiveDisabled 
            ? (isDark ? Colors.white12 : AppColors.textPlaceholder) 
            : primaryColor,
      ),
    );
  }

  Widget _buildChild(Color color) {
    if (widget.isLoading) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          color: color,
          strokeWidth: 2.5,
        ),
      );
    }

    final textStyle = TextStyle(
      color: color,
      fontSize: widget.fontSize ?? 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );

    if (widget.icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: AppSizes.iconMd, color: color),
          const SizedBox(width: AppSizes.sm),
          Text(widget.label, style: textStyle),
        ],
      );
    }

    return Text(widget.label, style: textStyle);
  }
}
