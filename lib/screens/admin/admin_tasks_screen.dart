import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({Key? key}) : super(key: key);

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  final Set<String> _processingIds = {};
  Future<QuerySnapshot>? _tasksFuture;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  void _loadTasks() {
    _tasksFuture = _fetchTasks();
  }

  Future<QuerySnapshot> _fetchTasks() async {
    // Best-effort token refresh so a freshly-assigned admin/super_admin role
    // claim reaches the Firestore rules (the lead stats read campaign_leads,
    // which requires isAdmin()). Bounded + guarded: on web getIdToken(true) can
    // hang, so we never let it block the query (falls back to cached token).
    try {
      await FirebaseAuth.instance.currentUser
          ?.getIdToken(true)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Ignore — proceed with the existing (cached) token.
    }
    return FirebaseFirestore.instance
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
  }

  Future<void> _toggleTaskStatus(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final data = doc.data() as Map<String, dynamic>;
    final currentStatus = data['status']?.toString() ?? 'inactive';
    final newStatus = currentStatus == 'active' || currentStatus == 'available'
        ? 'paused'
        : 'active';

    setState(() => _processingIds.add(id));
    try {
      await doc.reference.update({'status': newStatus});
      if (!mounted) return;
      if (!mounted) return;
      SnackBarUtils.showInfo('Task marked as $newStatus');
      setState(() => _loadTasks());
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  Future<void> _deleteTask(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text(
            'Are you sure you want to permanently delete this task?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingIds.add(id));
    try {
      await doc.reference.update({'status': 'deleted'}); // Soft delete
      if (!mounted) return;
      SnackBarUtils.showSuccess('Task deleted successfully.');
      setState(() => _loadTasks());
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  void _showEditDialog(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final titleCtrl =
        TextEditingController(text: data['title']?.toString() ?? '');
    final payoutCtrl =
        TextEditingController(text: data['payout']?.toString() ?? '0');
    final slotsCtrl =
        TextEditingController(text: data['totalSlots']?.toString() ?? '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Task Title'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: payoutCtrl,
                decoration: const InputDecoration(labelText: 'Payout'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: slotsCtrl,
                decoration: const InputDecoration(labelText: 'Total Slots'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newTitle = titleCtrl.text.trim();
              final newPayout = double.tryParse(payoutCtrl.text.trim()) ?? 0;
              final newSlots = int.tryParse(slotsCtrl.text.trim()) ?? 0;

              if (newTitle.isNotEmpty && newPayout > 0 && newSlots > 0) {
                Navigator.pop(ctx);
                try {
                  await doc.reference.update({
                    'title': newTitle,
                    'payout': newPayout,
                    'totalSlots': newSlots,
                    'remainingSlots': data[
                        'remainingSlots'], // Usually we calculate this but limit to basic edit
                  });
                  if (!mounted) return;
                  SnackBarUtils.showSuccess('Task updated');
                  setState(() => _loadTasks());
                } catch (e) {
                  if (!mounted) return;
                  SnackBarUtils.showError('Error: $e');
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Tasks'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _loadTasks()),
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Admin Tasks Error: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertCircle, color: AppColors.error, size: 48),
                    const SizedBox(height: AppSizes.md),
                    const Text('Error loading tasks', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSizes.sm),
                    Text('${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          // Filter out deleted tasks on the client side to bypass composite index requirement
          final docs = allDocs.where((doc) {
             final data = doc.data() as Map<String, dynamic>;
             return data['status'] != 'deleted';
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Text('No tasks found.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(
                bottom: 80,
                left: AppSizes.md,
                right: AppSizes.md,
                top: AppSizes.md),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isProcessing = _processingIds.contains(doc.id);

              final title = data['title']?.toString() ?? 'Untitled';
              final taskCode = data['taskCode']?.toString() ?? '';
              final payout = data['payout']?.toString() ?? '0';
              final totalSlots = data['totalSlots']?.toString() ?? '0';
              final remainingSlots = data['remainingSlots']?.toString() ?? '0';
              final status = data['status']?.toString() ?? 'inactive';
              final isActive = status == 'active' || status == 'available';

              return Card(
                margin: const EdgeInsets.only(bottom: AppSizes.md),
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Paused',
                              style: TextStyle(
                                color: isActive
                                    ? AppColors.success
                                    : AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (taskCode.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(taskCode,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: AppSizes.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStat('Payout', '₹$payout'),
                          _buildStat(
                              'Remaining', '$remainingSlots/$totalSlots'),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      // ── Lead Stats ──────────────────────────────
                      _buildLeadStats(data['campaignId']?.toString() ?? doc.id),
                      const SizedBox(height: AppSizes.md),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _showEditDialog(doc),
                                icon: const Icon(LucideIcons.edit,
                                    color: AppColors.primary),
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                onPressed: isProcessing
                                    ? null
                                    : () => _deleteTask(doc),
                                icon: const Icon(LucideIcons.trash2,
                                    color: AppColors.error),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: isProcessing
                                ? null
                                : () => _toggleTaskStatus(doc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isActive
                                  ? AppColors.warning
                                  : AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                            icon: isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Icon(
                                    isActive
                                        ? LucideIcons.pause
                                        : LucideIcons.play,
                                    size: 16),
                            label: Text(isActive ? 'Pause' : 'Activate'),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildLeadStats(String campaignId) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('campaign_leads')
          .where('campaignId', isEqualTo: campaignId)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 18,
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        // On error (or no data) don't hang the bar — just hide the stats.
        if (snap.hasError || !snap.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snap.data!.docs;
        final total = docs.length;
        String statusOf(QueryDocumentSnapshot d) =>
            ((d.data() as Map<String, dynamic>)['status'] ?? '').toString();
        // "Completed" = leads that passed QA (approved) — the final billable
        // state. A lead with status 'completed' is a finished call still awaiting
        // review, so it belongs with the in-progress pipeline, not done.
        final completed = docs.where((d) => statusOf(d) == 'approved').length;
        final inProgress = docs.where((d) {
          final s = statusOf(d);
          return s == 'in_progress' || s == 'assigned' || s == 'completed';
        }).length;
        final pending = docs.where((d) {
          final s = statusOf(d);
          return s.isEmpty || s == 'pending' || s == 'requeue_pending';
        }).length;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildLeadBadge('Pending', pending, AppColors.warning),
              _buildLeadBadge('In Progress', inProgress, AppColors.info),
              _buildLeadBadge('Completed', completed, AppColors.success),
              _buildLeadBadge('Total', total, AppColors.primary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeadBadge(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}
