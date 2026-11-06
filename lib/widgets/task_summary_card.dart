import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/constants/constants.dart';
import '../core/theme/app_decorations.dart';

/// Modern task summary card with animated progress bar
/// and color-coded stat chips.
class TaskSummaryCard extends StatelessWidget {
  final int activeTasks;
  final int pendingTasks;
  final int completedTasks;
  final VoidCallback? onViewAll;

  const TaskSummaryCard({
    Key? key,
    required this.activeTasks,
    required this.pendingTasks,
    required this.completedTasks,
    this.onViewAll,
  }) : super(key: key);

  int get _total => activeTasks + pendingTasks + completedTasks;

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? completedTasks / _total : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: AppDecorations.iconBox(color: AppColors.primary),
                child: const Icon(LucideIcons.clipboardList,
                    size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  'Tasks Overview',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(LucideIcons.arrowRight,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),

          // Progress Bar
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: isDark 
                      ? Colors.white.withValues(alpha: 0.05)
                      : AppColors.surfaceVariant,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.success),
                ),
              );
            },
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completedTasks/$_total completed',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                    ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.successLight : AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),

          // Stat Chips
          Row(
            children: [
              _StatChip(
                label: 'Active',
                value: activeTasks.toString(),
                color: isDark ? AppColors.infoLight : AppColors.info,
                bgColor: isDark ? AppColors.infoLight.withValues(alpha: 0.1) : AppColors.info.withValues(alpha: 0.08),
                icon: LucideIcons.play,
              ),
              const SizedBox(width: AppSizes.sm),
              _StatChip(
                label: 'Pending',
                value: pendingTasks.toString(),
                color: isDark ? AppColors.warningLight : AppColors.warning,
                bgColor: isDark ? AppColors.warningLight.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.08),
                icon: LucideIcons.clock,
              ),
              const SizedBox(width: AppSizes.sm),
              _StatChip(
                label: 'Done',
                value: completedTasks.toString(),
                color: isDark ? AppColors.successLight : AppColors.success,
                bgColor: isDark ? AppColors.successLight.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.08),
                icon: LucideIcons.checkCircle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.sm, vertical: AppSizes.sm),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
