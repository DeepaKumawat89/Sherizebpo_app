import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({Key? key}) : super(key: key);

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final Set<String> _processingIds = {};

  Future<void> _toggleUserStatus(DocumentSnapshot doc, bool isSuspended) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuspended ? 'Activate User?' : 'Suspend User?'),
        content: Text(
            'Are you sure you want to ${isSuspended ? 'activate' : 'suspend'} this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isSuspended ? 'Activate' : 'Suspend',
              style: TextStyle(
                color: isSuspended ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingIds.add(id));

    try {
      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'status': isSuspended ? 'active' : 'suspended',
      });
      if (!mounted) return;
      if (!mounted) return;
      if (isSuspended) {
        SnackBarUtils.showSuccess('User activated successfully.');
      } else {
        SnackBarUtils.showError('User suspended.');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'worker')
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No users found.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.md),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isProcessing = _processingIds.contains(doc.id);
              final userName = data['name']?.toString() ?? 'Employee';
              final phone = data['phone']?.toString() ?? 'No Phone';
              final kycStatus = data['kycStatus']?.toString() ?? 'unverified';
              final status = data['status']?.toString() ?? 'active';
              final isSuspended = status == 'suspended';
              final earningsRaw = data['earnings'] ?? 0;
              final earnings = earningsRaw is num
                  ? earningsRaw.toDouble()
                  : double.tryParse(earningsRaw.toString()) ?? 0.0;
              final walletRaw = data['walletBalance'] ?? 0;
              final walletBalance = walletRaw is num
                  ? walletRaw.toDouble()
                  : double.tryParse(walletRaw.toString()) ?? 0.0;
              final tasksRaw =
                  data['completedTasks'] ?? data['completed_tasks'] ?? 0;
              final completedTasks = tasksRaw is num
                  ? tasksRaw.toInt()
                  : int.tryParse(tasksRaw.toString()) ?? 0;

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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                Text(phone,
                                    style: const TextStyle(
                                        color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSuspended
                                  ? AppColors.errorBg
                                  // ignore: deprecated_member_use
                                  : AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isSuspended ? 'Suspended' : 'Active',
                              style: TextStyle(
                                color: isSuspended
                                    ? AppColors.error
                                    : AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatColumn('KYC', kycStatus.toUpperCase()),
                          _buildStatColumn(
                              'Earnings', '₹${earnings.toStringAsFixed(0)}'),
                          _buildStatColumn(
                              'Wallet', '₹${walletBalance.toStringAsFixed(0)}'),
                          _buildStatColumn('Tasks', '$completedTasks'),
                        ],
                      ),
                      const SizedBox(height: AppSizes.md),
                      const Divider(),
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        children: [
                          Expanded(
                            child: isSuspended
                                ? ElevatedButton(
                                    onPressed: isProcessing
                                        ? null
                                        : () => _toggleUserStatus(doc, true),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                        foregroundColor: Colors.white),
                                    child: isProcessing
                                        ? const CircularProgressIndicator(
                                            color: Colors.white)
                                        : const Text('Activate'),
                                  )
                                : OutlinedButton(
                                    onPressed: isProcessing
                                        ? null
                                        : () => _toggleUserStatus(doc, false),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error),
                                    child: isProcessing
                                        ? const CircularProgressIndicator()
                                        : const Text('Suspend'),
                                  ),
                          ),
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

  Widget _buildStatColumn(String label, String value) {
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
}
