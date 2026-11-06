import 'dart:collection';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../services/platform_settings_service.dart';
import '../../widgets/my_task_card.dart';

class TaskHistoryScreen extends StatefulWidget {
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  const TaskHistoryScreen({Key? key, this.auth, this.firestore}) : super(key: key);

  @override
  State<TaskHistoryScreen> createState() => _TaskHistoryScreenState();
}

class _TaskHistoryScreenState extends State<TaskHistoryScreen> {
  final Set<String> _expandedDays = {};

  User? get user => (widget.auth ?? FirebaseAuth.instance).currentUser;

  DateTime? _assignmentDate(Map<String, dynamic> data) {
    final value = data['assignedAt'] ?? data['acceptedAt'];
    return value is Timestamp ? value.toDate().toLocal()
        : value is DateTime ? value.toLocal() : null;
  }

  bool _isHistoryTask(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'active').toString().toLowerCase();

    // Terminal statuses always go to history
    if (status == 'completed' ||
        status == 'rejected' ||
      status == 'revoked' ||
      status == 'cancelled' ||
        status == 'out_of_tat' ||
        status == 'expired' || 
        status == 'approved') {
      return true;
    }

    // If TAT deadline has passed, treat as history even if status not updated yet
    final now = DateTime.now();
    final tatRaw = data['tatDeadline'];
    if (tatRaw is Timestamp && tatRaw.toDate().isBefore(now)) {
      return true;
    }

    return false;
  }

  /// Groups history docs by calendar day label ("Today" / "Yesterday" / "Apr 15").
  /// Returns a [LinkedHashMap] ordered newest day first.
  Map<String, List<QueryDocumentSnapshot>> _groupByDay(
      List<QueryDocumentSnapshot> docs) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterdayDate = todayDate.subtract(const Duration(days: 1));

    // Build ordered map: sort by date descending first
    final sorted = [...docs];
    sorted.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aTs = _assignmentDate(aData)?.millisecondsSinceEpoch ?? -8640000000000000;
      final bTs = _assignmentDate(bData)?.millisecondsSinceEpoch ?? -8640000000000000;
      return bTs.compareTo(aTs); // newest first
    });

    final result = <String, List<QueryDocumentSnapshot>>{};

    for (final doc in sorted) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = _assignmentDate(data);
      if (ts == null) {
        result.putIfAbsent('Date not recorded', () => []).add(doc);
        continue;
      }
      final docDate = DateTime(ts.year, ts.month, ts.day);

      String label;
      if (docDate == todayDate) {
        label = 'Today';
      } else if (docDate == yesterdayDate) {
        label = 'Yesterday';
      } else {
        label = DateFormat('dd MMM yyyy').format(ts);
      }

      result.putIfAbsent(label, () => []).add(doc);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task History')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Task History'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: (widget.firestore ?? FirebaseFirestore.instance)
            .collection('task_assignments')
            .where('userId', isEqualTo: user!.uid)
            .limit(200) // Increase limit for history
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Error loading history.'));
          }

          final docs = snapshot.data?.docs ?? [];
          final historyDocs = docs.where((d) => _isHistoryTask(d.data() as Map<String, dynamic>)).toList();

          if (historyDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSizes.radiusXl),
                    ),
                    child: Icon(LucideIcons.history,
                      size: 32,
                      color: isDark ? Colors.white24 : AppColors.textPlaceholder),
                  ),
                  const SizedBox(height: AppSizes.xl),
                  Text('No History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Text('Completed tasks will appear here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white38 : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }

          final groupedHistory = _groupByDay(historyDocs);

          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.screenPaddingH),
            itemCount: groupedHistory.length,
            itemBuilder: (context, index) {
              final label = groupedHistory.keys.elementAt(index);
              final dayDocs = groupedHistory[label]!;
              final isExpanded = _expandedDays.contains(label);

              // Calculate total earned for this day
              double earned = 0;
              for (final doc in dayDocs) {
                final d = doc.data() as Map<String, dynamic>;
                // Only sum up if approved or completed based on your business logic.
                final status = (d['status'] ?? '').toString().toLowerCase();
                if (status == 'completed' || status == 'approved') {
                  earned += (d['payout'] ?? 0).toDouble();
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDayAccordionHeader(
                    label: label,
                    tasksCount: dayDocs.length,
                    earned: earned,
                    isExpanded: isExpanded,
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedDays.remove(label);
                        } else {
                          _expandedDays.add(label);
                        }
                      });
                    },
                    isDark: isDark,
                  ),
                  if (isExpanded)
                    ...dayDocs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: MyTaskCard(
                          assignmentId: doc.id,
                          data: data,
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: AppSizes.md),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDayAccordionHeader({
    required String label,
    required int tasksCount,
    required double earned,
    required bool isExpanded,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final earningsEnabled =
        context.watch<PlatformSettingsService>().earningsSystemEnabled;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSizes.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(
            color: isExpanded
              ? AppColors.primary.withValues(alpha: 0.5)
              : (isDark ? Colors.white10 : AppColors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? AppColors.info.withValues(alpha: 0.15) : AppColors.infoBg,
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Text('$tasksCount Tasks',
                style: TextStyle(
                  color: isDark ? AppColors.infoLight : AppColors.infoDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (earningsEnabled) ...[
              const SizedBox(width: AppSizes.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.success.withValues(alpha: 0.15) : AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Text('₹${earned.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: isDark ? AppColors.successLight : AppColors.successDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: AppSizes.sm),
            Icon(
              isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 20,
              color: isDark ? Colors.white38 : AppColors.textMuted,
            )
          ],
        ),
      ),
    );
  }
}
