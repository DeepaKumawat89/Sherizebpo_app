import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../core/constants/constants.dart';
import '../core/theme/app_decorations.dart';
import '../routes.dart';
import '../services/platform_settings_service.dart';

class MyTaskCard extends StatefulWidget {
  final String assignmentId;
  final Map<String, dynamic> data;

  const MyTaskCard({Key? key, required this.assignmentId, required this.data}) : super(key: key);

  @override
  State<MyTaskCard> createState() => _MyTaskCardState();
}

class _MyTaskCardState extends State<MyTaskCard> {
  Timer? _tatTimer;
  Duration _timeRemaining = Duration.zero;
  bool _isOverdue = false;

  @override
  void initState() {
    super.initState();
    _initTatTimer();
  }

  void _initTatTimer() {
    final tatDeadlineRaw = widget.data['tatDeadline'];
    if (tatDeadlineRaw == null) return;

    DateTime deadline;
    if (tatDeadlineRaw is Timestamp) {
      deadline = tatDeadlineRaw.toDate();
    } else {
      return;
    }

    _updateRemaining(deadline);
    _tatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining(deadline);
    });
  }

  void _updateRemaining(DateTime deadline) {
    final now = DateTime.now();
    final diff = deadline.difference(now);
    setState(() {
      _timeRemaining = diff.isNegative ? Duration.zero : diff;
      _isOverdue = diff.isNegative;
    });
  }

  @override
  void dispose() {
    _tatTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(dynamic value) {
    final date = value is Timestamp ? value.toDate().toLocal()
        : value is DateTime ? value.toLocal() : null;
    return date == null ? 'Not recorded'
        : '${DateFormat('dd MMM yyyy, h:mm a').format(date)} ${date.timeZoneName}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final earningsEnabled =
        context.watch<PlatformSettingsService>().earningsSystemEnabled;
    final title = widget.data['title'] ?? 'Task';
    final status = (widget.data['status'] ?? 'active').toString().toLowerCase();
    final hasTat = widget.data['tatDeadline'] != null;

    final bool isActuallyOverdue = _isOverdue || status == 'out_of_tat';

    // Determine TAT color based on time left
    Color tatColor;
    if (isActuallyOverdue) {
      tatColor = AppColors.error;
    } else if (_timeRemaining.inMinutes < 30) {
      tatColor = AppColors.warning;
    } else {
      tatColor = AppColors.success;
    }

    // Only show "Start Working" for active tasks
    final isActive = status == 'active' || status == 'in_progress';

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isActuallyOverdue && isActive
              ? AppColors.error.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ),
              _buildStatusBadge(status, isDark),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(widget.data['clientName'] ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.white38 : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          for (final entry in <String, dynamic>{
            widget.data['assignedAt'] != null ? 'Assigned' : 'Accepted':
                widget.data['assignedAt'] ?? widget.data['acceptedAt'],
            if (widget.data['startedAt'] != null || status == 'in_progress')
              'Started': widget.data['startedAt'],
            if (hasTat) 'Deadline': widget.data['tatDeadline'],
            if (status == 'completed') 'Completed': widget.data['completedAt'],
            if (status == 'approved')
              'Approved': widget.data['approvedAt'] ?? widget.data['reviewedAt'],
            if (status == 'rejected')
              'Rejected': widget.data['rejectedAt'] ?? widget.data['reviewedAt'],
            if (status == 'revoked') 'Revoked': widget.data['revokedAt'],
            if (widget.data['updatedAt'] != null) 'Last updated': widget.data['updatedAt'],
          }.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${entry.key}: ${_formatDate(entry.value)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          // ── TAT Countdown ─────────────────────────────────
          if (hasTat && isActive) ...
            [
              const SizedBox(height: AppSizes.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: tatColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  border: Border.all(color: tatColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isActuallyOverdue ? LucideIcons.alertCircle : LucideIcons.timer,
                      size: 16,
                      color: tatColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isActuallyOverdue
                          ? 'TAT Overdue!'
                          : 'TAT: ${_formatDuration(_timeRemaining)} remaining',
                      style: TextStyle(
                        color: tatColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
          if (isActive) ...[
            const SizedBox(height: AppSizes.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isActuallyOverdue ? null : () {
                  Navigator.pushNamed(context, AppRoutes.taskExecution, arguments: {
                    'taskId': widget.data['taskId'],
                    'assignmentId': widget.assignmentId,
                    'payout': widget.data['payout'],
                    'clientName': widget.data['clientName'],
                    'tatDeadline': widget.data['tatDeadline'],
                    'totalLeads': ((widget.data['totalLeads'] ?? 0) as num).toInt(),
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActuallyOverdue ? (isDark ? Colors.white10 : AppColors.surfaceVariant) : AppColors.primary,
                  foregroundColor: isActuallyOverdue ? AppColors.textMuted : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
                ),
                child: Text(isActuallyOverdue ? 'Time Expired' : 'Start Working'),
              ),
            ),
          ] else if (earningsEnabled) ...[
             // For history view, show payout (hidden when earnings disabled)
             const SizedBox(height: AppSizes.md),
             Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
             const SizedBox(height: AppSizes.sm),
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text('Payout', style: TextStyle(color: isDark ? Colors.white54 : AppColors.textMuted)),
                   Text('₹${(widget.data['payout'] ?? 0).toStringAsFixed(0)}', 
                     style: TextStyle(
                       fontWeight: FontWeight.bold, 
                       color: isDark ? Colors.white : AppColors.textDark
                     )
                   ),
                ]
             )
          ]
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isDark) {
    Color color;
    if (status == 'completed' || status == 'approved') {
      color = AppColors.success;
    } else if (status == 'rejected' || status == 'out_of_tat') {
      color = AppColors.error;
    } else {
      color = AppColors.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(status.toUpperCase(),
        style: TextStyle(
          color: isDark ? Colors.white70 : color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
