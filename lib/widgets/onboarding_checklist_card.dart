import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/constants/constants.dart';
import '../core/theme/app_decorations.dart';

/// Premium onboarding checklist card that guides new users
/// through profile setup, KYC, and first task.
class OnboardingChecklistCard extends StatelessWidget {
  final bool isProfileComplete;
  final bool isKycDone;
  final bool isFirstTaskDone;
  final VoidCallback? onCompleteProfile;
  final VoidCallback? onCompleteKyc;
  final VoidCallback? onStartTask;

  const OnboardingChecklistCard({
    Key? key,
    required this.isProfileComplete,
    required this.isKycDone,
    required this.isFirstTaskDone,
    this.onCompleteProfile,
    this.onCompleteKyc,
    this.onStartTask,
  }) : super(key: key);

  int get _completedCount =>
      (isProfileComplete ? 1 : 0) +
      (isKycDone ? 1 : 0) +
      (isFirstTaskDone ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final progress = _completedCount / 3;
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
                decoration: AppDecorations.iconBox(color: AppColors.accent),
                child: const Icon(LucideIcons.rocket,
                    size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get Started',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '$_completedCount of 3 steps done',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isDark ? Colors.white54 : AppColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
              // Circular Progress
              SizedBox(
                width: 40,
                height: 40,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 3.5,
                          backgroundColor: isDark 
                              ? Colors.white.withValues(alpha: 0.05)
                              : AppColors.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? AppColors.successLight : AppColors.success,
                          ),
                        ),
                        Text(
                          '${(value * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),

          // Steps
          _ChecklistItem(
            title: 'Complete your profile',
            subtitle: 'Add your name and details',
            icon: LucideIcons.user,
            isDone: isProfileComplete,
            onTap: isProfileComplete ? null : onCompleteProfile,
          ),
          const SizedBox(height: AppSizes.sm),
          _ChecklistItem(
            title: 'Verify your identity',
            subtitle: 'Upload KYC documents',
            icon: LucideIcons.shieldCheck,
            isDone: isKycDone,
            onTap: isKycDone ? null : onCompleteKyc,
          ),
          const SizedBox(height: AppSizes.sm),
          _ChecklistItem(
            title: 'Complete first task',
            subtitle: 'Start earning today',
            icon: LucideIcons.phoneCall,
            isDone: isFirstTaskDone,
            onTap: isFirstTaskDone ? null : onStartTask,
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDone;
  final VoidCallback? onTap;

  const _ChecklistItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: isDone
              ? (isDark ? AppColors.successLight.withValues(alpha: 0.1) : AppColors.successBg.withValues(alpha: 0.5))
              : (isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.surfaceVariant.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isDone
                ? (isDark ? AppColors.successLight.withValues(alpha: 0.2) : AppColors.success.withValues(alpha: 0.2))
                : (isDark ? Colors.white.withValues(alpha: 0.1) : AppColors.border.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          children: [
            // Check circle
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDone ? (isDark ? AppColors.successLight : AppColors.success) : Colors.transparent,
                shape: BoxShape.circle,
                border: isDone
                    ? null
                    : Border.all(
                        color: isDark ? Colors.white24 : AppColors.border,
                        width: 1.5,
                      ),
              ),
              child: isDone
                  ? Icon(LucideIcons.check, size: 14, color: isDark ? Colors.black : Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDone 
                          ? (isDark ? Colors.white38 : AppColors.textMuted) 
                          : (isDark ? Colors.white : AppColors.textDark),
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!isDone)
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: isDark ? Colors.white24 : AppColors.textPlaceholder,
              ),
          ],
        ),
      ),
    );
  }
}
