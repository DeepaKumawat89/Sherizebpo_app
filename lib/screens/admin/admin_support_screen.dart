import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminSupportScreen extends StatefulWidget {
  const AdminSupportScreen({Key? key}) : super(key: key);

  @override
  State<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends State<AdminSupportScreen> {
  final Set<String> _processingIds = {};
  Future<QuerySnapshot>? _ticketsFuture;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  void _loadTickets() {
    _ticketsFuture = _fetchTickets();
  }

  Future<QuerySnapshot> _fetchTickets() async {
    // Best-effort token refresh so a freshly-assigned support_admin role claim
    // reaches the Firestore rules. Bounded + guarded: on web getIdToken(true)
    // can hang, so we never let it block the query (falls back to cached token).
    try {
      await FirebaseAuth.instance.currentUser
          ?.getIdToken(true)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Ignore — proceed with the existing (cached) token.
    }
    return FirebaseFirestore.instance
        .collection('support_requests')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
  }

  Future<void> _updateTicketStatus(
      DocumentSnapshot doc, String newStatus) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    setState(() => _processingIds.add(id));
    try {
      await doc.reference.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      SnackBarUtils.showSuccess('Ticket marked as $newStatus');
      setState(() => _loadTickets()); // Refresh after action
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  /// Opens an attached screenshot full-screen with pinch-to-zoom.
  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.network(url)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Support Tickets'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _loadTickets()),
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _ticketsFuture,
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
                'No support tickets found.',
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
              final userName =
                  (data['name'] ?? data['userName'] ?? 'User').toString();
              final subject = data['subject']?.toString() ?? 'No Subject';
              final message = data['message']?.toString() ?? 'No Message';
              final status = data['status']?.toString() ?? 'pending';
              final isClient =
                  (data['source']?.toString() ?? '') == 'client_portal';
              final priority = data['priority']?.toString() ?? '';
              final email = data['email']?.toString() ?? '';
              final screenshotUrl = data['screenshotUrl']?.toString() ?? '';

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
                            child: Text(userName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: status == 'resolved'
                                  ? AppColors.successBg
                                  : AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: status == 'resolved'
                                    ? AppColors.success
                                    : AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isClient
                                      ? AppColors.info
                                      : AppColors.primary)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isClient ? 'CLIENT' : 'EMPLOYEE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: isClient
                                    ? AppColors.info
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                          if (priority.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('Priority: $priority',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(email,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ],
                      const SizedBox(height: AppSizes.sm),
                      Text('Subject: $subject',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: AppSizes.sm),
                      Text(message,
                          style: const TextStyle(
                              color: AppColors.textBody, fontSize: 14)),
                      if (screenshotUrl.isNotEmpty) ...[
                        const SizedBox(height: AppSizes.md),
                        const Text('Attachment',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted)),
                        const SizedBox(height: AppSizes.sm),
                        GestureDetector(
                          onTap: () => _openImage(screenshotUrl),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              screenshotUrl,
                              height: 140,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          height: 140,
                                          alignment: Alignment.center,
                                          color: AppColors.surfaceVariant,
                                          child:
                                              const CircularProgressIndicator(),
                                        ),
                              errorBuilder: (context, error, stack) => Container(
                                height: 140,
                                alignment: Alignment.center,
                                color: AppColors.surfaceVariant,
                                child: const Text('Could not load attachment',
                                    style:
                                        TextStyle(color: AppColors.textMuted)),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSizes.md),
                      const Divider(),
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isProcessing || status == 'in_progress'
                                  ? null
                                  : () =>
                                      _updateTicketStatus(doc, 'in_progress'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.warning),
                              child: const Text('In Progress'),
                            ),
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isProcessing || status == 'resolved'
                                  ? null
                                  : () => _updateTicketStatus(doc, 'resolved'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white),
                              child: isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          color: Colors.white))
                                  : const Text('Resolve'),
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
}
