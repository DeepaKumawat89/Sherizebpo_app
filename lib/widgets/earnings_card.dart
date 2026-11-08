import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/constants/constants.dart';
import '../core/theme/app_decorations.dart';

/// Dashboard earnings summary card.
class EarningsCard extends StatelessWidget {
  final double totalEarned;
  final double pendingAmount;
  final VoidCallback? onWithdraw;

  const EarningsCard({
    Key? key,
    required this.totalEarned,
    this.pendingAmount = 0.0,
    this.onWithdraw,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: AppDecorations.primaryGradientCard,
      child: Stack(
        children: [
          Positioned(
            right: -38,
            bottom: -62,
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryLight.withValues(alpha: 0.20),
              ),
            ),
          ),
          Positioned(
            right: 34,
            top: -52,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.violet.withValues(alpha: 0.16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius:
                            BorderRadius.circular(AppSizes.radiusMd),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.wallet,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    const Expanded(
                      child: Text(
                        'Total Earnings',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onWithdraw != null)
                      GestureDetector(
                        onTap: onWithdraw,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md,
                            vertical: AppSizes.sm,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusRound),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: AppSizes.xs),
                              Icon(
                                LucideIcons.arrowUpRight,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.xl),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: totalEarned),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '\u20B9${value.toStringAsFixed(0)}',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1.1,
                        ),
                      ),
                    );
                  },
                ),
                if (pendingAmount > 0) ...[
                  const SizedBox(height: AppSizes.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md,
                      vertical: AppSizes.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.clock,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Flexible(
                          child: Text(
                            '\u20B9${pendingAmount.toStringAsFixed(0)} pending',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
