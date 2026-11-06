import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({Key? key}) : super(key: key);

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} mins ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays == 1) return 'Yesterday';
    return '${difference.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: isDark ? Colors.white : AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
        actions: [
          TextButton(
            onPressed: () async {
              await NotificationService().markAllAsRead();
              if (!context.mounted) return;
              SnackBarUtils.showSuccess('All notifications marked as read.');
            },
            child: const Text(
              'Mark all as read',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: NotificationService().getUserNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.bellOff,
                      size: 64, 
                      color: isDark ? Colors.white10 : AppColors.textLightest),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : AppColors.textMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return NotificationTile(
                notification: notification,
                timeText: _formatTime(notification.createdAt),
              );
            },
          );
        },
      ),
    );
  }
}

/// A reusable widget to display a single notification item.
class NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final String timeText;

  const NotificationTile({
    Key? key,
    required this.notification,
    required this.timeText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: notification.read
          ? Colors.transparent
          : (isDark 
              ? AppColors.primary.withValues(alpha: 0.1) 
              : AppColors.infoBg.withValues(alpha: 0.3)),
      child: InkWell(
        onTap: () async {
          if (!notification.read) {
            await NotificationService().markAsRead(notification.id);
          }

          final String? relatedTaskId = notification.relatedTaskId;
          final String? relatedSubmissionId = notification.relatedSubmissionId;

          if (!context.mounted) return;
          if (relatedSubmissionId != null && relatedSubmissionId.isNotEmpty) {
            Navigator.pushNamed(
              context,
              AppRoutes.submissionDetail,
              arguments: {'submissionId': relatedSubmissionId},
            );
          } else if (relatedTaskId != null && relatedTaskId.isNotEmpty) {
            Navigator.pushNamed(
              context,
              AppRoutes.taskList,
              arguments: {'taskId': relatedTaskId},
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPaddingH,
            vertical: AppSizes.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon Box ──
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getIconBackgroundColor(isDark),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIconData(),
                  color: _getIconColor(isDark),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSizes.md),

              // ── Content ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              color: isDark ? Colors.white : AppColors.textDark,
                              fontSize: 15,
                              fontWeight: notification.read
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!notification.read)
                          Container(
                            margin: const EdgeInsets.only(
                                left: AppSizes.sm, top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.info,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        color: notification.read
                            ? (isDark ? Colors.white60 : AppColors.textBody)
                            : (isDark ? Colors.white : AppColors.textDark),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      timeText,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconData() {
    switch (notification.type) {
      case 'task_assigned':
      case 'task_submission_received':
        return LucideIcons.briefcase;
      case 'payment_released':
      case 'withdrawal_approved':
        return LucideIcons.banknote;
      case 'submission_approved':
        return LucideIcons.checkCircle;
      case 'submission_rejected':
      case 'withdrawal_rejected':
        return LucideIcons.xCircle;
      case 'admin_message':
      default:
        return LucideIcons.bell;
    }
  }

  Color _getIconColor(bool isDark) {
    switch (notification.type) {
      case 'task_assigned':
      case 'task_submission_received':
        return isDark ? AppColors.primaryLight : AppColors.primary;
      case 'payment_released':
      case 'withdrawal_approved':
      case 'submission_approved':
        return isDark ? AppColors.successLight : AppColors.success;
      case 'submission_rejected':
      case 'withdrawal_rejected':
        return isDark ? AppColors.errorLight : AppColors.error;
      case 'admin_message':
      default:
        return isDark ? AppColors.infoLight : AppColors.info;
    }
  }

  Color _getIconBackgroundColor(bool isDark) {
    switch (notification.type) {
      case 'task_assigned':
      case 'task_submission_received':
        return isDark 
          ? AppColors.primary.withValues(alpha: 0.15) 
          : AppColors.primaryLight.withValues(alpha: 0.1);
      case 'payment_released':
      case 'withdrawal_approved':
      case 'submission_approved':
        return isDark 
          ? AppColors.success.withValues(alpha: 0.15) 
          : AppColors.successBg;
      case 'submission_rejected':
      case 'withdrawal_rejected':
        return isDark 
          ? AppColors.error.withValues(alpha: 0.15) 
          : AppColors.errorBg;
      case 'admin_message':
      default:
        return isDark 
          ? AppColors.info.withValues(alpha: 0.15) 
          : AppColors.infoBg;
    }
  }
}
