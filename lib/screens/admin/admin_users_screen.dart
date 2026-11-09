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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                fontWeight: FontWeight.w700,
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.errorBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.error_outline,
                          size: 32, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
 
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(Icons.people_outline,
                        size: 40, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No users found.',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }
 
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSizes.md),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isProcessing = _processingIds.contains(doc.id);
                  final userName = data['name']?.toString() ?? 'Employee';
                  final phone = data['phone']?.toString() ?? 'No Phone';
                  final kycStatus =
                      data['kycStatus']?.toString() ?? 'unverified';
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
 
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSizes.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.person_outline,
                                    size: 24, color: AppColors.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            height: 1.3)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_outlined,
                                            size: 14,
                                            color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(phone,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: AppColors.textMuted)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSuspended
                                      ? AppColors.errorBg
                                      : AppColors.success
                                          .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSuspended
                                            ? AppColors.error
                                            : AppColors.success,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isSuspended ? 'Suspended' : 'Active',
                                      style: TextStyle(
                                        color: isSuspended
                                            ? AppColors.error
                                            : AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 4),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildStatColumn(
                                      'KYC', kycStatus.toUpperCase()),
                                  _statDivider(),
                                  _buildStatColumn('Earnings',
                                      '₹${earnings.toStringAsFixed(0)}'),
                                  _statDivider(),
                                  _buildStatColumn('Wallet',
                                      '₹${walletBalance.toStringAsFixed(0)}'),
                                  _statDivider(),
                                  _buildStatColumn('Tasks', '$completedTasks'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          Row(
                            children: [
                              Expanded(
                                child: isSuspended
                                    ? ElevatedButton(
                                        onPressed: isProcessing
                                            ? null
                                            : () =>
                                                _toggleUserStatus(doc, true),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size(0, 48),
                                          elevation: 0,
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          textStyle: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        child: isProcessing
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white))
                                            : const Text('Activate'),
                                      )
                                    : OutlinedButton(
                                        onPressed: isProcessing
                                            ? null
                                            : () =>
                                                _toggleUserStatus(doc, false),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 48),
                                          foregroundColor: AppColors.error,
                                          side: const BorderSide(
                                              color: AppColors.error),
                                          textStyle: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        child: isProcessing
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
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
              ),
            ),
          );
        },
      ),
    );
  }
 
  Widget _statDivider() => VerticalDivider(
        width: 1,
        thickness: 1,
        color: Colors.grey.shade300,
      );
 
  Widget _buildStatColumn(String label, String value) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}