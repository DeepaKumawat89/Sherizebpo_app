import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../routes.dart';

class ProfileInformationScreen extends StatelessWidget {
  const ProfileInformationScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    this.showTaskHistory = false,
  });

  final String title;
  final IconData icon;
  final List<ProfileInformationItem> items;
  final bool showTaskHistory;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.base),
        children: [
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: AppSizes.lg),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          Container(
            padding: const EdgeInsets.all(AppSizes.base),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.border.withValues(alpha: 0.7),
              ),
              boxShadow: isDark ? null : AppDecorations.shadowMd,
            ),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _DetailRow(item: items[index]),
                  if (index < items.length - 1)
                    Divider(
                      height: AppSizes.xxl,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.15),
                    ),
                ],
              ],
            ),
          ),
          if (showTaskHistory) ...[
            const SizedBox(height: AppSizes.xl),
            _TaskHistoryCard(
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.taskHistory),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileInformationItem {
  const ProfileInformationItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.item});

  final ProfileInformationItem item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Icon(item.icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                    ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                item.value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskHistoryCard extends StatelessWidget {
  const _TaskHistoryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusXl),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.base),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.7),
          ),
        ),
        child: const Row(
          children: [
            Icon(LucideIcons.history, color: AppColors.primary),
            SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                'Task History',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
