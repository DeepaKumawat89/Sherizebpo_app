// import 'package:flutter/material.dart';
// import 'package:lucide_icons/lucide_icons.dart';

// import '../../core/constants/constants.dart';
// import '../../core/theme/app_decorations.dart';
// import '../../routes.dart';

// class ProfileInformationScreen extends StatelessWidget {
//   const ProfileInformationScreen({
//     super.key,
//     required this.title,
//     required this.icon,
//     required this.items,
//     this.showTaskHistory = false,
//   });

//   final String title;
//   final IconData icon;
//   final List<ProfileInformationItem> items;
//   final bool showTaskHistory;

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     return Scaffold(
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       appBar: AppBar(
//         title: Text(title),
//         backgroundColor: Colors.white,
//         foregroundColor: AppColors.textDark,
//         surfaceTintColor: Colors.transparent,
//       ),
//       body: ListView(
//         padding: const EdgeInsets.all(AppSizes.base),
//         children: [
//           Container(
//             width: 64,
//             height: 64,
//             margin: const EdgeInsets.only(bottom: AppSizes.lg),
//             decoration: BoxDecoration(
//               color: AppColors.primary.withValues(alpha: 0.12),
//               borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//             ),
//             child: Icon(icon, color: AppColors.primary, size: 30),
//           ),
//           Container(
//             padding: const EdgeInsets.all(AppSizes.base),
//             decoration: BoxDecoration(
//               color: Theme.of(context).cardColor,
//               borderRadius: BorderRadius.circular(AppSizes.radiusXl),
//               border: Border.all(
//                 color: isDark
//                     ? Colors.white.withValues(alpha: 0.08)
//                     : AppColors.border.withValues(alpha: 0.7),
//               ),
//               boxShadow: isDark ? null : AppDecorations.shadowMd,
//             ),
//             child: Column(
//               children: [
//                 for (var index = 0; index < items.length; index++) ...[
//                   _DetailRow(item: items[index]),
//                   if (index < items.length - 1)
//                     Divider(
//                       height: AppSizes.xxl,
//                       color: Theme.of(context)
//                           .dividerColor
//                           .withValues(alpha: 0.15),
//                     ),
//                 ],
//               ],
//             ),
//           ),
//           if (showTaskHistory) ...[
//             const SizedBox(height: AppSizes.xl),
//             _TaskHistoryCard(
//               onTap: () =>
//                   Navigator.pushNamed(context, AppRoutes.taskHistory),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
// }

// class ProfileInformationItem {
//   const ProfileInformationItem({
//     required this.icon,
//     required this.label,
//     required this.value,
//   });

//   final IconData icon;
//   final String label;
//   final String value;
// }

// class _DetailRow extends StatelessWidget {
//   const _DetailRow({required this.item});

//   final ProfileInformationItem item;

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Container(
//           width: 40,
//           height: 40,
//           decoration: BoxDecoration(
//             color: AppColors.primary.withValues(alpha: 0.12),
//             borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//           ),
//           child: Icon(item.icon, color: AppColors.primary, size: 20),
//         ),
//         const SizedBox(width: AppSizes.md),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 item.label,
//                 style: Theme.of(context).textTheme.labelMedium?.copyWith(
//                       color: isDark ? Colors.white54 : AppColors.textMuted,
//                     ),
//               ),
//               const SizedBox(height: AppSizes.xs),
//               Text(
//                 item.value,
//                 style: Theme.of(context).textTheme.bodyLarge?.copyWith(
//                       color: isDark ? Colors.white : AppColors.textDark,
//                       fontWeight: FontWeight.w600,
//                     ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _TaskHistoryCard extends StatelessWidget {
//   const _TaskHistoryCard({required this.onTap});

//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(AppSizes.radiusXl),
//       child: Container(
//         padding: const EdgeInsets.all(AppSizes.base),
//         decoration: BoxDecoration(
//           color: Theme.of(context).cardColor,
//           borderRadius: BorderRadius.circular(AppSizes.radiusXl),
//           border: Border.all(
//             color: AppColors.border.withValues(alpha: 0.7),
//           ),
//         ),
//         child: const Row(
//           children: [
//             Icon(LucideIcons.history, color: AppColors.primary),
//             SizedBox(width: AppSizes.md),
//             Expanded(
//               child: Text(
//                 'Task History',
//                 style: TextStyle(fontWeight: FontWeight.w700),
//               ),
//             ),
//             Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
//           ],
//         ),
//       ),
//     );
//   }
// }



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
    final textTheme = Theme.of(context).textTheme;
    final accent = isDark ? AppColors.primaryLight : AppColors.primary;
 
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSizes.base,
          AppSizes.sm,
          AppSizes.base,
          AppSizes.xxl,
        ),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12),
                  AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: AppSizes.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: AppSizes.xs),
                      Text(
                        items.length == 1
                            ? '1 detail'
                            : '${items.length} details',
                        style: textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white60 : AppColors.textBody,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
 
          // Details
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.base,
              vertical: AppSizes.sm,
            ),
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
                  _DetailRow(item: items[index], accent: accent),
                  if (index < items.length - 1)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : AppColors.borderLight,
                    ),
                ],
              ],
            ),
          ),
          if (showTaskHistory) ...[
            const SizedBox(height: AppSizes.lg),
            _TaskHistoryCard(
              accent: accent,
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
  const _DetailRow({required this.item, required this.accent});
 
  final ProfileInformationItem item;
  final Color accent;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
 
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(item.icon, color: accent, size: 19),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: textTheme.labelMedium?.copyWith(
                    color: isDark ? Colors.white54 : AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  style: textTheme.bodyLarge?.copyWith(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 
class _TaskHistoryCard extends StatelessWidget {
  const _TaskHistoryCard({required this.onTap, required this.accent});
 
  final VoidCallback onTap;
  final Color accent;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
 
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border.withValues(alpha: 0.7),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.base),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Icon(LucideIcons.history, color: accent, size: 20),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Task History',
                        style: textTheme.titleSmall?.copyWith(
                          color: isDark ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'View your past and completed tasks',
                        style: textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white54 : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: isDark ? Colors.white38 : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
 