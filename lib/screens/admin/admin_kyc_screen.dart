import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminKycScreen extends StatefulWidget {
  const AdminKycScreen({Key? key}) : super(key: key);

  @override
  State<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends State<AdminKycScreen> {
  final Set<String> _processingIds = {};

  Future<void> _updateKycStatus(DocumentSnapshot doc, String newStatus) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${newStatus == 'approved' ? 'Approve' : 'Reject'} KYC?'),
        content:
            Text('Are you sure you want to $newStatus this KYC submission?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              newStatus == 'approved' ? 'Approve' : 'Reject',
              style: TextStyle(
                color: newStatus == 'approved'
                    ? AppColors.success
                    : AppColors.error,
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
        'kycStatus': newStatus,
        'kycReviewedAt': FieldValue.serverTimestamp(),
        'kycReviewedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (!mounted) return;
      if (newStatus == 'approved') {
        SnackBarUtils.showSuccess('KYC approved successfully.');
      } else {
        SnackBarUtils.showInfo('KYC rejected.');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Error: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      var validUrl = url.trim();
      if (!validUrl.startsWith('http')) {
        validUrl = 'https://$validUrl';
      }
      final uri = Uri.tryParse(validUrl);
      if (uri == null) {
        if (!mounted) return;
        SnackBarUtils.showError('Invalid URL');
        return;
      }

      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Launch URL error: $e');
      if (!mounted) return;
      SnackBarUtils.showError('Could not launch document: $e');
    }
  }

  String? _safeUrl(dynamic raw) {
    final s = raw?.toString();
    return (s != null && s.trim().isNotEmpty) ? s.trim() : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review KYC Submissions'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('kycStatus', isEqualTo: 'pending')
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          // ── Error state ──
          if (snapshot.hasError) {
            debugPrint('KYC Stream Error: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Error loading KYC submissions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Loading state ──
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Loading KYC submissions...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          debugPrint('KYC Docs fetched: ${docs.length}');

          // ── Empty state ──
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.verified_user,
                        size: 36, color: AppColors.success),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All Clear!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No pending KYC submissions.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          // ── List ──
          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.md),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              // Cast safely
              final rawData = doc.data();
              if (rawData == null) return const SizedBox.shrink();
              final data = rawData as Map<String, dynamic>;

              final isProcessing = _processingIds.contains(doc.id);
              final userName = _safeUrl(data['fullName']?.toString()) ??
                  _safeUrl(data['name']?.toString()) ??
                  'Employee';
              final phone = _safeUrl(data['phone']) ?? 'No Phone';
              final profileImage = _safeUrl(data['profileImageUrl']) ??
                  _safeUrl(data['profileImage']) ??
                  _safeUrl(data['profilePicUrl']);
              final aadharUrl = _safeUrl(data['aadharUrl']) ??
                  _safeUrl(data['aadhaarUrl']) ??
                  _safeUrl(data['aadhaar_url']);
              final panUrl =
                  _safeUrl(data['panUrl']) ?? _safeUrl(data['pan_url']);

              return _KycCard(
                key: ValueKey(doc.id),
                userName: userName,
                phone: phone,
                profileImage: profileImage,
                aadharUrl: aadharUrl,
                panUrl: panUrl,
                isProcessing: isProcessing,
                onApprove: () => _updateKycStatus(doc, 'approved'),
                onReject: () => _updateKycStatus(doc, 'rejected'),
                onLaunchUrl: _launchUrl,
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Extracted stateless card — avoids AnimatedListItem/SlideTransition
// which causes `size: MISSING` on Flutter Web.
// ─────────────────────────────────────────────────────────────
class _KycCard extends StatelessWidget {
  final String userName;
  final String phone;
  final String? profileImage;
  final String? aadharUrl;
  final String? panUrl;
  final bool isProcessing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final Future<void> Function(String) onLaunchUrl;

  const _KycCard({
    Key? key,
    required this.userName,
    required this.phone,
    this.profileImage,
    this.aadharUrl,
    this.panUrl,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onLaunchUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header: Avatar + Name + Phone ──
            Row(
              children: [
                _Avatar(imageUrl: profileImage),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Document Buttons ──
            if (aadharUrl != null || panUrl != null) ...[
              const SizedBox(height: AppSizes.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (aadharUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => onLaunchUrl(aadharUrl!),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: const Text('View Aadhaar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  if (panUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => onLaunchUrl(panUrl!),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: const Text('View PAN'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: AppSizes.md),
            const Divider(),
            const SizedBox(height: AppSizes.sm),

            // ── Action Buttons ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : onReject,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error)),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : onApprove,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white),
                    child: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Safe network avatar with errorBuilder
// ─────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String? imageUrl;
  const _Avatar({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: imageUrl != null
            ? ClipOval(
                child: Image.network(
                  imageUrl!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(LucideIcons.user, color: AppColors.primary),
                  loadingBuilder: (_, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Icon(LucideIcons.user,
                        color: AppColors.primary);
                  },
                ),
              )
            : const Icon(LucideIcons.user, color: AppColors.primary),
      ),
    );
  }
}
