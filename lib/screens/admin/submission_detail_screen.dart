import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/constants.dart';
import '../../widgets/custom_button.dart';
import '../../core/utils/snackbar_utils.dart';

/// Submission Detail Screen — Production-Ready with Full Null Safety.
///
/// Shows full submission details including:
///   - Worker name, task, customer phone
///   - Call result, notes, call duration
///   - Audio player for call recording
///   - Approve / Reject buttons
///   - Full null safety — never crashes on missing Firestore fields
class SubmissionDetailScreen extends StatefulWidget {
  final String submissionId;

  const SubmissionDetailScreen({Key? key, required this.submissionId})
      : super(key: key);

  @override
  State<SubmissionDetailScreen> createState() => _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState extends State<SubmissionDetailScreen> {
  bool _isProcessing = false;
  String? _processingAction;
  double _selectedRating = 0.0;

  // ═══════════════════════════════════════════════════════════════
  // SAFE PARSING HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Safely parse a value to int, returning [fallback] on failure.
  static int _safeInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Safely parse a value to double, returning [fallback] on failure.
  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Safely parse a value to String, returning [fallback] on failure.
  static String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  /// Persists the admin's star rating after the Cloud Function has settled.
  /// Touches ONLY non-money fields (user rating + submission rating), so it is
  /// safe to run from the client. Best-effort — never fails the review action.
  Future<void> _recordRating({
    required String userId,
    required double rating,
  }) async {
    if (userId.isEmpty) return;
    try {
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final userDoc = await userRef.get();
      final userData = userDoc.data() ?? {};
      final double currentRating = _safeDouble(userData['rating']);
      final int ratingCount = _safeInt(userData['ratingCount']);
      final int newCount = ratingCount + 1;
      final double newRating =
          ((currentRating * ratingCount) + rating) / newCount;

      final batch = FirebaseFirestore.instance.batch();
      if (userDoc.exists) {
        batch.update(userRef, {
          'rating': double.parse(newRating.toStringAsFixed(2)),
          'ratingCount': newCount,
        });
      }
      batch.update(
        FirebaseFirestore.instance
            .collection('task_submissions')
            .doc(widget.submissionId),
        {'rating': rating},
      );
      await batch.commit();
    } catch (e) {
      debugPrint('⚠️ Rating update skipped for ${widget.submissionId}: $e');
    }
  }

  Future<void> _qaReview(Map<String, dynamic> data, {required bool pass}) async {
    if (_isProcessing) return;
    String notes = '';
    bool reassign = true;
    if (!pass) {
      final result = await _askForReason();
      if (result == null) return;
      notes = (result['reason'] as String? ?? '').trim();
      if (notes.isEmpty) return;
      reassign = result['reassign'] as bool? ?? true;
    }
    setState(() {
      _isProcessing = true;
      _processingAction = pass ? 'qa_pass' : 'qa_fail';
    });
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('reviewSubmissionQA');
      await callable.call({
        'submissionId': widget.submissionId,
        'pass': pass,
        'notes': notes,
        'reassign': reassign,
      });
      if (mounted) {
        SnackBarUtils.showSuccess(pass
            ? 'Task approved.'
            : (reassign
            ? 'Rejected — lead scheduled for reassignment.'
                : 'Submission rejected.'));
        Navigator.pop(context, pass ? 'qa_passed' : 'rejected');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) SnackBarUtils.showError('QA review failed: ${e.message}');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('QA review failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingAction = null;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _askForReason() async {
    final controller = TextEditingController();
    bool reassign = true;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Reject submission'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. no real conversation / wrong script / silent call',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: reassign,
                onChanged: (v) => setLocal(() => reassign = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Return lead for reassignment',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Keep this lead in its original task',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, {
                'reason': controller.text.trim(),
                'reassign': reassign,
              }),
              child: Text(reassign ? 'Reject & Reassign' : 'Reject',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // APPROVE SUBMISSION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _approveSubmission(Map<String, dynamic> data) async {
    if (_isProcessing) return;
    if (_selectedRating == 0) {
      if (mounted) {
        SnackBarUtils.showError('Please select a rating (1-5 stars)');
      }
      return;
    }
    setState(() {
      _isProcessing = true;
      _processingAction = 'approve';
    });

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Money AND the worker's consolidated rating are handled server-side by
      // approveTaskSubmission (settleSubmission): atomic client-debit + escrow
      // release + budget cap + commission + rating average. The client must not
      // mutate any of those directly.
      final callable =
          FirebaseFunctions.instance.httpsCallable('approveTaskSubmission');
      await callable.call({
        'submissionId': widget.submissionId,
        'adminId': adminId,
        'rating': _selectedRating,
      });

      if (mounted) {
        SnackBarUtils.showSuccess('Task approved.');
        Navigator.pop(context, 'approved');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '❌ Approve error for ${widget.submissionId}: ${e.code} - ${e.message}');
      if (mounted) {
        SnackBarUtils.showError('Approval failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('❌ Approve error for ${widget.submissionId}: $e');
      if (mounted) {
        SnackBarUtils.showError('Approval failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingAction = null;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REJECT SUBMISSION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _rejectSubmission(Map<String, dynamic> data) async {
    if (_isProcessing) return;
    if (_selectedRating == 0) {
      if (mounted) {
        SnackBarUtils.showError('Please select a rating (1-5 stars)');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Submission?'),
        content: const Text(
            'This will reject the employee\'s submission. No earnings will be credited.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Reject', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _processingAction = 'reject';
    });

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userId = _safeString(data['userId']);

      // Rejection is handled server-side (atomic status + earnings_pending
      // cleanup). The client must not mutate money fields directly.
      final callable =
          FirebaseFunctions.instance.httpsCallable('rejectTaskSubmission');
      await callable.call({
        'submissionId': widget.submissionId,
        'adminId': adminId,
        'reason': 'Rejected manually by admin',
      });

      // Rating is a non-money field — safe to persist from the client.
      await _recordRating(userId: userId, rating: _selectedRating);

      if (mounted) {
        SnackBarUtils.showError('Submission rejected.');
        Navigator.pop(context, 'rejected');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '❌ Reject error for ${widget.submissionId}: ${e.code} - ${e.message}');
      if (mounted) {
        SnackBarUtils.showError('Rejection failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('❌ Reject error for ${widget.submissionId}: $e');
      if (mounted) {
        SnackBarUtils.showError('Rejection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingAction = null;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FORMAT HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTimestamp(dynamic ts) {
    final date = ts is Timestamp ? ts.toDate().toLocal()
        : ts is DateTime ? ts.toLocal() : null;
    return date == null ? 'Not recorded'
        : '${DateFormat('dd MMM yyyy, h:mm a').format(date)} ${date.timeZoneName}';
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}...';
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Submission Details'),
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          color: AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('task_submissions')
            .doc(widget.submissionId)
            .snapshots(),
        builder: (context, snapshot) {
          // ── Loading State ──
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          // ── Error State ──
          if (snapshot.hasError) {
            debugPrint('❌ StreamBuilder error (detail): ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.alertTriangle,
                        size: 40, color: AppColors.error),
                    const SizedBox(height: AppSizes.md),
                    const Text('Unable to load submission. Please try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.error, fontSize: 13)),
                    const SizedBox(height: AppSizes.md),
                    TextButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          // ── Document Not Found ──
          if (!snapshot.hasData ||
              snapshot.data == null ||
              !snapshot.data!.exists) {
            return const Center(
              child: Text('Submission not found.',
                  style: TextStyle(color: AppColors.textMuted)),
            );
          }

          // ── Safe Data Extraction ──
          final rawData = snapshot.data!.data();
          final data =
              (rawData is Map<String, dynamic>) ? rawData : <String, dynamic>{};

          if (data.isEmpty) {
            debugPrint(
                '⚠️ [SubmissionDetail] Empty data for ${widget.submissionId}');
            return const Center(
              child: Text('Submission data is empty.',
                  style: TextStyle(color: AppColors.textMuted)),
            );
          }

          // Log any missing fields for debugging
          final missingFields = <String>[];
          if (data['userId'] == null) missingFields.add('userId');
          if (data['taskId'] == null) missingFields.add('taskId');
          if (data['status'] == null) missingFields.add('status');
          if (missingFields.isNotEmpty) {
            debugPrint(
                '⚠️ [SubmissionDetail] ${widget.submissionId} missing: ${missingFields.join(', ')}');
          }

          // ── All fields use safe extraction ──
          final status = _safeString(data['status'], 'pending_admin_review');
          final isQA = status == 'pending_admin_review';
          final isPayment = status == 'pending_payment';
          final workerName =
              _safeString(data['workerName'] ?? data['leadName'], 'Employee');
          final taskId = _safeString(data['taskId']);
          final customerPhone =
              _safeString(data['customerPhone'] ?? data['leadPhone']);
          final result = _safeString(data['result'], 'Unknown');
          final notes = _safeString(data['notes']);
          final callDuration = _safeInt(data['callDuration']);
          final payout = _safeDouble(data['payout']);
          final recordingUrl = data['recordingUrl']?.toString();
          final callType = _safeString(data['callType'], 'manual');
          final submittedAt = data['submittedAt'];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.screenPaddingH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Status Badge ──
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'approved'
                        ? AppColors.successBg
                        : status == 'rejected'
                            ? AppColors.errorBg
                            : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Text(
                    status.toUpperCase().replaceAll('_', ' '),
                    style: TextStyle(
                      color: status == 'approved'
                          ? AppColors.success
                          : status == 'rejected'
                              ? AppColors.error
                              : AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.xl),

                // ── Worker & Task Info Card ──
                _buildInfoCard(
                  title: 'Employee & Task Information',
                  icon: LucideIcons.user,
                  children: [
                    _infoRow('Employee',
                        workerName.isNotEmpty ? workerName : 'Unknown'),
                    _infoRow('Task ID',
                        taskId.isNotEmpty ? _truncate(taskId, 24) : 'N/A'),
                    _infoRow('Customer',
                        customerPhone.isNotEmpty ? customerPhone : 'N/A'),
                    _infoRow('Submitted', _formatTimestamp(submittedAt)),
                    if (data['qaAt'] != null)
                      _infoRow('QA reviewed', _formatTimestamp(data['qaAt'])),
                    if (status == 'approved' || status == 'completed')
                      _infoRow('Approved', _formatTimestamp(
                          data['approvedAt'] ?? data['reviewedAt'] ?? data['qaAt'])),
                    if (status == 'rejected' || status == 'qa_failed')
                      _infoRow('Rejected', _formatTimestamp(
                          data['rejectedAt'] ?? data['reviewedAt'] ?? data['qaAt'])),
                  ],
                ),
                const SizedBox(height: AppSizes.md),

                // ── Call Details Card ──
                _buildInfoCard(
                  title: 'Call Details',
                  icon: LucideIcons.phoneCall,
                  children: [
                    _infoRow('Result', result),
                    _infoRow(
                        'Duration',
                        callDuration > 0
                            ? _formatDuration(callDuration)
                            : 'Duration unavailable'),
                    _infoRow('Call Type',
                        callType == 'voip' ? 'VOIP (Exotel)' : 'Manual'),
                    _infoRow('Payout', '₹${payout.toStringAsFixed(2)}'),
                  ],
                ),
                const SizedBox(height: AppSizes.md),

                // ── Notes Card ──
                _buildInfoCard(
                  title: 'Employee Notes',
                  icon: LucideIcons.fileText,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        notes.isNotEmpty ? '"$notes"' : 'No notes provided',
                        style: TextStyle(
                          color: notes.isNotEmpty
                              ? AppColors.textBody
                              : AppColors.textMuted,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),

                // ── Recording Player Card ──
                _buildInfoCard(
                  title: 'Call Recording',
                  icon: LucideIcons.mic,
                  children: [
                    if (recordingUrl != null &&
                        recordingUrl.trim().isNotEmpty &&
                        recordingUrl != 'null') ...[
                      const SizedBox(height: AppSizes.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                          border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.info,
                                borderRadius:
                                    BorderRadius.circular(AppSizes.radiusSm),
                              ),
                              child: const Icon(LucideIcons.play,
                                  color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: AppSizes.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Recording Available',
                                    style: TextStyle(
                                      color: AppColors.info,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    callDuration > 0
                                        ? 'Duration: ${_formatDuration(callDuration)}'
                                        : 'Duration unavailable',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  var validUrl = recordingUrl.trim();
                                  if (!validUrl.startsWith('http')) {
                                    validUrl = 'https://$validUrl';
                                  }
                                  final url = Uri.parse(validUrl);
                                  await launchUrl(url,
                                      mode: LaunchMode.externalApplication);
                                } catch (e) {
                                  debugPrint(
                                      '❌ Failed to launch recording: $e');
                                  if (context.mounted) {
                                    SnackBarUtils.showError('Could not open: $e');
                                  }
                                }
                              },
                              icon: const Icon(LucideIcons.externalLink,
                                  size: 16),
                              label: const Text('Play'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.info,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppSizes.radiusSm),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.micOff,
                                color: AppColors.textMuted, size: 20),
                            SizedBox(width: AppSizes.sm),
                            Text(
                              'No recording available for this call.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSizes.xxl),

                // ── Action Buttons ──
                if (isPayment) ...[
                  _buildRatingSelector(),
                  const SizedBox(height: AppSizes.xl),
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          label: 'Approve',
                          icon: LucideIcons.checkCircle,
                          isLoading:
                              _isProcessing && _processingAction == 'approve',
                          isDisabled: _isProcessing,
                          onPressed: _isProcessing
                              ? null
                              : () => _approveSubmission(data),
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: CustomButton(
                          label: 'Reject',
                          icon: LucideIcons.xCircle,
                          variant: CustomButtonVariant.outlined,
                          isLoading:
                              _isProcessing && _processingAction == 'reject',
                          isDisabled: _isProcessing,
                          onPressed: _isProcessing
                              ? null
                              : () => _rejectSubmission(data),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xxl),
                ] else if (isQA) ...[
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          label: 'Approve',
                          icon: LucideIcons.arrowRight,
                          isLoading:
                              _isProcessing && _processingAction == 'qa_pass',
                          isDisabled: _isProcessing,
                          onPressed: _isProcessing
                              ? null
                              : () => _qaReview(data, pass: true),
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: CustomButton(
                          label: 'Fail QA',
                          icon: LucideIcons.xCircle,
                          variant: CustomButtonVariant.outlined,
                          isLoading:
                              _isProcessing && _processingAction == 'qa_fail',
                          isDisabled: _isProcessing,
                          onPressed: _isProcessing
                              ? null
                              : () => _qaReview(data, pass: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.xxl),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textMuted),
              const SizedBox(width: AppSizes.sm),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Review Rating (Required)',
            style: TextStyle(
                color: AppColors.textDark,
                fontSize: 15,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRating = starIndex.toDouble();
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(
                    starIndex <= _selectedRating
                        ? Icons.star
                        : Icons.star_border,
                    size: 40,
                    color: starIndex <= _selectedRating
                        ? AppColors.accent
                        : AppColors.textMuted,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
