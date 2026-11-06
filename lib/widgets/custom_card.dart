import 'package:flutter/material.dart';
import '../core/constants/constants.dart';

/// Premium SaaS Card container with soft shadow,
/// rounded corners, and smooth tap feedback.
class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool hasShadow;
  final BorderSide? borderSide;

  const CustomCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.md),
    this.margin,
    this.color = AppColors.surface,
    this.borderRadius,
    this.onTap,
    this.hasShadow = true,
    this.borderSide,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? AppSizes.radiusLg;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget cardBody = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color == AppColors.surface ? Theme.of(context).cardColor : color,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: borderSide != null ? Border.fromBorderSide(borderSide!) : null,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  color: isDark 
                      ? Colors.black.withValues(alpha: 0.1)
                      : AppColors.textDark.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.05)
                      : AppColors.textDark.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(effectiveRadius),
            child: cardBody,
          ),
        ),
      );
    }

    return margin != null
        ? Padding(padding: margin!, child: cardBody)
        : cardBody;
  }
}
