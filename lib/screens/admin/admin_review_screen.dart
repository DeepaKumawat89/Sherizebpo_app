// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/animated_list_item.dart';

/// Admin Task Review Screen — Production-Ready with Full Null Safety + Stunning Animations.
///
/// Features:
///   ✓ Real-time StreamBuilder with Firestore
///   ✓ Tabs: Pending / Approved / Rejected
///   ✓ Search by phone, employee name, or employee ID
///   ✓ Filter by result, sort by date
///   ✓ Complete review queue with lazy card rendering
///   ✓ Approve / Reject with batch transactions
///   ✓ Duplicate approval prevention
///   ✓ Loading states & error handling
///   ✓ Full null safety — never crashes on missing Firestore fields
///   ✓ Data validation & debug logging
///   ✓ View Details → SubmissionDetailScreen
///   ✓ flutter_animate stagger list animations
///   ✓ Shimmer skeleton loading cards
///   ✓ Glassmorphism AppBar with animated stats
///   ✓ Animated approve/reject feedback
class AdminReviewScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  const AdminReviewScreen({Key? key, this.firestore, this.auth}) : super(key: key);

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _processingIds = {};
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _submissionStreams = {};
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _employeeProfiles = {};
  final Map<String, String?> _selectedDates = {};
  bool _oldestFirst = false;

  // ── Two-stage review role gating ──
  static const List<String> _reviewRoles = ['admin', 'super_admin', 'task_review_admin', 'kyc_admin'];
  static const List<String> _paymentRoles = ['admin', 'super_admin', 'kyc_admin'];
  String? _myRole;
  bool get _canQA => _myRole != null && _reviewRoles.contains(_myRole);
  bool get _canPay => _myRole != null && _paymentRoles.contains(_myRole);

  // ── Filters ──
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _resultFilter; // null = all
  final List<String> _resultOptions = [
    'All',
    'Interested',
    'Not Interested',
    'No Answer',
    'Callback',
    'Wrong Number',
  ];

  ErrorWidgetBuilder? _originalErrorWidgetBuilder;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _fetchMyRole();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });

    _originalErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint('🔥 [AdminReview] ErrorWidget caught: ${details.exception}');
      return Container(
        padding: const EdgeInsets.all(AppSizes.xl),
        color: AppColors.errorBg,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle,
                  color: AppColors.error, size: 40),
              const SizedBox(height: 10),
              Text(
                'Layout/Render Error:\n${details.exception}',
                style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Stack:\n${details.stack}',
                style: const TextStyle(color: AppColors.error, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    };
  }

  @override
  void dispose() {
    if (_originalErrorWidgetBuilder != null) {
      ErrorWidget.builder = _originalErrorWidgetBuilder!;
    }
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // SAFE PARSING HELPERS
  // ═══════════════════════════════════════════════════════════════

  static int _safeInt(dynamic value, [int fallback = 0]) {
    if (value == null) {
      return fallback;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.toInt();
    }
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }

  // A friendly worker code looks like "SHR123456" (or contains a dash). A raw
  // Firebase UID never does — this lets us avoid ever showing the raw UID.
  static bool _looksFriendly(String v) {
    final s = v.trim().toUpperCase();
    return s.isNotEmpty && (s.startsWith('SHR') || s.contains('-'));
  }

  // Format a Firestore Timestamp/DateTime as e.g. "9 Jul 2026, 2:14 PM".
  static String _formatDateTime(dynamic ts) {
    if (ts == null) return 'Not recorded';
    DateTime d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else if (ts is DateTime) {
      d = ts;
    } else {
      return 'Not recorded';
    }
    final local = d.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$min $ampm ${local.timeZoneName}';
  }

  Future<DateTime?> _pickFutureDateTime(
      BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 364)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (selected.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      SnackBarUtils.showInfo('Choose a return time at least 1 minute from now.');
      return null;
    }
    if (selected.isAfter(DateTime.now().add(const Duration(days: 365)))) {
      SnackBarUtils.showInfo('Choose a return time within 365 days.');
      return null;
    }
    return selected;
  }

  // ═══ TWO-STAGE REVIEW — role fetch + QA (stage 1) actions ═══
  Future<void> _fetchMyRole() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      final snap =
          await _firestore.collection('users').doc(uid).get();
      if (mounted) {
        setState(() => _myRole = _safeString(snap.data()?['role']).toLowerCase());
      }
    } catch (e) {
      debugPrint('[AdminReview] role fetch failed: $e');
    }
  }

  Future<Map<String, dynamic>?> _askForReason(BuildContext context) async {
    final controller = TextEditingController();
    bool reassign = true;
    DateTime? requeueAt;
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
              if (reassign)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final selected =
                          await _pickFutureDateTime(ctx, requeueAt);
                      if (selected != null) {
                        setLocal(() => requeueAt = selected);
                      }
                    },
                    icon: const Icon(LucideIcons.calendarClock, size: 18),
                    label: Text(requeueAt == null
                      ? 'Set retry time'
                        : _formatDateTime(requeueAt)),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: reassign && requeueAt == null
                  ? null
                  : () => Navigator.pop(ctx, {
                        'reason': controller.text.trim(),
                        'reassign': reassign,
                        if (requeueAt != null) 'requeueAt': requeueAt,
                      }),
              child: Text(reassign ? 'Reject & Reassign' : 'Reject',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  // Stage 1: forward to payment (pass) or reject the recording (fail).
  // NO money moves here — that happens at payment approval.
  Future<void> _qaReview(DocumentSnapshot doc, {required bool pass}) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    String notes = '';
    bool reassign = true;
    DateTime? requeueAt;
    double? rating;
    if (pass) {
      // Task Reviewer rates the worker's completed call (1–5) before approving.
      // The rating is consolidated into the worker's profile server-side.
      rating = await _askForRating(context, isApprove: true);
      if (rating == null) return; // reviewer cancelled
    } else {
      final result = await _askForReason(context);
      if (result == null) return;
      notes = (result['reason'] as String? ?? '').trim();
      if (notes.isEmpty) return;
      reassign = result['reassign'] as bool? ?? true;
      requeueAt = result['requeueAt'] as DateTime?;
    }

    setState(() => _processingIds.add(id));
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('reviewSubmissionQA');
      await callable.call({
        'submissionId': id,
        'pass': pass,
        'notes': notes,
        'reassign': reassign,
        if (requeueAt != null)
          'requeueAt': requeueAt.millisecondsSinceEpoch,
        if (rating != null) 'rating': rating,
      });
      if (mounted) {
        if (pass) {
          SnackBarUtils.showSuccess('Task approved.');
        } else {
          SnackBarUtils.showInfo(reassign
              ? 'Rejected — lead scheduled for reassignment.'
              : 'Submission rejected.');
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) SnackBarUtils.showError('QA review failed: ${e.message}');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('QA review failed: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  Widget _buildQAActionButtons(DocumentSnapshot doc, bool isProcessing) {
    return Row(
      children: [
        Expanded(
          child: TapScaleWidget(
            onTap: isProcessing ? null : () => _qaReview(doc, pass: false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error),
                borderRadius: BorderRadius.circular(10),
                color: isProcessing ? AppColors.errorBg : Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.x,
                      size: 16,
                      color:
                          isProcessing ? AppColors.textMuted : AppColors.error),
                  const SizedBox(width: 6),
                    Flexible(child: Text('Fail QA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isProcessing
                            ? AppColors.textMuted
                            : AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: TapScaleWidget(
            onTap: isProcessing ? null : () => _qaReview(doc, pass: true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: isProcessing
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.primary, Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isProcessing ? AppColors.primarySoft : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isProcessing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    )
                  else ...[
                    const Icon(LucideIcons.arrowRight,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    const Flexible(child: Text('Approve',
                      textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // APPROVE SUBMISSION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _approveSubmission(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final rating = await _askForRating(context, isApprove: true);
    if (rating == null) return;

    setState(() => _processingIds.add(id));

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';

      final callable =
          FirebaseFunctions.instance.httpsCallable('approveTaskSubmission');
      await callable.call({
        'submissionId': id,
        'adminId': adminId,
        'rating': rating,
      });

      // Rating consolidation into the worker profile is done server-side by
      // approveTaskSubmission (settleSubmission), so the average and count stay
      // atomic and can't double-count.

      if (mounted) _showFeedbackSnackBar(isApprove: true);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Approve error for submission $id: ${e.code} - ${e.message}');
      if (mounted) SnackBarUtils.showError('Approval failed: ${e.message}');
    } catch (e) {
      debugPrint('❌ Approve error for submission $id: $e');
      if (mounted) SnackBarUtils.showError('Approval failed: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REJECT SUBMISSION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _rejectSubmission(DocumentSnapshot doc) async {
    final id = doc.id;
    if (_processingIds.contains(id)) return;

    final rating = await _askForRating(context, isApprove: false);
    if (rating == null) return;

    setState(() => _processingIds.add(id));

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? '';

      final callable =
          FirebaseFunctions.instance.httpsCallable('rejectTaskSubmission');
      await callable.call({
        'submissionId': id,
        'adminId': adminId,
        'reason': 'Rejected manually by admin',
      });

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final userId = _safeString(data['userId']);
      if (userId.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data() ?? {};
          double currentRating = _safeDouble(userData['rating']);
          int tasksCompleted = _safeInt(userData['totalTasksCompleted'] ??
              userData['tasks_completed'] ??
              userData['completedTasks']);
          int newTasksCompleted = tasksCompleted + 1;
          double newRating =
              ((currentRating * tasksCompleted) + rating) / newTasksCompleted;

          final batch = FirebaseFirestore.instance.batch();
          batch.update(userDoc.reference, {
            'rating': newRating,
            'totalTasksCompleted': newTasksCompleted,
          });
          batch.update(doc.reference, {'rating': rating});
          await batch.commit();
        }
      }

      if (mounted) _showFeedbackSnackBar(isApprove: false);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Reject error for submission $id: ${e.code} - ${e.message}');
      if (mounted) SnackBarUtils.showError('Rejection failed: ${e.message}');
    } catch (e) {
      debugPrint('❌ Reject error for submission $id: $e');
      if (mounted) SnackBarUtils.showError('Rejection failed: $e');
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SNACKBAR HELPERS — Animated Premium Style
  // ═══════════════════════════════════════════════════════════════
  void _showFeedbackSnackBar({required bool isApprove}) {
    if (isApprove) {
      SnackBarUtils.showSuccess('Task approved.');
    } else {
      SnackBarUtils.showInfo('Submission rejected.');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Task Submissions')
            .animate()
            .fadeIn(duration: 500.ms)
            .slideX(begin: -0.15, end: 0),
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
        actions: [
          // Animated pending count badge
          _PendingCountBadge(firestore: _firestore)
              .animate()
              .fadeIn(delay: 300.ms, duration: 400.ms)
              .scale(begin: const Offset(0.7, 0.7)),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(150),
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Search Bar ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.screenPaddingH),
                  child: _AnimatedSearchBar(
                    controller: _searchController,
                    searchQuery: _searchQuery,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 100.ms, duration: 400.ms)
                    .slideY(begin: -0.2, end: 0),
                const SizedBox(height: AppSizes.sm),
                // ── Result Filter Chips ──
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.screenPaddingH),
                    children: _resultOptions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final opt = entry.value;
                      final isSelected = opt == 'All'
                          ? _resultFilter == null
                          : _resultFilter == opt;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _AnimatedFilterChip(
                          label: opt,
                          isSelected: isSelected,
                          onSelected: () {
                            setState(() {
                              _resultFilter = opt == 'All' ? null : opt;
                            });
                          },
                        ),
                      )
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: 150 + i * 40),
                            duration: 300.ms,
                          )
                          .slideX(begin: 0.2, end: 0);
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 6),
                // ── Tab Bar ──
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(text: 'QA Review'),
                    Tab(text: 'Approved'),
                    Tab(text: 'Rejected'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSubmissionsList('pending_admin_review'),
          _buildSubmissionsList('approved'),
          _buildSubmissionsList('rejected'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SUBMISSIONS LIST WITH SKELETON LOADING
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSubmissionsList(String statusFilter) {
    // ponytail: Load the full status queue for complete local search; very large
    // histories should move to indexed server-side search/date pagination.
    final stream = _submissionStreams.putIfAbsent(statusFilter, () => _firestore
        .collection('task_submissions')
        .where('status', isEqualTo: statusFilter)
        .snapshots());

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        // ── Skeleton Loading State ──
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonList();
        }

        if (snapshot.hasError) {
          return _buildErrorState('${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];
        if (_searchQuery.isEmpty) {
          return _buildFilteredSubmissions(docs, statusFilter, const {});
        }
        final userIds = docs.map((doc) => _safeString(doc.data()['userId']))
            .where((id) => id.isNotEmpty).toSet();
        return FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>?>>(
          future: Future.wait(userIds.map((id) async {
            try {
              return await _employeeProfile(id);
            } on FirebaseException {
              return null;
            }
          })),
          builder: (context, profiles) {
            if (profiles.connectionState == ConnectionState.waiting) {
              return _buildSkeletonList();
            }
            if (profiles.hasError) {
              return _buildErrorState('${profiles.error}');
            }
            return _buildFilteredSubmissions(docs, statusFilter, {
              for (final profile in profiles.data ?? [])
                if (profile != null) profile.id: profile.data() ?? {},
            });
          },
        );
      },
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _employeeProfile(String userId) =>
      _employeeProfiles.putIfAbsent(userId, () => _firestore.collection('users').doc(userId).get());

  static DateTime? _submittedDate(Map<String, dynamic> data) {
    final value = data['submittedAt'];
    return value is Timestamp ? value.toDate().toLocal()
        : value is DateTime ? value.toLocal() : null;
  }

  static String _dateKey(Map<String, dynamic> data) {
    final date = _submittedDate(data);
    return date == null ? 'undated' : DateFormat('yyyy-MM-dd').format(date);
  }

  static String _dateLabel(String key) => key == 'undated'
      ? 'Undated' : DateFormat('dd MMM yyyy').format(DateTime.parse(key));

  Widget _buildFilteredSubmissions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> submissions,
      String statusFilter,
      Map<String, Map<String, dynamic>> profiles) {
        final docs = [...submissions];
        docs.sort((first, second) {
          final firstDate = _submittedDate(first.data());
          final secondDate = _submittedDate(second.data());
          if (firstDate == null && secondDate != null) return 1;
          if (secondDate == null && firstDate != null) return -1;
          final dateOrder = firstDate == null || secondDate == null ? 0
              : _oldestFirst ? firstDate.compareTo(secondDate) : secondDate.compareTo(firstDate);
          return dateOrder != 0 ? dateOrder : first.id.compareTo(second.id);
        });

        final matchingDocs = docs.where((doc) {
          final data = doc.data();
          final workerName = _safeString(data['workerName']).toLowerCase();
          final customerPhone = _safeString(
              data['leadPhone'], _safeString(data['customerPhone']));

          final rawOutcome =
              _safeString(data['outcome'], _safeString(data['result']));
          String formattedOutcome = rawOutcome;
          if (rawOutcome == 'interested') {
            formattedOutcome = 'Interested';
          } else if (rawOutcome == 'not_interested') formattedOutcome = 'Not Interested';
          else if (rawOutcome == 'callback') formattedOutcome = 'Callback';
          else if (rawOutcome == 'no_answer') formattedOutcome = 'No Answer';
          else if (rawOutcome == 'wrong_number') formattedOutcome = 'Wrong Number';
          else if (rawOutcome.isEmpty) formattedOutcome = 'No Result';

          if (_searchQuery.isNotEmpty) {
            final profile = profiles[_safeString(data['userId'])] ?? const {};
            final employeeIds = ['employeeId', 'systemWorkerId', 'workerId']
                .expand((field) => [data[field], profile[field]])
                .map((value) => _safeString(value).trim().toLowerCase());
            final profileName = _safeString(profile['name'], _safeString(profile['fullName'])).toLowerCase();
            if (!workerName.contains(_searchQuery) &&
                !profileName.contains(_searchQuery) &&
                !customerPhone.contains(_searchQuery) &&
                !employeeIds.any((id) => id.contains(_searchQuery))) {
              return false;
            }
          }
          if (_resultFilter != null && _resultFilter != 'All') {
            if (formattedOutcome != _resultFilter) return false;
          }
          return true;
        }).toList();

        final dateCounts = <String, int>{};
        for (final doc in matchingDocs) {
          final key = _dateKey(doc.data());
          dateCounts[key] = (dateCounts[key] ?? 0) + 1;
        }
        final selectedDate = _selectedDates[statusFilter];
        if (selectedDate != null) dateCounts.putIfAbsent(selectedDate, () => 0);
        final dates = dateCounts.keys.toList()..sort((first, second) {
          if (first == second) return 0;
          if (first == 'undated') return 1;
          if (second == 'undated') return -1;
          return second.compareTo(first);
        });
        final filteredDocs = matchingDocs.where((doc) =>
            selectedDate == null || _dateKey(doc.data()) == selectedDate).toList();
        final hasFilters = _searchQuery.isNotEmpty || _resultFilter != null || selectedDate != null;

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.screenPaddingH, 8, AppSizes.screenPaddingH, 0),
            child: Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                key: ValueKey('$statusFilter:$selectedDate'),
                initialValue: selectedDate ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Submission date',
                  prefixIcon: Icon(LucideIcons.calendar, size: 18),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text('All dates (${matchingDocs.length})')),
                  for (final date in dates)
                    DropdownMenuItem(value: date, child: Text('${_dateLabel(date)} (${dateCounts[date]})', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _selectedDates[statusFilter] = value == 'all' ? null : value),
              )),
              IconButton(
                tooltip: _oldestFirst ? 'Oldest first' : 'Newest first',
                icon: Icon(_oldestFirst ? LucideIcons.arrowUp : LucideIcons.arrowDown),
                onPressed: () => setState(() => _oldestFirst = !_oldestFirst),
              ),
              if (hasFilters) IconButton(
                tooltip: 'Clear filters',
                icon: const Icon(LucideIcons.filterX),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _resultFilter = null;
                  _selectedDates[statusFilter] = null;
                }),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH, vertical: 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('${filteredDocs.length} of ${docs.length} submissions',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
          ),
          Expanded(child: filteredDocs.isEmpty
              ? _buildEmptyState(statusFilter, hasFilters: hasFilters)
              : ListView.builder(
          key: PageStorageKey('$statusFilter:$selectedDate:$_searchQuery:$_resultFilter:$_oldestFirst'),
          padding: const EdgeInsets.only(
            top: AppSizes.md,
            bottom: 100,
            left: AppSizes.screenPaddingH,
            right: AppSizes.screenPaddingH,
          ),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final doc = filteredDocs[index];
            final stage = statusFilter == 'pending_admin_review'
                ? 'qa'
                : statusFilter == 'pending_payment'
                    ? 'payment'
                    : 'done';
            final dateKey = _dateKey(doc.data());
            final startsDay = index == 0 || _dateKey(filteredDocs[index - 1].data()) != dateKey;
            return Column(
              key: ValueKey(doc.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsDay) Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_dateLabel(dateKey), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _buildReviewCard(doc, stage, index),
              ],
            );
          },
        )),
        ]);
  }

  // ═══════════════════════════════════════════════════════════════
  // SKELETON LOADING — 5 placeholder cards
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppSizes.md,
        bottom: 100,
        left: AppSizes.screenPaddingH,
        right: AppSizes.screenPaddingH,
      ),
      itemCount: 5,
      itemBuilder: (_, i) => _SkeletonReviewCard()
          .animate(delay: Duration(milliseconds: i * 80))
          .fadeIn(duration: 400.ms),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EMPTY STATE — Animated
  // ═══════════════════════════════════════════════════════════════
  Widget _buildEmptyState(String statusFilter, {bool hasFilters = false}) {
    final isPending = statusFilter == 'pending_admin_review';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(LucideIcons.inbox,
                size: 36, color: AppColors.primary),
          )
              .animate()
              .scale(
                begin: const Offset(0.5, 0.5),
                duration: 500.ms,
                curve: Curves.elasticOut,
              )
              .fadeIn(),
          const SizedBox(height: 16),
          Text(
            hasFilters ? 'No matching submissions' : isPending ? 'All caught up! 🎉' : 'Nothing here yet.',
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          )
              .animate(delay: 200.ms)
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.3, end: 0),
          const SizedBox(height: 8),
          Text(
            hasFilters ? 'No submissions match the selected filters.' : isPending
                ? 'No pending submissions to review.'
                : 'No submissions in this category.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
          )
              .animate(delay: 300.ms)
              .fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ERROR STATE
  // ═══════════════════════════════════════════════════════════════
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertTriangle,
                color: AppColors.error, size: 40)
                .animate()
                .shake(duration: 600.ms),
            const SizedBox(height: 12),
            Text('Error: $error',
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // REVIEW CARD — ANIMATED + FULLY NULL-SAFE
  // ═══════════════════════════════════════════════════════════════
  Widget _buildReviewCard(DocumentSnapshot doc, String stage, int index) {
    if (!doc.exists) return const SizedBox.shrink();

    final isPending = stage != 'done';

    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final id = doc.id;
    final status = _safeString(data['status']);
    final workerName = _safeString(data['workerName'], 'Unknown Employee');
    final userId = _safeString(data['userId'], 'Unknown Employee ID');
    // Use the denormalized friendly code if the employee profile is unavailable.
    final workerCode = ['employeeId', 'systemWorkerId', 'workerId']
      .map((field) => _safeString(data[field]))
      .firstWhere(_looksFriendly, orElse: () => '');
    
    final customerPhone = _safeString(data['customerPhone'], _safeString(data['leadPhone'], 'No Phone'));
    String maskedPhone = 'No Phone';
    if (customerPhone != 'No Phone') {
      if (customerPhone.length > 3) {
        maskedPhone = ('*' * (customerPhone.length - 3)) + customerPhone.substring(customerPhone.length - 3);
      } else {
        maskedPhone = '*' * customerPhone.length;
      }
    }

    final rawOutcome = _safeString(data['outcome'], _safeString(data['result'], 'No Result'));
    String formattedOutcome = rawOutcome;
    if (rawOutcome == 'interested') {
      formattedOutcome = 'Interested';
    } else if (rawOutcome == 'not_interested') formattedOutcome = 'Not Interested';
    else if (rawOutcome == 'callback') formattedOutcome = 'Callback';
    else if (rawOutcome == 'no_answer') formattedOutcome = 'No Answer';
    else if (rawOutcome == 'wrong_number') formattedOutcome = 'Wrong Number';
    else if (rawOutcome == 'busy') formattedOutcome = 'Busy';

    final callDuration = _safeInt(data['callDuration']);
    final recordingUrl = _safeString(data['recordingUrl']);
    final notes = _safeString(data['notes']);

    final isProcessing = _processingIds.contains(id);

    return _AnimatedReviewCard(
      index: index,
      child: FutureBuilder<DocumentSnapshot>(
        future: _employeeProfile(userId),
        builder: (context, userSnapshot) {
          String displayWorkerName = workerName;
          // Only ever show a friendly worker code — never the raw Firebase UID.
          String friendlyId = _looksFriendly(workerCode) ? workerCode : '';

          if (userSnapshot.hasData && userSnapshot.data?.exists == true) {
            final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
            final sysId = ['employeeId', 'systemWorkerId', 'workerId']
              .map((field) => _safeString(userData[field]))
              .firstWhere(_looksFriendly, orElse: () => '');
            if (_looksFriendly(sysId)) friendlyId = sysId;
            final name = _safeString(userData['name'], _safeString(userData['fullName']));
            if (name.isNotEmpty) displayWorkerName = name;
          }

          // Guarantee the header never falls back to the raw UID.
          if (displayWorkerName.isEmpty || displayWorkerName == 'Unknown Employee' || displayWorkerName == 'Unknown Worker') {
            displayWorkerName = friendlyId.isNotEmpty ? friendlyId : 'Employee';
          }
          final workerIdLabel = friendlyId.isNotEmpty ? friendlyId : 'Not assigned';

          // Lead with the worker ID; never surface the email as the identifier.
          final looksEmail = displayWorkerName.contains('@');
          final headerTitle = friendlyId.isNotEmpty
              ? friendlyId
              : (looksEmail ? 'Employee' : displayWorkerName);
          final headerSubtitle = (friendlyId.isNotEmpty && !looksEmail &&
                  displayWorkerName != friendlyId)
              ? displayWorkerName
              : '';

          return Container(
            margin: const EdgeInsets.only(bottom: AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              boxShadow: AppDecorations.shadowSm,
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Card Header ──
                  _buildCardHeader(headerTitle, headerSubtitle, formattedOutcome, rawOutcome, isPending),

                  // ── Card Body ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSizes.lg, 0, AppSizes.lg, AppSizes.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSizes.md),
                        _cardInfoRow(LucideIcons.user, 'Employee ID', workerIdLabel),
                        _cardInfoRow(LucideIcons.phone, 'Customer', maskedPhone),
                        _cardInfoRow(
                            LucideIcons.clock, 'Duration', _formatDuration(callDuration)),
                        _cardInfoRow(LucideIcons.calendar, 'Submitted',
                            _formatDateTime(data['submittedAt'])),
                        if (status == 'approved')
                          _cardInfoRow(LucideIcons.checkCircle, 'Approved',
                              _formatDateTime(data['approvedAt'] ?? data['reviewedAt'] ?? data['qaAt'])),
                        if (status == 'rejected')
                          _cardInfoRow(LucideIcons.xCircle, 'Rejected',
                              _formatDateTime(data['rejectedAt'] ?? data['reviewedAt'] ?? data['qaAt'])),
                        if (status == 'rejected' &&
                            data['reassigned'] == true &&
                            data['requeueAfter'] != null)
                          RequeueScheduleRow(
                            key: ValueKey('retry-$id'),
                            leadId: _safeString(data['leadId']),
                            taskId: _safeString(data['taskId']),
                              requeueAfter: data['requeueAfter']),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(LucideIcons.fileText,
                                  size: 14, color: AppColors.textLight),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notes: $notes',
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.textBody),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (recordingUrl.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.sm),
                          _AudioPlayerWidget(url: recordingUrl),
                        ],
                        if (stage == 'qa' && _canQA) ...[
                          const SizedBox(height: AppSizes.md),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: AppSizes.sm),
                          _buildQAActionButtons(doc, isProcessing),
                        ] else if (stage == 'payment' && _canPay) ...[
                          const SizedBox(height: AppSizes.md),
                          const Divider(color: AppColors.border),
                          const SizedBox(height: AppSizes.sm),
                          _buildActionButtons(doc, isProcessing),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildCardHeader(String title, String subtitle, String formattedOutcome, String rawOutcome, bool isPending) {
    final outcomeColor = _outcomeColor(rawOutcome);
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surface,
            outcomeColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    title.isNotEmpty ? title[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textDark),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: AppColors.textLight),
                    ),
                ],
              ),
            ],
          ),
          // Outcome badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: outcomeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: outcomeColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: outcomeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  formattedOutcome,
                  style: TextStyle(
                      color: outcomeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(DocumentSnapshot doc, bool isProcessing) {
    return Row(
      children: [
        Expanded(
          child: TapScaleWidget(
            onTap: isProcessing ? null : () => _rejectSubmission(doc),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error),
                borderRadius: BorderRadius.circular(10),
                color: isProcessing
                    ? AppColors.errorBg
                    : Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.x,
                      size: 16,
                      color: isProcessing
                          ? AppColors.textMuted
                          : AppColors.error),
                  const SizedBox(width: 6),
                  Text(
                    'Reject',
                    style: TextStyle(
                      color: isProcessing
                          ? AppColors.textMuted
                          : AppColors.error,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: TapScaleWidget(
            onTap: isProcessing ? null : () => _approveSubmission(doc),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: isProcessing
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.success, Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isProcessing ? AppColors.successBg : null,
                borderRadius: BorderRadius.circular(10),
                boxShadow: isProcessing
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isProcessing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.success, strokeWidth: 2),
                    )
                  else ...[
                    const Icon(LucideIcons.checkCircle2,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    const Text(
                      'Approve',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _outcomeColor(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'interested':
        return AppColors.success;
      case 'not interested':
      case 'not_interested':
        return AppColors.error;
      case 'callback':
        return AppColors.warning;
      case 'no answer':
      case 'no_answer':
        return AppColors.textMuted;
      case 'wrong number':
      case 'wrong_number':
        return AppColors.rose;
      default:
        return AppColors.primary;
    }
  }

  Widget _cardInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textLight),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<double?> _askForRating(BuildContext context,
      {required bool isApprove}) async {
    double selectedRating = 0;
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF1E2235) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isApprove
                          ? AppColors.successBg
                          : AppColors.errorBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isApprove
                          ? LucideIcons.checkCircle2
                          : LucideIcons.xCircle,
                      color:
                          isApprove ? AppColors.success : AppColors.error,
                      size: 28,
                    ),
                  )
                      .animate()
                      .scale(
                        begin: const Offset(0.5, 0.5),
                        duration: 300.ms,
                        curve: Curves.elasticOut,
                      )
                      .fadeIn(),
                  const SizedBox(height: 16),
                  Text(
                    isApprove ? 'Approve & Rate' : 'Reject & Rate',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rate the employee\'s performance\nbefore continuing.',
                    style: TextStyle(
                        color: isDark ? Colors.white60 : AppColors.textMuted,
                        fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  if (!isApprove) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Rejected tasks still need ratings.',
                        style: TextStyle(
                            color: AppColors.error, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // ── Star Rating ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      final filled = starIndex <= selectedRating;
                      return GestureDetector(
                        onTap: () => setState(
                            () => selectedRating = starIndex.toDouble()),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4.0),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              filled ? Icons.star_rounded : Icons.star_outline_rounded,
                              key: ValueKey('$starIndex-$filled'),
                              size: 44,
                              color: filled
                                  ? AppColors.accent
                                  : (isDark ? Colors.white24 : AppColors.textLight),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  // ── Action buttons ──
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                    color: isDark ? Colors.white24 : AppColors.border)),
                          ),
                          child: Text('Cancel',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : AppColors.textMuted,
                              )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: selectedRating > 0 ? 1.0 : 0.4,
                          duration: const Duration(milliseconds: 200),
                          child: ElevatedButton(
                            onPressed: selectedRating > 0
                                ? () => Navigator.pop(ctx, selectedRating)
                                : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: isApprove
                                  ? AppColors.success
                                  : AppColors.error,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: selectedRating > 0 ? 4 : 0,
                              shadowColor: (isApprove
                                      ? AppColors.success
                                      : AppColors.error)
                                  .withValues(alpha: 0.4),
                            ),
                            child: Text(
                              isApprove ? 'Confirm' : 'Reject',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}

class RequeueScheduleRow extends StatefulWidget {
  final dynamic requeueAfter;
  final String leadId;
  final String taskId;
  final FirebaseFirestore? firestore;

  const RequeueScheduleRow({
    super.key,
    required this.requeueAfter,
    required this.leadId,
    required this.taskId,
    this.firestore,
  });

  @override
  State<RequeueScheduleRow> createState() => _RequeueScheduleRowState();
}

class _RequeueScheduleRowState extends State<RequeueScheduleRow> {
  Timer? _timer;
  late DateTime _now;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _leadStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _taskStream;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _watchDocuments();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _watchDocuments() {
    final firestore = widget.firestore ?? FirebaseFirestore.instance;
    _leadStream = widget.leadId.isEmpty || widget.leadId.contains('/')
        ? null
        : firestore.collection('campaign_leads').doc(widget.leadId).snapshots();
    _taskStream = widget.taskId.isEmpty || widget.taskId.contains('/')
        ? null
        : firestore.collection('tasks').doc(widget.taskId).snapshots();
  }

  @override
  void didUpdateWidget(covariant RequeueScheduleRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leadId != widget.leadId ||
        oldWidget.taskId != widget.taskId ||
        oldWidget.firestore != widget.firestore) {
      _watchDocuments();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _leadStream,
      builder: (context, leadSnapshot) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _taskStream,
        builder: (context, taskSnapshot) {
          final lead = leadSnapshot.data?.data();
          final task = taskSnapshot.data?.data();
            final schedule = lead != null && lead['status'] == 'requeue_pending'
              ? lead['requeueAfter']
              : widget.requeueAfter;
          final due = schedule is Timestamp
              ? schedule.toDate()
              : schedule is DateTime ? schedule : null;
          var label = 'Lead status unavailable';
          var color = AppColors.textMuted;

          if (leadSnapshot.connectionState == ConnectionState.waiting) {
            label = 'Checking retry status...';
          } else if (_leadStream != null && !leadSnapshot.hasError && lead != null &&
              lead['taskId'] == widget.taskId) {
            switch (lead['status']) {
              case 'requeue_pending':
                color = AppColors.warning;
                final remaining = due?.difference(_now);
                if (remaining == null) {
                  label = 'Retry scheduled - time unavailable';
                } else if (remaining <= Duration.zero) {
                  label = 'Retry due - waiting for scheduler';
                } else {
                  label = 'Retry scheduled - '
                      '${remaining.inDays > 0 ? '${remaining.inDays}d ' : ''}'
                      '${(remaining.inHours % 24).toString().padLeft(2, '0')}:'
                      '${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:'
                      '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
                }
              case 'pending':
                color = AppColors.primary;
                if (taskSnapshot.connectionState == ConnectionState.waiting) {
                  label = 'Returned - checking destination';
                } else if (_taskStream == null || taskSnapshot.hasError || task == null) {
                  label = 'Returned - location unavailable';
                } else if (task['status'] == 'pending_team_leader') {
                  label = 'Returned - Awaiting Team Leader';
                } else if (task['status'] != 'active') {
                  label = 'Returned - Task not available';
                } else if (task['distributionMode'] == 'individual') {
                  label = 'Returned - Individual task';
                } else if (task['distributionMode'] != 'marketplace') {
                  label = 'Returned - location unavailable';
                } else if (task['remainingSlots'] is num &&
                    (task['remainingSlots'] as num) > 0) {
                  label = 'Returned - Available in Marketplace';
                } else {
                  label = 'Returned - Waiting for an available slot';
                }
              case 'assigned':
                label = 'Reassigned - Awaiting work';
              case 'in_progress':
                label = 'Reassigned - In progress';
              case 'completed':
              case 'pending_admin_review':
                label = 'Retry completed - Awaiting review';
              case 'approved':
                label = 'Retry approved';
                color = AppColors.success;
              case 'wrong_number':
                label = 'Closed - Wrong number';
              case 'unreachable':
                label = 'Closed - Retry limit reached';
              case 'rejected':
                label = 'Closed - Rejected';
            }
          }
          return _buildRow(label, color, due);
        },
      ),
    );
  }

  Widget _buildRow(String label, Color color, DateTime? due) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Icon(LucideIcons.calendarClock, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                    color: color)),
                if (due != null)
                  Text(_AdminReviewScreenState._formatDateTime(due),
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ANIMATED REVIEW CARD WRAPPER
// ═══════════════════════════════════════════════════════════════
class _AnimatedReviewCard extends StatelessWidget {
  final int index;
  final Widget child;

  const _AnimatedReviewCard({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return child
        .animate(delay: Duration(milliseconds: index.clamp(0, 5) * 70))
        .fadeIn(duration: 400.ms)
        .slideY(
          begin: 0.2,
          end: 0,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        )
        .scale(
          begin: const Offset(0.97, 0.97),
          end: const Offset(1, 1),
          duration: 350.ms,
        );
  }
}

// ═══════════════════════════════════════════════════════════════
// PENDING COUNT BADGE — Live Firestore Count
// ═══════════════════════════════════════════════════════════════
class _PendingCountBadge extends StatelessWidget {
  final FirebaseFirestore firestore;

  const _PendingCountBadge({required this.firestore});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('task_submissions')
          .where('status', isEqualTo: 'pending_admin_review')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.error.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Text(
            '$count pending',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(
              end: 1.06,
              duration: 1200.ms,
              curve: Curves.easeInOut,
            );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ANIMATED SEARCH BAR
// ═══════════════════════════════════════════════════════════════
class _AnimatedSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String searchQuery;

  const _AnimatedSearchBar(
      {required this.controller, required this.searchQuery});

  @override
  State<_AnimatedSearchBar> createState() => _AnimatedSearchBarState();
}

class _AnimatedSearchBarState extends State<_AnimatedSearchBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 2),
                )
              ]
            : [],
      ),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: TextField(
          controller: widget.controller,
          style: TextStyle(
            color: isDark ? Colors.white : AppColors.textDark,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Search by phone or Employee ID...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : AppColors.textPlaceholder,
              fontSize: 14,
            ),
            prefixIcon: AnimatedRotation(
              turns: _focused ? 0.02 : 0,
              duration: const Duration(milliseconds: 300),
              child: Icon(LucideIcons.search,
                  size: 18,
                  color: isDark ? Colors.white38 : AppColors.textMuted),
            ),
            suffixIcon: widget.searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 16,
                        color: isDark ? Colors.white38 : AppColors.textMuted),
                    onPressed: () => widget.controller.clear(),
                  )
                    .animate()
                    .fadeIn(duration: 200.ms)
                    .scale(begin: const Offset(0.5, 0.5))
                : null,
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : AppColors.border,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              borderSide: BorderSide(
                color: isDark ? Colors.white12 : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ANIMATED FILTER CHIP
// ═══════════════════════════════════════════════════════════════
class _AnimatedFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _AnimatedFilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : AppColors.textBody),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SKELETON REVIEW CARD
// ═══════════════════════════════════════════════════════════════
class _SkeletonReviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerWidget(width: 38, height: 38, borderRadius: 12),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerWidget(height: 14, width: 120),
                  ],
                ),
              ),
              ShimmerWidget(width: 80, height: 24, borderRadius: 20),
            ],
          ),
          SizedBox(height: 16),
          ShimmerWidget(height: 12),
          SizedBox(height: 8),
          ShimmerWidget(height: 12, width: 180),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ShimmerWidget(height: 40, borderRadius: 10),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ShimmerWidget(height: 40, borderRadius: 10),
              ),
            ],
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 1500.ms,
          color: Colors.white38,
        );
  }
}

// ═══════════════════════════════════════════════════════════════
// AUDIO PLAYER WIDGET
// ═══════════════════════════════════════════════════════════════
class _AudioPlayerWidget extends StatefulWidget {
  final String url;
  const _AudioPlayerWidget({required this.url});
  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}


class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMsg = '';
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (mounted) setState(() { _isLoading = true; _hasError = false; });
    try {
      // If this is our proxy recording endpoint, append the Firebase ID token
      // as a query parameter (just_audio cannot set custom headers).
      String audioUrl = widget.url;
      if (audioUrl.contains('/api/recording')) {
        try {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token != null && token.isNotEmpty) {
            final separator = audioUrl.contains('?') ? '&' : '?';
            audioUrl = '$audioUrl${separator}token=$token';
          }
        } catch (tokenErr) {
          debugPrint('Could not fetch auth token for recording: $tokenErr');
        }
      }
      await _player.setUrl(audioUrl);

      _player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.durationStream.listen((d) {
        if (mounted) setState(() => _duration = d ?? Duration.zero);
      });
      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
            if (state.processingState == ProcessingState.completed) {
              _player.seek(Duration.zero);
              _player.pause();
            }
          });
        }
      });
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading audio: $e');
      if (mounted) {
        setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMsg = 'Recording not ready yet';
      });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: AppColors.primary)),
            SizedBox(width: 10),
            Text('Loading recording...',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (_hasError) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.micOff,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(_errorMsg,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryMuted),
      ),
      child: Row(
        children: [
          // Play/Pause button with animation
          GestureDetector(
            onTap: () {
              if (_isPlaying) {
                _player.pause();
              } else {
                _player.play();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Icon(
                _isPlaying ? LucideIcons.pause : LucideIcons.play,
                color: Colors.white,
                size: 16,
              ),
            )
                .animate(target: _isPlaying ? 1 : 0)
                .scaleXY(end: 0.95, duration: 100.ms),
          ),
          const SizedBox(width: 10),
          // Progress bar + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.primaryMuted,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(_position),
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _formatTime(_duration),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.2, end: 0);
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
