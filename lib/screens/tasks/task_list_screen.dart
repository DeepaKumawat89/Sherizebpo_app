import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../services/platform_settings_service.dart';
import '../../services/task_service.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/my_task_card.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({Key? key}) : super(key: key);

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  User? get user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Task Marketplace'),
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
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH,
            ),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                boxShadow: isDark ? null : AppDecorations.shadowSm,
              ),
              dividerColor: Colors.transparent,
              labelColor: AppColors.primary,
              unselectedLabelColor:
                  isDark ? Colors.white38 : AppColors.textMuted,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Available'),
                Tab(text: 'My Tasks'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildAvailableTasks(),
          _buildMyTasks(),
        ],
      ),
    );
  }

  Widget _buildAvailableTasks() {
    return Column(
      children: [
        _buildTaskSearchField(),
        Expanded(child: _availableTasksList()),
      ],
    );
  }

  // Search bar so workers can jump to a specific task by its Task ID
  // (TSK-XXXX) or title instead of scrolling the whole marketplace.
  Widget _buildTaskSearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPaddingH,
        AppSizes.md,
        AppSizes.screenPaddingH,
        0,
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search by Task ID (e.g. TSK-1234) or title',
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _availableTasksList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('status', isEqualTo: 'active')
          .where('remainingSlots', isGreaterThan: 0)
          .where('totalLeads', isGreaterThan: 0)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: LucideIcons.alertCircle,
            title: 'Unable to load tasks',
            subtitle: 'Check your connection or contact admin.',
            isError: true,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingState();
        }

        final q = _searchQuery.trim().toLowerCase();
        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['distributionMode'] == 'individual') return false;
          final maxSlots = ((data['totalSlots'] ?? data['maxSlots'] ?? 1) as num).toInt();
          int acceptedCount = ((data['acceptedCount'] ?? 0) as num).toInt();
          if (acceptedCount >= maxSlots) return false;
          if (q.isEmpty) return true;
          // Match the friendly Task ID (TSK-XXXX), the title, the client name,
          // or the raw document id so any of them finds the task.
          final code = (data['taskCode'] ?? '').toString().toLowerCase();
          final title = (data['title'] ?? '').toString().toLowerCase();
          final client = (data['clientName'] ?? '').toString().toLowerCase();
          return code.contains(q) ||
              title.contains(q) ||
              client.contains(q) ||
              doc.id.toLowerCase().contains(q);
        }).toList();

        if (docs.isEmpty) {
          return _searchQuery.trim().isNotEmpty
              ? _buildEmptyState(
                  icon: LucideIcons.search,
                  title: 'No matching tasks',
                  subtitle: 'No available task matches "${_searchQuery.trim()}"',
                )
              : _buildEmptyState(
                  icon: LucideIcons.inbox,
                  title: 'No tasks available',
                  subtitle: 'Check back later for new opportunities',
                );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final taskId = docs[index].id;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.md),
              child: _AvailableTaskCard(
                taskId: taskId,
                data: data,
                userId: user?.uid ?? '',
                onAccepted: () {
                  SnackBarUtils.showSuccess('Task accepted successfully! 🎉');
                  _tabCtrl.animateTo(1);
                },
              ),
            );
          },
        );
      },
    );
  }

  bool _isActiveTask(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'active').toString().toLowerCase();

    if (status == 'completed' ||
      status == 'revoked' ||
      status == 'cancelled' ||
      status == 'out_of_tat_processing' ||
        status == 'rejected' ||
        status == 'out_of_tat' ||
        status == 'expired' ||
        status == 'approved') {
      return false;
    }

    final now = DateTime.now();
    final tatRaw = data['tatDeadline'];
    if (tatRaw is Timestamp && tatRaw.toDate().isBefore(now)) {
      return false;
    }
    return true;
  }

  Widget _buildMyTasks() {
    if (user == null) {
      return _buildEmptyState(
        icon: LucideIcons.logIn,
        title: 'Not logged in',
        subtitle: 'Please sign in to see your tasks',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_assignments')
          .where('userId', isEqualTo: user!.uid)
          .where('status', whereIn: ['active', 'in_progress', 'accepted', 'pending', 'assigned', 'pending_admin_review'])
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: LucideIcons.alertCircle,
            title: 'Error loading tasks',
            subtitle: 'Unable to fetch your assigned tasks.',
            isError: true,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingState();
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: LucideIcons.clipboardList,
            title: 'No tasks yet',
            subtitle: 'Accept tasks from the marketplace to get started',
          );
        }

        final activeDocs = docs
            .where((doc) => _isActiveTask(doc.data() as Map<String, dynamic>))
            .toList();

        // Sort active by TAT deadline ascending (most urgent first)
        activeDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTat = (aData['tatDeadline'] as Timestamp?)?.toDate();
          final bTat = (bData['tatDeadline'] as Timestamp?)?.toDate();
          if (aTat == null && bTat == null) return 0;
          if (aTat == null) return 1;
          if (bTat == null) return -1;
          return aTat.compareTo(bTat);
        });

        return ListView(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          children: [
            _buildActiveSectionHeader(activeDocs.length),
            const SizedBox(height: AppSizes.sm),
            if (activeDocs.isEmpty)
              _buildInlineEmpty(
                icon: LucideIcons.checkCircle2,
                message: 'No active tasks right now — great job! 🎉',
              )
            else
              ...activeDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.md),
                  child: MyTaskCard(
                    assignmentId: doc.id,
                    data: data,
                  ),
                );
              }),
            const SizedBox(height: AppSizes.xl),
          ],
        );
      },
    );
  }

  /// Header for the Active Tasks section.
  Widget _buildActiveSectionHeader(int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: AppDecorations.primaryGradient,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          child: const Icon(LucideIcons.zap, size: 14, color: Colors.white),
        ),
        const SizedBox(width: AppSizes.sm),
        Text(
          'Active Tasks',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
        ),
        const SizedBox(width: AppSizes.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSizes.radiusRound),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  /// Small inline empty-state placeholder (used inside sections).
  Widget _buildInlineEmpty({required IconData icon, required String message}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.xl),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.border.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: isDark ? Colors.white24 : AppColors.textPlaceholder),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white38 : AppColors.textMuted,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSizes.screenPaddingH),
      itemCount: 3,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: AppSizes.md),
        child: ShimmerCard(height: 160),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xxxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isError
                    ? AppColors.error.withValues(alpha: 0.1)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : AppColors.surfaceVariant),
                borderRadius: BorderRadius.circular(AppSizes.radiusXl),
              ),
              child: Icon(icon,
                  size: 32,
                  color: isError
                      ? AppColors.error
                      : (isDark ? Colors.white24 : AppColors.textPlaceholder)),
            ),
            const SizedBox(height: AppSizes.xl),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white38 : AppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableTaskCard extends StatefulWidget {
  final String taskId;
  final Map<String, dynamic> data;
  final String userId;
  final VoidCallback? onAccepted;

  const _AvailableTaskCard({
    required this.taskId,
    required this.data,
    required this.userId,
    this.onAccepted,
  });

  @override
  State<_AvailableTaskCard> createState() => _AvailableTaskCardState();
}

class _AvailableTaskCardState extends State<_AvailableTaskCard> {
  String _formatDate(dynamic value) {
    final date = value is Timestamp ? value.toDate().toLocal()
        : value is DateTime ? value.toLocal() : null;
    return date == null ? 'Not recorded'
        : '${DateFormat('dd MMM yyyy, h:mm a').format(date)} ${date.timeZoneName}';
  }
  bool _isAccepting = false;

  /// Shows a dialog when the task has no leads available.
  void _showNoLeadsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        backgroundColor: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.userX,
                  size: 30,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              // Title
              Text(
                'No Leads Available',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
              ),
              const SizedBox(height: AppSizes.sm),
              // Body
              Text(
                'This task currently has no leads to call. Please check back later or choose a different task.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppSizes.xl),
              // Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a dialog prompting the worker to complete KYC before they can
  /// accept or start a task.
  void _showKycRequiredDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        backgroundColor: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  size: 30,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                'Verify KYC to Start',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'You need an approved KYC before you can accept tasks and start working. Complete your verification to unlock tasks.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: AppSizes.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                        ),
                      ),
                      child: const Text('Later',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.pushNamed(context, AppRoutes.kyc);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Verify Now',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptTask() async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);

    try {
      // ── KYC gate: workers must be verified before accepting/starting work ──
      final meSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final kyc = (meSnap.data()?['kycStatus'] ??
              meSnap.data()?['kyc_status'] ??
              'pending')
          .toString()
          .toLowerCase();
      if (kyc != 'approved' && kyc != 'verified') {
        if (mounted) {
          setState(() => _isAccepting = false);
          _showKycRequiredDialog();
        }
        return;
      }

      await TaskService().acceptMarketplaceTask(
        taskId: widget.taskId,
      );
      widget.onAccepted?.call();
    } catch (e) {
      if (mounted) {
        if (e is FirebaseFunctionsException && e.message == 'No leads available') {
          _showNoLeadsDialog();
        } else {
          SnackBarUtils.showError(e.toString());
        }
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final earningsEnabled =
        context.watch<PlatformSettingsService>().earningsSystemEnabled;
    final title = widget.data['title'] ?? 'Untitled Task';
    final payout = (widget.data['payout'] ?? 0).toDouble();
    final totalLeads = ((widget.data['totalLeads'] ?? 0) as num).toInt();
    final totalSlots = ((widget.data['totalSlots'] ?? widget.data['maxSlots'] ?? 1) as num).toInt();
    final accepted = ((widget.data['acceptedCount'] ?? 0) as num).toInt();
    final slots = totalSlots > accepted ? totalSlots - accepted : 1;
    final myQuota = ((totalLeads + slots - 1) ~/ slots).clamp(0, totalLeads);

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppDecorations.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                child: const Icon(LucideIcons.phoneCall,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.data['clientName'] != null)
                      Text(
                        widget.data['clientName'],
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color:
                                  isDark ? Colors.white38 : AppColors.textMuted,
                            ),
                      ),
                    if ((widget.data['taskCode'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.data['taskCode'].toString(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
              if (earningsEnabled)
                Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                ),
                child: Text(
                  '₹${payout.toStringAsFixed(0)}',
                  style: TextStyle(
                    color:
                        isDark ? AppColors.successLight : AppColors.successDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            widget.data['description'] ?? 'No description',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white60 : AppColors.textMuted,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSizes.sm),
          Text('Created: ${_formatDate(widget.data['createdAt'])}',
              style: Theme.of(context).textTheme.bodySmall),
          if (widget.data['publishedAt'] != null)
            Text('Published: ${_formatDate(widget.data['publishedAt'])}',
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSizes.md),
          Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppColors.border.withValues(alpha: 0.3)),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.warning.withValues(alpha: 0.15)
                      : AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.list,
                        size: 14,
                        color: isDark
                            ? AppColors.warningLight
                            : AppColors.warningDark),
                    const SizedBox(width: 4),
                    Text(
                      '$myQuota ${myQuota == 1 ? 'lead' : 'leads'} for you',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.warningLight
                            : AppColors.warningDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _isAccepting ? null : _acceptTask,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    gradient:
                        _isAccepting ? null : AppDecorations.primaryGradient,
                    color: _isAccepting
                        ? (isDark ? Colors.white10 : AppColors.surfaceVariant)
                        : null,
                    borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                  ),
                  child: _isAccepting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary))
                      : const Text('Accept',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
