import 'package:flutter/material.dart';
import '../core/constants/constants.dart';

/// Shimmer loading skeleton placeholder.
///
/// Use in place of content while data is loading. Provides a
/// smooth, premium loading experience instead of spinners.
///
/// ```dart
/// ShimmerBox(width: 200, height: 16) // text placeholder
/// ShimmerBox(width: double.infinity, height: 120) // card placeholder
/// ```
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    Key? key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8.0,
  }) : super(key: key);

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: const [
                AppColors.surfaceVariant,
                AppColors.background,
                AppColors.surfaceVariant,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton card — full card-sized shimmer placeholder.
class ShimmerCard extends StatelessWidget {
  final double height;

  const ShimmerCard({Key? key, this.height = 120}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 120, height: 14, borderRadius: 4),
          SizedBox(height: AppSizes.md),
          ShimmerBox(height: 20, borderRadius: 4),
          SizedBox(height: AppSizes.sm),
          ShimmerBox(width: 200, height: 14, borderRadius: 4),
        ],
      ),
    );
  }
}
