import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
 
class AdminWithdrawalsScreen extends StatefulWidget {
  const AdminWithdrawalsScreen({Key? key}) : super(key: key);
 
  @override
  State<AdminWithdrawalsScreen> createState() => _AdminWithdrawalsScreenState();
}
 
class _AdminWithdrawalsScreenState extends State<AdminWithdrawalsScreen> {
  final Set<String> _processingIds = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _selectedTabIndex = 0;
 
  final List<String> _tabs = ['All', 'Pending', 'Approved', 'Paid', 'Rejected', 'Failed', 'Refunded'];
  final Map<String, Map<String, dynamic>> _userCache = {};
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
 
  final Map<String, bool> _isLoadingUser = {};
 
  Future<void> _getUserData(String userId) async {
    if (_userCache.containsKey(userId) || _isLoadingUser[userId] == true) return;
    
    _isLoadingUser[userId] = true;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _userCache[userId] = data;
          _isLoadingUser.remove(userId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _userCache[userId] = {}; // Cache empty to avoid infinite retries
          _isLoadingUser.remove(userId);
        });
      }
    }
  }
 
  Future<void> _processWithdrawal(DocumentSnapshot doc, bool isApproved) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;
 
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final amountRaw = data['amount'] ?? 0;
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw.toString()) ?? 0.0;
 
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isApproved ? 'Approve Withdrawal?' : 'Reject Withdrawal?'),
        content: Text('Are you sure you want to ${isApproved ? 'approve' : 'reject'} this ₹$amount withdrawal request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: isApproved ? AppColors.success : AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(isApproved ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
 
    if (confirmed != true) return;
    setState(() => _processingIds.add(id));
 
    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final callable = FirebaseFunctions.instance.httpsCallable('processWithdrawal');
      await callable.call({
        'withdrawRequestId': id,
        'adminId': adminId,
        'status': isApproved ? 'approved' : 'rejected',
      });
 
      if (!mounted) return;
      if (isApproved) {
        SnackBarUtils.showSuccess('Withdrawal approved successfully.');
      } else {
        SnackBarUtils.showError('Withdrawal rejected.');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }
 
  Future<void> _markAsPaid(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;
 
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Paid manually?'),
        content: const Text('Are you sure you want to forcibly mark this transfer as Paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Mark as Paid'),
          ),
        ],
      ),
    );
 
    if (confirmed != true) return;
    setState(() => _processingIds.add(id));
 
    try {
      await FirebaseFirestore.instance.collection('withdraw_requests').doc(id).update({
        'status': 'paid',
        'manualOverrideAt': FieldValue.serverTimestamp(),
        'adminId': FirebaseAuth.instance.currentUser?.uid,
      });
      if (!mounted) return;
      SnackBarUtils.showSuccess('Marked as paid successfully.');
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }
 
  Future<void> _retryPayout(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;
 
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retry Payout?'),
        content: const Text(
            'This will fetch the user\'s latest UPI ID and attempt the Razorpay payment again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
 
    if (confirmed != true) return;
    setState(() => _processingIds.add(id));
 
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('retryWithdrawalPayout');
      final result = await callable.call({'withdrawalId': id});
 
      if (!mounted) return;
      SnackBarUtils.showSuccess(result.data['message'] ?? 'Payout retry successful.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Retry Failed: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }
 
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'approved': return Colors.blue;
      case 'paid': return AppColors.success;
      case 'refunded': return Colors.deepPurple;
      case 'failed':
      case 'rejected': return AppColors.error;
      default: return AppColors.textLight;
    }
  }
 
  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> allDocs) {
    final statusFilter = _tabs[_selectedTabIndex].toLowerCase();
    return allDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final docStatus = (data['status']?.toString() ?? 'pending').toLowerCase();
      if (statusFilter != 'all' && docStatus != statusFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final userId = data['userId']?.toString().toLowerCase() ?? '';
        final lq = _searchQuery.toLowerCase();
        bool matchesId = userId.contains(lq);
        bool matchesName = false;
        if (_userCache.containsKey(data['userId'])) {
          final userData = _userCache[data['userId']];
          final name = (userData?['fullName']?.toString() ?? userData?['name']?.toString() ?? '').toLowerCase();
          matchesName = name.contains(lq);
        }
        if (!matchesId && !matchesName) return false;
      }
      return true;
    }).toList();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Withdrawal Requests'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Tab chips row (below the app bar)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final selected = _selectedTabIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_tabs[i]),
                      selected: selected,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(
                          color: selected ? AppColors.primary : Colors.grey.shade300,
                        ),
                      ),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: selected ? Colors.white : Colors.grey.shade700,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) => setState(() => _selectedTabIndex = i),
                    ),
                  );
                }),
              ),
            ),
          ),
 
          // Search bar + content (centered, max width)
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSizes.md, AppSizes.md, AppSizes.md, AppSizes.sm),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by User ID or Name...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey.shade300,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 14),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      ),
                    ),
 
                    // Content
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('withdraw_requests')
                            .limit(200)
                            .snapshots(),
                        builder: (context, snapshot) {
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
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.error_outline,
                                          size: 32, color: AppColors.error),
                                    ),
                                    const SizedBox(height: 16),
                                    SelectableText(
                                      'Error: ${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.red, fontSize: 14, height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
 
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
 
                          final allDocs = snapshot.data?.docs ?? [];
 
                          // Sort client-side by requestedAt descending
                          allDocs.sort((a, b) {
                            final aData = a.data() as Map<String, dynamic>? ?? {};
                            final bData = b.data() as Map<String, dynamic>? ?? {};
                            final aTime = aData['requestedAt'];
                            final bTime = bData['requestedAt'];
                            if (aTime == null && bTime == null) return 0;
                            if (aTime == null) return 1;
                            if (bTime == null) return -1;
                            if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
                            return 0;
                          });
 
                          final filteredDocs = _filterDocs(allDocs);
 
                          if (filteredDocs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade500),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    allDocs.isEmpty
                                        ? 'No withdrawal requests yet'
                                        : 'No ${_tabs[_selectedTabIndex]} requests found',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            );
                          }
 
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.md),
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final data = doc.data() as Map<String, dynamic>? ?? {};
                              final userId = data['userId']?.toString() ?? '';
                              if (!_userCache.containsKey(userId) && userId.isNotEmpty) {
                                _getUserData(userId);
                              }
                              return _buildWithdrawalCard(doc, data);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _detailRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700)),
          ),
        ],
      );
 
  ButtonStyle _filledStyle(Color bg) => ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      );
 
  ButtonStyle _outlinedStyle(Color fg) => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: fg,
        side: BorderSide(color: fg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      );
 
  Widget _buildWithdrawalCard(DocumentSnapshot doc, Map<String, dynamic> data) {
    final isProcessing = _processingIds.contains(doc.id);
    final userId = data['userId']?.toString() ?? 'Unknown';
    final amountStr = data['amount']?.toString() ?? '0.0';
    final status = data['status']?.toString() ?? 'pending';
 
    final userData = _userCache[userId];
    final workerName = userData != null
        ? (userData['fullName']?.toString() ?? userData['name']?.toString() ?? 'Unknown User')
        : 'Loading...';
 
    // Neat identifiers: the payment reference (PAY-XXXX) and the worker's
    // friendly code (SHR######) instead of the raw Firestore UID.
    final paymentCode = data['paymentCode']?.toString() ?? '';
    final workerCode = userData != null
        ? (userData['systemWorkerId']?.toString() ?? userData['workerId']?.toString() ?? '')
        : '';
    final shortId = userId.length > 12
        ? '${userId.substring(0, 6)}…${userId.substring(userId.length - 4)}'
        : userId;
 
    final requestedAt = data['requestedAt'];
    final dateStr = (requestedAt is Timestamp)
        ? DateFormat('dd MMM yyyy, hh:mm a').format(requestedAt.toDate())
        : 'Unknown Date';
 
    final payMethod = data['paymentMethod']?.toString() ?? 'N/A';
    final payDetails = data['paymentDetails']?.toString() ?? 'No details provided';
    final statusColor = _getStatusColor(status);
 
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: avatar + name/ids + amount/status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_outline, size: 22, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(
                        paymentCode.isNotEmpty ? paymentCode : 'ID: $shortId',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                      ),
                      if (workerCode.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Employee: $workerCode', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹$amountStr', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
 
            const SizedBox(height: 16),
 
            // Details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _detailRow(Icons.account_balance_wallet, '$payMethod - $payDetails'),
                  const SizedBox(height: 8),
                  _detailRow(Icons.calendar_today, dateStr),
                ],
              ),
            ),
 
            if ((status == 'failed' || status == 'refunded') && data['error'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        status == 'refunded'
                            ? 'Payout rejected & refunded: ${data['error']}'
                            : 'Automated Payout Failed: ${data['error']}',
                        style: const TextStyle(color: AppColors.error, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
 
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isProcessing ? null : () => _processWithdrawal(doc, false),
                      style: _outlinedStyle(AppColors.error),
                      child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : () => _processWithdrawal(doc, true),
                      style: _filledStyle(AppColors.success),
                      child: isProcessing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Approve', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ],
            if (status == 'approved' || status == 'failed') ...[
              const SizedBox(height: 16),
              if (status == 'failed')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing ? null : () => _markAsPaid(doc),
                        icon: isProcessing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Mark Paid', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        style: _outlinedStyle(AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isProcessing ? null : () => _retryPayout(doc),
                        icon: isProcessing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry Payout', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        style: _filledStyle(AppColors.primary),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isProcessing ? null : () => _markAsPaid(doc),
                    icon: isProcessing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Mark Paid', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    style: _filledStyle(AppColors.primary),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
 