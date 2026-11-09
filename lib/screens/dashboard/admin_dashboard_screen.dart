// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:lucide_icons/lucide_icons.dart';
// import 'package:provider/provider.dart';
// import 'package:intl/intl.dart';
// import '../../core/constants/constants.dart';
// import '../../services/auth_service.dart';
// import '../../routes.dart';

// /// Admin Dashboard Screen — Role-aware, task-reviewer focused.
// class AdminDashboardScreen extends StatefulWidget {
//   /// The role the admin chose to work as on the role-select screen. When null
//   /// (e.g. legacy deep-links), the dashboard falls back to the admin's primary
//   /// `role` from their Firestore profile.
//   final String? activeRole;

//   const AdminDashboardScreen({
//     super.key,
//     this.activeRole,
//     this.auth,
//     this.firestore,
//   });

//   final FirebaseAuth? auth;
//   final FirebaseFirestore? firestore;

//   @override
//   State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
// }

// class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
//   ErrorWidgetBuilder? _originalErrorWidgetBuilder;
//   FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
//   FirebaseFirestore get _firestore =>
//       widget.firestore ?? FirebaseFirestore.instance;

//   @override
//   void initState() {
//     super.initState();
//     // Force-refresh the ID token so freshly-assigned role claims (synced to the
//     // auth token by the syncUserClaims trigger) reach the Firestore security
//     // rules. This heals sessions that signed in BEFORE a role was granted —
//     // without it, per-role queries (task_submissions, users) stay denied until
//     // the admin logs out and back in. The Firestore SDK re-runs active
//     // listeners automatically once the refreshed token lands.
//     _auth.currentUser?.getIdToken(true);
//     _originalErrorWidgetBuilder = ErrorWidget.builder;
//     ErrorWidget.builder = (FlutterErrorDetails details) {
//       debugPrint(
//         '⚠️ [AdminDashboard] ErrorWidget caught: ${details.exception}',
//       );
//       return Container(
//         padding: const EdgeInsets.all(AppSizes.md),
//         margin: const EdgeInsets.all(AppSizes.sm),
//         decoration: BoxDecoration(
//           color: AppColors.error.withValues(alpha: 0.1),
//           borderRadius: BorderRadius.circular(AppSizes.radiusSm),
//           border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
//         ),
//         child: const Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               LucideIcons.alertTriangle,
//               size: 16,
//               color: AppColors.error,
//             ),
//             SizedBox(width: 8),
//             Flexible(
//               child: Text(
//                 'Widget error — data loading...',
//                 style: TextStyle(
//                   color: AppColors.error,
//                   fontSize: 12,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       );
//     };
//   }

//   @override
//   void dispose() {
//     if (_originalErrorWidgetBuilder != null) {
//       ErrorWidget.builder = _originalErrorWidgetBuilder!;
//     }
//     super.dispose();
//   }

//   /// Human-readable label for each admin role.
//   String _roleLabel(String role) {
//     switch (role) {
//       case 'super_admin':
//         return 'Super Admin';
//       case 'task_review_admin':
//         return 'Task Reviewer';
//       case 'kyc_admin':
//         return 'KYC Admin';
//       case 'payment_admin':
//         return 'Payment Admin';
//       case 'support_admin':
//         return 'Support Admin';
//       case 'admin':
//         return 'Admin';
//       default:
//         return 'Admin';
//     }
//   }

//   /// Every role the admin holds (handles legacy single-role docs).
//   List<String> _rolesOf(Map<String, dynamic> data) {
//     final raw = data['roles'];
//     if (raw is List && raw.isNotEmpty) {
//       return raw.map((e) => e.toString()).toList();
//     }
//     final single = data['role']?.toString();
//     return single == null ? <String>[] : [single];
//   }

//   /// Support-desk summary: open tickets + active chats.
//   Widget _buildSupportAdminStats(bool isDark) {
//     return Row(
//       children: [
//         Expanded(
//           child: _supportCountCard(
//             isDark,
//             stream: _firestore
//                 .collection('support_requests')
//                 .where('status', whereIn: ['open', 'pending', 'in_progress'])
//                 .snapshots(),
//             label: 'Open Tickets',
//             icon: LucideIcons.helpCircle,
//             color: AppColors.info,
//           ),
//         ),
//         const SizedBox(width: AppSizes.md),
//         Expanded(
//           child: _supportCountCard(
//             isDark,
//             stream: _firestore
//                 .collection('support_chats')
//                 .where('status', isEqualTo: 'open')
//                 .snapshots(),
//             label: 'Active Chats',
//             icon: LucideIcons.messageSquare,
//             color: AppColors.success,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _supportCountCard(
//     bool isDark, {
//     required Stream<QuerySnapshot> stream,
//     required String label,
//     required IconData icon,
//     required Color color,
//   }) {
//     return Container(
//       padding: const EdgeInsets.all(AppSizes.lg),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(
//           color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
//         ),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             width: 36,
//             height: 36,
//             decoration: BoxDecoration(
//               color: color.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//             ),
//             child: Icon(icon, color: color, size: 18),
//           ),
//           const SizedBox(height: AppSizes.md),
//           StreamBuilder<QuerySnapshot>(
//             stream: stream,
//             builder: (context, snap) {
//               final count = snap.data?.docs.length ?? 0;
//               return Text(
//                 '$count',
//                 style: TextStyle(
//                   fontSize: 24,
//                   fontWeight: FontWeight.w800,
//                   color: isDark ? Colors.white : AppColors.textDark,
//                 ),
//               );
//             },
//           ),
//           Text(
//             label,
//             style: TextStyle(
//               fontSize: 12,
//               color: isDark ? Colors.white38 : AppColors.textMuted,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     final user = _auth.currentUser;
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     if (user == null) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         Navigator.of(
//           context,
//         ).pushNamedAndRemoveUntil(AppRoutes.adminLogin, (_) => false);
//       });
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }

//     return Scaffold(
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       appBar: AppBar(
//         backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//         foregroundColor: Theme.of(context).colorScheme.onSurface,
//         elevation: 0,
//         scrolledUnderElevation: 0,
//         centerTitle: false,
//         title: const Text(
//           'Admin workspace',
//           style: TextStyle(
//             fontSize: 18,
//             fontWeight: FontWeight.w600,
//             letterSpacing: 0,
//           ),
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(LucideIcons.logOut, size: 20),
//             tooltip: 'Logout',
//             onPressed: () => _handleLogout(context),
//           ),
//           const SizedBox(width: 8),
//         ],
//       ),
//       body: StreamBuilder<DocumentSnapshot>(
//         stream: _firestore.collection('users').doc(user.uid).snapshots(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting &&
//               !snapshot.hasData) {
//             return const Center(child: CircularProgressIndicator());
//           }

//           if (snapshot.hasError) {
//             return _buildErrorState(
//               'Failed to load admin profile',
//               onRetry: () => setState(() {}),
//             );
//           }

//           final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
//           // Every role the admin actually holds (multi-role support). Falls back
//           // to full-admin only when the profile carries no role at all.
//           final myRoles = _rolesOf(data);
//           final baseRoles = myRoles.isEmpty ? const ['admin'] : myRoles;
//           final isSuper =
//               baseRoles.contains('admin') || baseRoles.contains('super_admin');
//           // A super admin may scope into a single role via the picker; every
//           // other admin sees the COMBINED dashboard for all roles they hold, so
//           // the screen changes with whatever roles are assigned to them.
//           final Set<String> activeRoles = (isSuper && widget.activeRole != null)
//               ? {widget.activeRole!}
//               : baseRoles.toSet();
//           final bool superView =
//               activeRoles.contains('admin') ||
//               activeRoles.contains('super_admin');
//           bool has(String r) => superView || activeRoles.contains(r);
//           bool holds(String r) => activeRoles.contains(r);
//           final isTaskReviewer = has('task_review_admin');
//           final isKycAdmin = has('kyc_admin');
//           final isPaymentAdmin = has('payment_admin');
//           final isSupportAdmin = has('support_admin');
//           final roleLabel = superView
//               ? 'Super Admin'
//               : activeRoles.map(_roleLabel).join(' \u2022 ');

//           return Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 880),
//               child: SingleChildScrollView(
//                 padding: const EdgeInsets.all(AppSizes.screenPaddingH),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const SizedBox(height: AppSizes.md),

//                     // ── Welcome Header ──────────────────────────────────────────
//                     _buildWelcomeHeader(roleLabel: roleLabel),
//                     const SizedBox(height: 24),

//                     // ── Analytics (role-specific) ───────────────────────────────
//                     if (!superView) ...[
//                       _buildSectionLabel(context, 'Overview', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       if (isTaskReviewer)
//                         _buildTaskReviewerStats(user.uid, isDark),
//                       if (isKycAdmin) ...[
//                         if (isTaskReviewer) const SizedBox(height: AppSizes.md),
//                         _buildKycAdminStats(isDark),
//                       ],
//                       if (isPaymentAdmin && !isKycAdmin) ...[
//                         if (isTaskReviewer) const SizedBox(height: AppSizes.md),
//                         _buildPaymentAdminStats(isDark),
//                       ],
//                       if (isSupportAdmin) ...[
//                         if (isTaskReviewer || isKycAdmin || isPaymentAdmin)
//                           const SizedBox(height: AppSizes.md),
//                         _buildSupportAdminStats(isDark),
//                       ],
//                     ],

//                     const SizedBox(height: 24),

//                     // ── Administrative Actions ──────────────────────────────────
//                     if (isTaskReviewer || isKycAdmin || isPaymentAdmin) ...[
//                       _buildSectionLabel(context, 'Reviews & payouts', isDark),
//                       const SizedBox(height: AppSizes.md),
//                     ],

//                     if (has('task_review_admin')) ...[
//                       _ActionTile(
//                         icon: LucideIcons.checkSquare,
//                         title: 'Review Task Submissions',
//                         subtitle: 'Approve or reject completed tasks',
//                         color: AppColors.success,
//                         onTap: () =>
//                             Navigator.pushNamed(context, AppRoutes.adminReview),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                     ],
//                     if (has('kyc_admin')) ...[
//                       _ActionTile(
//                         icon: LucideIcons.fileCheck,
//                         title: 'Review KYC Submissions',
//                         subtitle: 'Approve or reject employee KYC',
//                         color: AppColors.warning,
//                         onTap: () =>
//                             Navigator.pushNamed(context, AppRoutes.adminKyc),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                       _ActionTile(
//                         icon: LucideIcons.wallet,
//                         title: 'Process Withdrawals',
//                         subtitle: 'Approve pending payout requests',
//                         color: AppColors.error,
//                         onTap: () => Navigator.pushNamed(
//                           context,
//                           AppRoutes.adminWithdrawals,
//                         ),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                     ],
//                     // Payment admin: payouts only (no KYC access). Skipped when the
//                     // admin also holds kyc_admin, since that block already renders it.
//                     if (isPaymentAdmin && !isKycAdmin) ...[
//                       _ActionTile(
//                         icon: LucideIcons.wallet,
//                         title: 'Process Withdrawals',
//                         subtitle: 'Approve pending payout requests',
//                         color: AppColors.error,
//                         onTap: () => Navigator.pushNamed(
//                           context,
//                           AppRoutes.adminWithdrawals,
//                         ),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                     ],
//                     if (superView) ...[
//                       const SizedBox(height: 24),
//                       _buildSectionLabel(context, 'Platform', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _ActionTile(
//                         icon: LucideIcons.users,
//                         title: 'Manage Users',
//                         subtitle: 'Suspend, activate, or view employee activity',
//                         color: AppColors.info,
//                         onTap: () =>
//                             Navigator.pushNamed(context, AppRoutes.adminUsers),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                       _ActionTile(
//                         icon: LucideIcons.clipboardList,
//                         title: 'Manage Tasks',
//                         subtitle: 'Edit, pause, and delete tasks',
//                         color: AppColors.primary,
//                         onTap: () =>
//                             Navigator.pushNamed(context, AppRoutes.adminTasks),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                       _ActionTile(
//                         icon: LucideIcons.settings,
//                         title: 'Platform Settings',
//                         subtitle: 'Configure global system parameters',
//                         color: AppColors.primary,
//                         onTap: () => Navigator.pushNamed(
//                           context,
//                           AppRoutes.adminSettings,
//                         ),
//                       ),
//                     ],

//                     // ── Support Desk (support_admin + full admins) ──────────
//                     if (has('support_admin')) ...[
//                       const SizedBox(height: 24),
//                       _buildSectionLabel(context, 'Support', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _ActionTile(
//                         icon: LucideIcons.helpCircle,
//                         title: 'Support Tickets',
//                         subtitle: 'Resolve employee & client tickets',
//                         color: AppColors.info,
//                         onTap: () => Navigator.pushNamed(
//                           context,
//                           AppRoutes.adminSupport,
//                         ),
//                       ),
//                       const SizedBox(height: AppSizes.sm),
//                       _ActionTile(
//                         icon: LucideIcons.messageSquare,
//                         title: 'Live Chats',
//                         subtitle: 'Reply to client conversations',
//                         color: AppColors.success,
//                         onTap: () => Navigator.pushNamed(
//                           context,
//                           AppRoutes.adminSupportChats,
//                         ),
//                       ),
//                     ],

//                     // ── Mail / Inbox (all admin roles) ──────────────────────
//                     if (has('support_admin')) ...[
//                       const SizedBox(height: AppSizes.sm),
//                       _ActionTile(
//                         icon: LucideIcons.mail,
//                         title: 'Employee Mail',
//                         subtitle: 'Threaded messages with employees',
//                         color: AppColors.info,
//                         onTap: () =>
//                             Navigator.pushNamed(context, AppRoutes.adminMail),
//                       ),
//                     ],

//                     if (superView) ...[
//                       const SizedBox(height: 32),
//                       _buildSectionLabel(context, 'Review overview', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _buildFullAnalyticsStats(isDark),
//                       const SizedBox(height: 24),
//                       _buildSectionLabel(context, 'Platform overview', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _buildPlatformStatsSection(isDark),
//                     ],

//                     // ── Review History (task_review_admin) ──────────────────────
//                     if (holds('task_review_admin')) ...[
//                       const SizedBox(height: 28),
//                       _buildSectionLabel(context, 'Review History', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _ReviewHistorySection(adminUid: user.uid, isDark: isDark),
//                     ],

//                     // ── KYC & Withdrawal History (kyc_admin) ────────────────────
//                     if (holds('kyc_admin')) ...[
//                       const SizedBox(height: 28),
//                       _buildSectionLabel(context, 'KYC Review History', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _KycHistorySection(adminUid: user.uid, isDark: isDark),
//                       const SizedBox(height: 24),
//                       _buildSectionLabel(context, 'Withdrawal History', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _WithdrawalHistorySection(isDark: isDark),
//                     ],

//                     // ── Withdrawal History (payment_admin) ──────────────────
//                     if (holds('payment_admin') && !holds('kyc_admin')) ...[
//                       const SizedBox(height: 28),
//                       _buildSectionLabel(context, 'Withdrawal History', isDark),
//                       const SizedBox(height: AppSizes.md),
//                       _WithdrawalHistorySection(isDark: isDark),
//                     ],

//                     const SizedBox(height: AppSizes.xxl),
//                     const SizedBox(height: AppSizes.xxxl),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   // ── Section label ─────────────────────────────────────────────────────────
//   Widget _buildSectionLabel(BuildContext context, String text, bool isDark) {
//     return Text(
//       text,
//       style: TextStyle(
//         color: Theme.of(context).colorScheme.onSurface,
//         fontSize: 15,
//         letterSpacing: 0,
//         fontWeight: FontWeight.w700,
//       ),
//     );
//   }

//   // ── Welcome Header (now shows role label) ─────────────────────────────────
//   Widget _buildWelcomeHeader({required String roleLabel}) {
//     final colors = Theme.of(context).colorScheme;
//     return Row(
//       children: [
//         ClipRect(
//           child: Align(
//             widthFactor: 0.5,
//             heightFactor: 0.5,
//             alignment: const Alignment(-0.1, -0.4),
//             child: Image.asset(
//               'assets/images/sherize_logo.png',
//               width: 120,
//               height: 120,
//               excludeFromSemantics: true,
//             ),
//           ),
//         ),
//         const SizedBox(width: 16),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Sherize',
//                 style: TextStyle(
//                   color: colors.onSurface,
//                   fontSize: 26,
//                   fontWeight: FontWeight.w800,
//                   letterSpacing: 0,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 roleLabel,
//                 style: TextStyle(
//                   color: colors.onSurfaceVariant,
//                   fontSize: 14,
//                   letterSpacing: 0,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   // ── Task-reviewer-specific analytics (no revenue/KYC) ────────────────────
//   Widget _buildTaskReviewerStats(String adminUid, bool isDark) {
//     final now = DateTime.now();
//     final todayStart = DateTime(now.year, now.month, now.day);

//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('task_submissions')
//           // ponytail: single unfiltered read caps at 200 so the shared "Pending"
//           // queue and this reviewer's counts share one stream. Fine at current
//           // volume; if submissions exceed ~200, split into a pending count() +
//           // a reviewedBy==adminUid query so per-reviewer totals stay exact.
//           .limit(200)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return _buildStatsGridLoading();
//         }
//         if (snap.hasError) {
//           return _buildStatsGridError('Failed to load review stats');
//         }

//         final docs = snap.data?.docs ?? [];
//         int pending = 0;
//         int approvedToday = 0;
//         int rejectedToday = 0;
//         int totalReviewed = 0;

//         for (final d in docs) {
//           final data = (d.data() as Map<String, dynamic>?) ?? {};
//           final status = (data['status'] as String?) ?? '';
//           final reviewedAt = data['reviewedAt'];
//           final isToday = reviewedAt is Timestamp &&
//               reviewedAt.toDate().isAfter(todayStart);
//           // Approved/rejected counts belong to THIS reviewer only. Pending is the
//           // shared queue (not yet reviewed by anyone), so it stays global.
//           final reviewedByMe = data['reviewedBy'] == adminUid;

//           if (status == 'pending_admin_review') {
//             pending++;
//           } else if (status == 'approved' && reviewedByMe) {
//             totalReviewed++;
//             if (isToday) approvedToday++;
//           } else if (status == 'rejected' && reviewedByMe) {
//             totalReviewed++;
//             if (isToday) rejectedToday++;
//           }
//         }

//         return _buildStatsGrid([
//           _StatCardData(
//             icon: LucideIcons.clock,
//             label: 'Pending Reviews',
//             value: pending.toString(),
//             color: AppColors.warning,
//           ),
//           _StatCardData(
//             icon: LucideIcons.checkCircle,
//             label: 'Approved Today',
//             value: approvedToday.toString(),
//             color: AppColors.success,
//           ),
//           _StatCardData(
//             icon: LucideIcons.xCircle,
//             label: 'Rejected Today',
//             value: rejectedToday.toString(),
//             color: AppColors.error,
//           ),
//           _StatCardData(
//             icon: LucideIcons.clipboardCheck,
//             label: 'Total Reviewed',
//             value: totalReviewed.toString(),
//             color: AppColors.info,
//           ),
//         ]);
//       },
//     );
//   }

//   // ── KYC admin analytics (KYC + withdrawals only) ─────────────────────────
//   Widget _buildKycAdminStats(bool isDark) {
//     final now = DateTime.now();
//     final todayStart = DateTime(now.year, now.month, now.day);

//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('users')
//           .where('kycStatus', whereIn: ['pending', 'approved', 'rejected'])
//           .limit(200)
//           .snapshots(),
//       builder: (context, kycSnap) {
//         if (kycSnap.connectionState == ConnectionState.waiting && !kycSnap.hasData) {
//           return _buildStatsGridLoading();
//         }
//         if (kycSnap.hasError) {
//           return _buildStatsGridError('Failed to load KYC stats');
//         }

//         final kycDocs = kycSnap.data?.docs ?? [];
//         int pendingKyc = 0;
//         int kycApprovedToday = 0;
//         int kycRejectedToday = 0;

//         for (final d in kycDocs) {
//           final data = (d.data() as Map<String, dynamic>?) ?? {};
//           final kycStatus = (data['kycStatus'] as String?) ?? '';
//           final reviewedAt = data['kycReviewedAt'];
//           final isToday = reviewedAt is Timestamp &&
//               reviewedAt.toDate().isAfter(todayStart);

//           if (kycStatus == 'pending') {
//             pendingKyc++;
//           } else if (kycStatus == 'approved' && isToday) {
//             kycApprovedToday++;
//           } else if (kycStatus == 'rejected' && isToday) {
//             kycRejectedToday++;
//           }
//         }

//         return StreamBuilder<QuerySnapshot>(
//           stream: FirebaseFirestore.instance
//               .collection('withdraw_requests')
//               .where('status', isEqualTo: 'pending')
//               .limit(100)
//               .snapshots(),
//           builder: (context, withdrawSnap) {
//             final pendingWithdrawals =
//                 withdrawSnap.data?.docs.length ?? 0;

//             return _buildStatsGrid([
//               _StatCardData(
//                 icon: LucideIcons.fileCheck,
//                 label: 'Pending KYC',
//                 value: pendingKyc.toString(),
//                 color: AppColors.warning,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.checkCircle,
//                 label: 'KYC Approved Today',
//                 value: kycApprovedToday.toString(),
//                 color: AppColors.success,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.xCircle,
//                 label: 'KYC Rejected Today',
//                 value: kycRejectedToday.toString(),
//                 color: AppColors.error,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.wallet,
//                 label: 'Pending Withdrawals',
//                 value: pendingWithdrawals.toString(),
//                 color: AppColors.info,
//               ),
//             ]);
//           },
//         );
//       },
//     );
//   }

//   // ── Payment admin analytics (payouts only) ───────────────────────────────
//   // Reads ONLY withdraw_requests + payout_history, both permitted for
//   // payment_admin via isAdmin(). Avoids the super-admin-only users list and the
//   // task_submissions collection (task-admins only), which is why the generic
//   // full-admin dashboard failed to load for this role.
//   Widget _buildPaymentAdminStats(bool isDark) {
//     final currency =
//         NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0);

//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('withdraw_requests')
//           .where('status', isEqualTo: 'pending')
//           .limit(200)
//           .snapshots(),
//       builder: (context, pendingSnap) {
//         if (pendingSnap.connectionState == ConnectionState.waiting &&
//             !pendingSnap.hasData) {
//           return _buildStatsGridLoading();
//         }
//         if (pendingSnap.hasError) {
//           return _buildStatsGridError('Failed to load payout stats');
//         }

//         final pendingDocs = pendingSnap.data?.docs ?? [];
//         num pendingAmount = 0;
//         for (final d in pendingDocs) {
//           final data = (d.data() as Map<String, dynamic>?) ?? {};
//           pendingAmount += (data['amount'] as num?) ?? 0;
//         }

//         return StreamBuilder<QuerySnapshot>(
//           stream: FirebaseFirestore.instance
//               .collection('payout_history')
//               .limit(100)
//               .snapshots(),
//           builder: (context, payoutSnap) {
//             final processedCount = payoutSnap.data?.docs.length ?? 0;

//             return _buildStatsGrid([
//               _StatCardData(
//                 icon: LucideIcons.wallet,
//                 label: 'Pending Withdrawals',
//                 value: pendingDocs.length.toString(),
//                 color: AppColors.warning,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.indianRupee,
//                 label: 'Pending Amount',
//                 value: currency.format(pendingAmount),
//                 color: AppColors.error,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.checkCircle,
//                 label: 'Payouts Processed',
//                 value: processedCount.toString(),
//                 color: AppColors.success,
//               ),
//             ]);
//           },
//         );
//       },
//     );
//   }

//   // ── Full analytics (super_admin / admin) ─────────────────────────────────
//   Widget _buildFullAnalyticsStats(bool isDark) {
//     final now = DateTime.now();
//     final todayStart = DateTime(now.year, now.month, now.day);

//     return StreamBuilder<QuerySnapshot>(
//       stream: _firestore
//           .collection('task_submissions')
//           .limit(100)
//           .snapshots(),
//       builder: (context, submissionsSnap) {
//         if (submissionsSnap.connectionState == ConnectionState.waiting &&
//             !submissionsSnap.hasData) {
//           return _buildStatsGridLoading();
//         }
//         if (submissionsSnap.hasError) {
//           return _buildStatsGridError('Failed to load review stats');
//         }

//         final docs = submissionsSnap.data?.docs ?? [];
//         int pendingCount = 0;
//         int approvedToday = 0;

//         for (final doc in docs) {
//           final d = (doc.data() as Map<String, dynamic>?) ?? {};
//           final status = (d['status'] as String?) ?? '';
//           if (status == 'pending_admin_review') {
//             pendingCount++;
//           } else if (status == 'approved') {
//             final reviewedAt = d['reviewedAt'];
//             if (reviewedAt is Timestamp &&
//                 reviewedAt.toDate().isAfter(todayStart)) {
//               approvedToday++;
//             }
//           }
//         }

//         return StreamBuilder<DocumentSnapshot>(
//           stream: _firestore
//               .collection('platform_earnings')
//               .doc('global')
//               .snapshots(),
//           builder: (context, earningsSnap) {
//             final eData =
//                 earningsSnap.data?.data() as Map<String, dynamic>? ?? {};
//             final totalRevenue =
//                 NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
//                     .format(eData['totalRevenue'] ?? 0);
//             final netProfit =
//                 NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
//                     .format(eData['netProfit'] ?? 0);

//             return _buildStatsGrid([
//               _StatCardData(
//                 icon: LucideIcons.clock,
//                 label: 'Pending Reviews',
//                 value: pendingCount.toString(),
//                 color: AppColors.warning,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.checkCircle,
//                 label: 'Approved Today',
//                 value: approvedToday.toString(),
//                 color: AppColors.success,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.trendingUp,
//                 label: 'Gross Revenue',
//                 value: totalRevenue,
//                 color: AppColors.success,
//               ),
//               _StatCardData(
//                 icon: LucideIcons.award,
//                 label: 'Net Profits',
//                 value: netProfit,
//                 color: AppColors.accent,
//               ),
//             ]);
//           },
//         );
//       },
//     );
//   }

//   // ── Platform stats (workers / KYC / payouts) ─────────────────────────────
//   Widget _buildPlatformStatsSection(bool isDark) {
//     return FutureBuilder<_PlatformStats>(
//       future: _fetchPlatformStats(),
//       builder: (context, snapshot) {
//         if (snapshot.connectionState == ConnectionState.waiting) {
//           return _buildStatsGridLoading();
//         }

//         if (snapshot.hasError) {
//           return _buildStatsGridError('Failed to load platform stats');
//         }

//         final stats = snapshot.data;
//         if (stats == null) {
//           return _buildEmptyStatsState('No platform data available');
//         }

//         return _buildStatsGrid([
//           _StatCardData(
//             icon: LucideIcons.users,
//             label: 'Total Employees',
//             value: stats.totalWorkers.toString(),
//             color: AppColors.info,
//           ),
//           _StatCardData(
//             icon: LucideIcons.fileCheck,
//             label: 'Pending KYC',
//             value: stats.pendingKyc.toString(),
//             color: AppColors.warning,
//           ),
//           _StatCardData(
//             icon: LucideIcons.clipboardList,
//             label: 'Active Tasks',
//             value: stats.activeTasks.toString(),
//             color: AppColors.success,
//           ),
//           _StatCardData(
//             icon: LucideIcons.wallet,
//             label: 'Pending Payouts',
//             value: stats.pendingWithdrawals.toString(),
//             color: AppColors.error,
//           ),
//         ]);
//       },
//     );
//   }

//   Future<_PlatformStats> _fetchPlatformStats() async {
//     try {
//       final results = await Future.wait([
//         _firestore
//             .collection('users')
//             .where('role', isEqualTo: 'worker')
//             .limit(100)
//             .get(),
//         _firestore
//             .collection('users')
//             .where('kycStatus', isEqualTo: 'pending')
//             .limit(100)
//             .get(),
//         _firestore
//             .collection('tasks')
//             .where('status', isEqualTo: 'active')
//             .limit(100)
//             .get(),
//         _firestore
//             .collection('withdraw_requests')
//             .where('status', isEqualTo: 'pending')
//             .limit(100)
//             .get(),
//       ]);

//       return _PlatformStats(
//         totalWorkers: results[0].docs.length,
//         pendingKyc: results[1].docs.length,
//         activeTasks: results[2].docs.length,
//         pendingWithdrawals: results[3].docs.length,
//       );
//     } catch (e) {
//       debugPrint('❌ [AdminDashboard] _fetchPlatformStats error: $e');
//       rethrow;
//     }
//   }

//   // ── Grid helpers ──────────────────────────────────────────────────────────
//   Widget _buildStatsGrid(List<_StatCardData> items) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
//         final columns = constraints.maxWidth >= 700 && !largeText
//             ? 4
//             : constraints.maxWidth >= 340 && !largeText
//             ? 2
//             : 1;
//         final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
//         return Wrap(
//           spacing: 12,
//           runSpacing: 12,
//           children: items
//               .map(
//                 (item) => SizedBox(
//                   width: width,
//                   child: _StatCard(
//                     icon: item.icon,
//                     label: item.label,
//                     value: item.value,
//                     color: item.color,
//                   ),
//                 ),
//               )
//               .toList(),
//         );
//       },
//     );
//   }

//   Widget _buildStatsGridLoading() {
//     return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
//   }

//   Widget _buildStatsGridError(String message) {
//     return Container(
//       padding: const EdgeInsets.all(AppSizes.xl),
//       decoration: BoxDecoration(
//         color: AppColors.error.withValues(alpha: 0.1),
//         borderRadius: BorderRadius.circular(AppSizes.radiusMd),
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Icon(LucideIcons.alertTriangle, size: 32, color: AppColors.error),
//           const SizedBox(height: AppSizes.sm),
//           Text(message, style: const TextStyle(color: AppColors.error)),
//           TextButton(onPressed: () => setState(() {}), child: const Text('Retry')),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyStatsState(String message) {
//     return Center(child: Text(message));
//   }

//   Widget _buildErrorState(String message, {VoidCallback? onRetry}) {
//     return Center(
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Icon(LucideIcons.alertTriangle, size: 48, color: AppColors.error),
//           const SizedBox(height: AppSizes.md),
//           Text(message, style: const TextStyle(color: AppColors.error)),
//           if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
//         ],
//       ),
//     );
//   }

//   // ── Logout ────────────────────────────────────────────────────────────────
//   void _handleLogout(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     showDialog(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         backgroundColor: Theme.of(context).cardColor,
//         title: Text('Logout',
//             style: TextStyle(
//                 color: isDark ? Colors.white : AppColors.textDark,
//                 fontWeight: FontWeight.bold)),
//         content: Text(
//           'Are you sure you want to logout from the admin panel?',
//           style: TextStyle(color: isDark ? Colors.white70 : AppColors.textBody),
//         ),
//         actions: [
//           TextButton(
//               onPressed: () => Navigator.pop(ctx),
//               child: Text('Cancel',
//                   style: TextStyle(
//                       color: isDark ? Colors.white38 : AppColors.textMuted))),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(ctx);
//               await Provider.of<AuthService>(context, listen: false).logout();
//               if (context.mounted) {
//                 Navigator.of(context).pushNamedAndRemoveUntil(
//                     AppRoutes.adminLogin, (route) => false);
//               }
//             },
//             child: const Text('Logout',
//                 style: TextStyle(
//                     color: AppColors.error, fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ─── Review History Section ───────────────────────────────────────────────────
// // Shows ONLY the submissions the signed-in admin personally reviewed
// // (reviewedBy == their uid), newest first, with an optional single-day filter.
// class _ReviewHistorySection extends StatefulWidget {
//   final String adminUid;
//   final bool isDark;

//   const _ReviewHistorySection({
//     required this.adminUid,
//     required this.isDark,
//   });

//   @override
//   State<_ReviewHistorySection> createState() => _ReviewHistorySectionState();
// }

// class _ReviewHistorySectionState extends State<_ReviewHistorySection> {
//   // When set, only reviews made on this calendar day are shown.
//   // Defaults to today; the clear (×) button switches back to all dates.
//   DateTime? _selectedDate = DateTime.now();

//   // Base query: this admin's reviews only. `reviewedBy` is written on both the
//   // approve and reject paths, so it attributes every reviewed submission.
//   // Optionally narrowed to a single day; always newest first.
//   Query<Map<String, dynamic>> _buildQuery() {
//     Query<Map<String, dynamic>> q = FirebaseFirestore.instance
//         .collection('task_submissions')
//         .where('reviewedBy', isEqualTo: widget.adminUid);

//     if (_selectedDate != null) {
//       final start = DateTime(
//           _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
//       final end = start.add(const Duration(days: 1));
//       q = q
//           .where('reviewedAt',
//               isGreaterThanOrEqualTo: Timestamp.fromDate(start))
//           .where('reviewedAt', isLessThan: Timestamp.fromDate(end));
//     }

//     return q.orderBy('reviewedAt', descending: true).limit(50);
//   }

//   Future<void> _pickDate() async {
//     final now = DateTime.now();
//     final picked = await showDatePicker(
//       context: context,
//       initialDate: _selectedDate ?? now,
//       firstDate: DateTime(2024),
//       lastDate: now,
//     );
//     if (picked != null) setState(() => _selectedDate = picked);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         _buildFilterBar(context),
//         const SizedBox(height: 12),
//         StreamBuilder<QuerySnapshot>(
//           stream: _buildQuery().snapshots(),
//           builder: (context, snap) {
//             if (snap.connectionState == ConnectionState.waiting &&
//                 !snap.hasData) {
//               return const Center(
//                   heightFactor: 2, child: CircularProgressIndicator());
//             }
//             // Missing composite index (or transient error) → index-free fallback.
//             if (snap.hasError) {
//               return _buildFallback(context);
//             }
//             final docs = snap.data?.docs ?? [];
//             if (docs.isEmpty) return _buildEmptyHistory(context);
//             return _buildList(docs);
//           },
//         ),
//       ],
//     );
//   }

//   // Fallback avoids the composite index: filter by reviewedBy only (single-field,
//   // no index needed), then apply the date filter + sort on the client.
//   Widget _buildFallback(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('task_submissions')
//           .where('reviewedBy', isEqualTo: widget.adminUid)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return const Center(
//               heightFactor: 2, child: CircularProgressIndicator());
//         }
//         if (snap.hasError || !snap.hasData) {
//           return _buildEmptyHistory(context);
//         }
//         final filtered = snap.data!.docs.where((d) {
//           if (_selectedDate == null) return true;
//           final at = (d.data() as Map)['reviewedAt'];
//           if (at is! Timestamp) return false;
//           final dt = at.toDate();
//           return dt.year == _selectedDate!.year &&
//               dt.month == _selectedDate!.month &&
//               dt.day == _selectedDate!.day;
//         }).toList()
//           ..sort((a, b) {
//             final aAt = (a.data() as Map)['reviewedAt'];
//             final bAt = (b.data() as Map)['reviewedAt'];
//             if (aAt is Timestamp && bAt is Timestamp) return bAt.compareTo(aAt);
//             return 0;
//           });
//         if (filtered.isEmpty) return _buildEmptyHistory(context);
//         return _buildList(filtered.take(50).toList());
//       },
//     );
//   }

//   Widget _buildList(List<QueryDocumentSnapshot> docs) {
//     return Column(
//       children: docs.map((doc) {
//         final d = (doc.data() as Map<String, dynamic>?) ?? {};
//         return _ReviewHistoryCard(
//             data: d, docId: doc.id, isDark: widget.isDark);
//       }).toList(),
//     );
//   }

//   Widget _buildFilterBar(BuildContext context) {
//     final hasDate = _selectedDate != null;
//     final label =
//         hasDate ? DateFormat('dd MMM yyyy').format(_selectedDate!) : 'All dates';
//     return Row(
//       children: [
//         Expanded(
//           child: InkWell(
//             onTap: _pickDate,
//             borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
//               decoration: BoxDecoration(
//                 color: Theme.of(context).cardColor,
//                 borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//                 border: Border.all(
//                   color: widget.isDark
//                       ? Colors.white.withValues(alpha: 0.08)
//                       : AppColors.textLight.withValues(alpha: 0.25),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Icon(LucideIcons.calendar,
//                       size: 16,
//                       color:
//                           widget.isDark ? Colors.white54 : AppColors.textMuted),
//                   const SizedBox(width: 10),
//                   Text(
//                     label,
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.w600,
//                       color: widget.isDark ? Colors.white : AppColors.textDark,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//         if (hasDate) ...[
//           const SizedBox(width: 8),
//           IconButton(
//             onPressed: () => setState(() => _selectedDate = null),
//             icon: const Icon(LucideIcons.x, size: 18),
//             tooltip: 'Clear date',
//             color: widget.isDark ? Colors.white54 : AppColors.textMuted,
//           ),
//         ],
//       ],
//     );
//   }

//   Widget _buildEmptyHistory(BuildContext context) {
//     final msg = _selectedDate == null
//         ? 'No reviewed submissions yet'
//         : 'No reviews on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}';
//     return Container(
//       padding: const EdgeInsets.all(AppSizes.xl),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(
//           color: widget.isDark
//               ? Colors.white.withValues(alpha: 0.05)
//               : AppColors.textLight.withValues(alpha: 0.2),
//         ),
//       ),
//       child: Column(
//         children: [
//           Icon(LucideIcons.inbox,
//               size: 36,
//               color: widget.isDark ? Colors.white24 : AppColors.textMuted),
//           const SizedBox(height: 8),
//           Text(
//             msg,
//             textAlign: TextAlign.center,
//             style: TextStyle(
//               color: widget.isDark ? Colors.white38 : AppColors.textMuted,
//               fontSize: 14,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// /// Single history card for a reviewed submission.
// class _ReviewHistoryCard extends StatelessWidget {
//   final Map<String, dynamic> data;
//   final String docId;
//   final bool isDark;

//   const _ReviewHistoryCard({
//     required this.data,
//     required this.docId,
//     required this.isDark,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final status = (data['status'] as String?) ?? '';
//     final isApproved = status == 'approved';
//     final workerName = (data['workerName'] as String?) ??
//         (data['userId'] as String?)?.substring(0, 6) ??
//         'Unknown Employee';
//     final taskTitle = (data['taskTitle'] as String?) ??
//         (data['campaignName'] as String?) ??
//         'Task';
//     final reviewedAt = data['reviewedAt'];
//     final reviewedAtDate = reviewedAt is Timestamp
//         ? DateFormat('dd MMM · hh:mm a').format(reviewedAt.toDate())
//         : 'Recently';
//     final rejectionReason = (data['rejectionReason'] as String?) ?? '';

//     final statusColor = isApproved ? AppColors.success : AppColors.error;
//     final statusLabel = isApproved ? 'Approved' : 'Rejected';
//     final statusIcon =
//         isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;

//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(
//           color: isDark
//               ? Colors.white.withValues(alpha: 0.05)
//               : statusColor.withValues(alpha: 0.12),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Status icon
//           Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               color: statusColor.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Icon(statusIcon, color: statusColor, size: 18),
//           ),
//           const SizedBox(width: 12),

//           // Content
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         taskTitle,
//                         style: TextStyle(
//                           color: isDark ? Colors.white : AppColors.textDark,
//                           fontWeight: FontWeight.w700,
//                           fontSize: 14,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     // Status badge
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 8, vertical: 3),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: Text(
//                         statusLabel,
//                         style: TextStyle(
//                           color: statusColor,
//                           fontSize: 11,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   'Employee: $workerName',
//                   style: TextStyle(
//                     color: isDark ? Colors.white54 : AppColors.textBody,
//                     fontSize: 12,
//                   ),
//                 ),
//                 if (!isApproved && rejectionReason.isNotEmpty) ...[
//                   const SizedBox(height: 4),
//                   Text(
//                     'Reason: $rejectionReason',
//                     style: const TextStyle(
//                       color: AppColors.error,
//                       fontSize: 11,
//                       fontStyle: FontStyle.italic,
//                     ),
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ],
//                 const SizedBox(height: 6),
//                 Text(
//                   reviewedAtDate,
//                   style: TextStyle(
//                     color: isDark ? Colors.white24 : AppColors.textMuted,
//                     fontSize: 11,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ─── Data Models ──────────────────────────────────────────────────────────────
// class _PlatformStats {
//   final int totalWorkers;
//   final int pendingKyc;
//   final int activeTasks;
//   final int pendingWithdrawals;

//   const _PlatformStats({
//     required this.totalWorkers,
//     required this.pendingKyc,
//     required this.activeTasks,
//     required this.pendingWithdrawals,
//   });
// }

// class _StatCardData {
//   final IconData icon;
//   final String label;
//   final String value;
//   final Color color;

//   const _StatCardData({
//     required this.icon,
//     required this.label,
//     required this.value,
//     required this.color,
//   });
// }

// // ─── Stat Card ────────────────────────────────────────────────────────────────
// class _StatCard extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String value;
//   final Color color;

//   const _StatCard({
//     required this.icon,
//     required this.label,
//     required this.value,
//     required this.color,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(6),
//             decoration: BoxDecoration(
//               color: color.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(6),
//             ),
//             child: Icon(icon, color: color, size: 20),
//           ),
//           const SizedBox(height: 12),
//           Text(
//             value,
//             style: TextStyle(
//               color: isDark ? Colors.white : AppColors.textDark,
//               fontSize: 20,
//               fontWeight: FontWeight.w800,
//               letterSpacing: 0,
//             ),
//           ),
//           const SizedBox(height: 2),
//           Text(
//             label,
//             style: TextStyle(
//               color: Theme.of(context).colorScheme.onSurfaceVariant,
//               fontSize: 13,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ─── Action Tile ──────────────────────────────────────────────────────────────
// class _ActionTile extends StatelessWidget {
//   final IconData icon;
//   final String title;
//   final String subtitle;
//   final Color color;
//   final VoidCallback onTap;

//   const _ActionTile({
//     required this.icon,
//     required this.title,
//     required this.subtitle,
//     required this.color,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final colors = Theme.of(context).colorScheme;
//     return Material(
//       color: colors.surface,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(8),
//         side: BorderSide(color: colors.outlineVariant),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: InkWell(
//         onTap: onTap,
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: Row(
//             children: [
//               Container(
//                 width: 40,
//                 height: 40,
//                 decoration: BoxDecoration(
//                   color: color.withValues(alpha: 0.1),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Icon(icon, color: color, size: 22),
//               ),
//               const SizedBox(width: 16),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       title,
//                       style: TextStyle(
//                         color: colors.onSurface,
//                         fontWeight: FontWeight.w600,
//                         fontSize: 15,
//                         letterSpacing: 0,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       subtitle,
//                       style: TextStyle(
//                         color: colors.onSurfaceVariant,
//                         fontSize: 13,
//                         letterSpacing: 0,
//                         fontWeight: FontWeight.w400,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Icon(
//                 LucideIcons.chevronRight,
//                 size: 20,
//                 color: colors.onSurfaceVariant,
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ─── KYC History Section ─────────────────────────────────────────────────────
// class _KycHistorySection extends StatelessWidget {
//   final String adminUid;
//   final bool isDark;
//   const _KycHistorySection({required this.adminUid, required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('users')
//           .where('kycReviewedBy', isEqualTo: adminUid)
//           .where('kycStatus', whereIn: ['approved', 'rejected'])
//           .orderBy('kycReviewedAt', descending: true)
//           .limit(20)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return const Center(heightFactor: 2, child: CircularProgressIndicator());
//         }
//         // Fallback without orderBy if index missing
//         if (snap.hasError) {
//           return _KycHistorySectionFallback(adminUid: adminUid, isDark: isDark);
//         }

//         final docs = snap.data?.docs ?? [];
//         if (docs.isEmpty) {
//           return _buildEmpty(context, 'No KYC reviews yet');
//         }

//         return Column(
//           children: docs.map((doc) {
//             final d = (doc.data() as Map<String, dynamic>?) ?? {};
//             return _KycHistoryCard(data: d, isDark: isDark);
//           }).toList(),
//         );
//       },
//     );
//   }

//   Widget _buildEmpty(BuildContext context, String text) => Container(
//         padding: const EdgeInsets.all(AppSizes.xl),
//         decoration: BoxDecoration(
//           color: Theme.of(context).cardColor,
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           border: Border.all(
//             color: isDark
//                 ? Colors.white.withValues(alpha: 0.05)
//                 : AppColors.textLight.withValues(alpha: 0.2),
//           ),
//         ),
//         child: Column(
//           children: [
//             Icon(LucideIcons.inbox,
//                 size: 36,
//                 color: isDark ? Colors.white24 : AppColors.textMuted),
//             const SizedBox(height: 8),
//             Text(text,
//                 style: TextStyle(
//                     color: isDark ? Colors.white38 : AppColors.textMuted,
//                     fontSize: 14)),
//           ],
//         ),
//       );
// }

// class _KycHistorySectionFallback extends StatelessWidget {
//   final String adminUid;
//   final bool isDark;
//   const _KycHistorySectionFallback({required this.adminUid, required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('users')
//           .where('kycReviewedBy', isEqualTo: adminUid)
//           .where('kycStatus', whereIn: ['approved', 'rejected'])
//           .limit(20)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return const Center(heightFactor: 2, child: CircularProgressIndicator());
//         }
//         if (snap.hasError || !(snap.hasData) || snap.data!.docs.isEmpty) {
//           return Padding(
//             padding: const EdgeInsets.all(16),
//             child: Text('No KYC history available.',
//                 style: TextStyle(
//                     color: isDark ? Colors.white38 : AppColors.textMuted)),
//           );
//         }
//         final docs = List.from(snap.data!.docs)
//           ..sort((a, b) {
//             final aT = (a.data() as Map)['kycReviewedAt'];
//             final bT = (b.data() as Map)['kycReviewedAt'];
//             if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
//             return 0;
//           });

//         return Column(
//           children: docs.map((doc) {
//             final d = (doc.data() as Map<String, dynamic>?) ?? {};
//             return _KycHistoryCard(data: d, isDark: isDark);
//           }).toList(),
//         );
//       },
//     );
//   }
// }

// class _KycHistoryCard extends StatelessWidget {
//   final Map<String, dynamic> data;
//   final bool isDark;
//   const _KycHistoryCard({required this.data, required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     final kycStatus = (data['kycStatus'] as String?) ?? '';
//     final isApproved = kycStatus == 'approved';
//     final name = (data['name'] as String?) ?? 'Unknown Employee';
//     final email = (data['email'] as String?) ?? '';
//     final reviewedAt = data['kycReviewedAt'];
//     final reviewedStr = reviewedAt is Timestamp
//         ? DateFormat('dd MMM · hh:mm a').format(reviewedAt.toDate())
//         : 'Recently';
//     final rejectionReason = (data['kycRejectionReason'] as String?) ?? '';

//     final statusColor = isApproved ? AppColors.success : AppColors.error;
//     final statusLabel = isApproved ? 'Approved' : 'Rejected';
//     final statusIcon = isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;

//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(
//           color: isDark
//               ? Colors.white.withValues(alpha: 0.05)
//               : statusColor.withValues(alpha: 0.12),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               color: statusColor.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Icon(statusIcon, color: statusColor, size: 18),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         name,
//                         style: TextStyle(
//                           color: isDark ? Colors.white : AppColors.textDark,
//                           fontWeight: FontWeight.w700,
//                           fontSize: 14,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: Text(
//                         statusLabel,
//                         style: TextStyle(
//                             color: statusColor,
//                             fontSize: 11,
//                             fontWeight: FontWeight.w700),
//                       ),
//                     ),
//                   ],
//                 ),
//                 if (email.isNotEmpty) ...[  
//                   const SizedBox(height: 3),
//                   Text(email,
//                       style: TextStyle(
//                           color: isDark ? Colors.white54 : AppColors.textBody,
//                           fontSize: 12)),
//                 ],
//                 if (!isApproved && rejectionReason.isNotEmpty) ...[  
//                   const SizedBox(height: 4),
//                   Text(
//                     'Reason: $rejectionReason',
//                     style: const TextStyle(
//                         color: AppColors.error,
//                         fontSize: 11,
//                         fontStyle: FontStyle.italic),
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ],
//                 const SizedBox(height: 6),
//                 Text(reviewedStr,
//                     style: TextStyle(
//                         color: isDark ? Colors.white24 : AppColors.textMuted,
//                         fontSize: 11)),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// // ─── Withdrawal History Section ───────────────────────────────────────────────
// class _WithdrawalHistorySection extends StatelessWidget {
//   final bool isDark;
//   const _WithdrawalHistorySection({required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('withdraw_requests')
//           .where('status', whereIn: ['approved', 'rejected'])
//           .orderBy('processedAt', descending: true)
//           .limit(20)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return const Center(heightFactor: 2, child: CircularProgressIndicator());
//         }
//         if (snap.hasError) {
//           return _WithdrawalHistorySectionFallback(isDark: isDark);
//         }

//         final docs = snap.data?.docs ?? [];
//         if (docs.isEmpty) {
//           return _buildEmpty(context, 'No withdrawal decisions yet');
//         }

//         return Column(
//           children: docs.map((doc) {
//             final d = (doc.data() as Map<String, dynamic>?) ?? {};
//             return _WithdrawalHistoryCard(data: d, isDark: isDark);
//           }).toList(),
//         );
//       },
//     );
//   }

//   Widget _buildEmpty(BuildContext context, String text) => Container(
//         padding: const EdgeInsets.all(AppSizes.xl),
//         decoration: BoxDecoration(
//           color: Theme.of(context).cardColor,
//           borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//           border: Border.all(
//             color: isDark
//                 ? Colors.white.withValues(alpha: 0.05)
//                 : AppColors.textLight.withValues(alpha: 0.2),
//           ),
//         ),
//         child: Column(
//           children: [
//             Icon(LucideIcons.inbox,
//                 size: 36,
//                 color: isDark ? Colors.white24 : AppColors.textMuted),
//             const SizedBox(height: 8),
//             Text(text,
//                 style: TextStyle(
//                     color: isDark ? Colors.white38 : AppColors.textMuted,
//                     fontSize: 14)),
//           ],
//         ),
//       );
// }

// class _WithdrawalHistorySectionFallback extends StatelessWidget {
//   final bool isDark;
//   const _WithdrawalHistorySectionFallback({required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<QuerySnapshot>(
//       stream: FirebaseFirestore.instance
//           .collection('withdraw_requests')
//           .where('status', whereIn: ['approved', 'rejected'])
//           .limit(20)
//           .snapshots(),
//       builder: (context, snap) {
//         if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
//           return const Center(heightFactor: 2, child: CircularProgressIndicator());
//         }
//         if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
//           return Padding(
//             padding: const EdgeInsets.all(16),
//             child: Text('No withdrawal history available.',
//                 style: TextStyle(
//                     color: isDark ? Colors.white38 : AppColors.textMuted)),
//           );
//         }
//         final docs = List.from(snap.data!.docs)
//           ..sort((a, b) {
//             final aT = (a.data() as Map)['processedAt'];
//             final bT = (b.data() as Map)['processedAt'];
//             if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
//             return 0;
//           });

//         return Column(
//           children: docs.map((doc) {
//             final d = (doc.data() as Map<String, dynamic>?) ?? {};
//             return _WithdrawalHistoryCard(data: d, isDark: isDark);
//           }).toList(),
//         );
//       },
//     );
//   }
// }

// class _WithdrawalHistoryCard extends StatelessWidget {
//   final Map<String, dynamic> data;
//   final bool isDark;
//   const _WithdrawalHistoryCard({required this.data, required this.isDark});

//   @override
//   Widget build(BuildContext context) {
//     final status = (data['status'] as String?) ?? '';
//     final isApproved = status == 'approved';
//     final workerName = (data['workerName'] as String?) ??
//         (data['userId'] as String?)?.substring(0, 6) ??
//         'Unknown Employee';
//     final amount = data['amount'];
//     final amountStr = amount != null
//         ? '₹${NumberFormat.compact().format(amount)}'
//         : '₹—';
//     final processedAt = data['processedAt'];
//     final processedStr = processedAt is Timestamp
//         ? DateFormat('dd MMM · hh:mm a').format(processedAt.toDate())
//         : 'Recently';
//     final rejectionReason = (data['rejectionReason'] as String?) ?? '';
//     final upiId = (data['upiId'] as String?) ?? '';

//     final statusColor = isApproved ? AppColors.success : AppColors.error;
//     final statusLabel = isApproved ? 'Paid' : 'Rejected';
//     final statusIcon = isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;

//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(
//           color: isDark
//               ? Colors.white.withValues(alpha: 0.05)
//               : statusColor.withValues(alpha: 0.12),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               color: statusColor.withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Icon(statusIcon, color: statusColor, size: 18),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         workerName,
//                         style: TextStyle(
//                           color: isDark ? Colors.white : AppColors.textDark,
//                           fontWeight: FontWeight.w700,
//                           fontSize: 14,
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     // Amount
//                     Text(
//                       amountStr,
//                       style: TextStyle(
//                         color: isApproved ? AppColors.success : AppColors.error,
//                         fontWeight: FontWeight.w800,
//                         fontSize: 15,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 3),
//                 Row(
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                       decoration: BoxDecoration(
//                         color: statusColor.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: Text(
//                         statusLabel,
//                         style: TextStyle(
//                             color: statusColor,
//                             fontSize: 11,
//                             fontWeight: FontWeight.w700),
//                       ),
//                     ),
//                     if (upiId.isNotEmpty) ...[  
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Text(
//                           'UPI: $upiId',
//                           style: TextStyle(
//                               color: isDark ? Colors.white38 : AppColors.textMuted,
//                               fontSize: 11),
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//                 if (!isApproved && rejectionReason.isNotEmpty) ...[  
//                   const SizedBox(height: 4),
//                   Text(
//                     'Reason: $rejectionReason',
//                     style: const TextStyle(
//                         color: AppColors.error,
//                         fontSize: 11,
//                         fontStyle: FontStyle.italic),
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ],
//                 const SizedBox(height: 6),
//                 Text(processedStr,
//                     style: TextStyle(
//                         color: isDark ? Colors.white24 : AppColors.textMuted,
//                         fontSize: 11)),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/constants.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';
 
/// Admin Dashboard Screen — Role-aware, task-reviewer focused.
class AdminDashboardScreen extends StatefulWidget {
  /// The role the admin chose to work as on the role-select screen. When null
  /// (e.g. legacy deep-links), the dashboard falls back to the admin's primary
  /// `role` from their Firestore profile.
  final String? activeRole;
 
  const AdminDashboardScreen({
    super.key,
    this.activeRole,
    this.auth,
    this.firestore,
  });
 
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
 
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}
 
class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  ErrorWidgetBuilder? _originalErrorWidgetBuilder;
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;
 
  @override
  void initState() {
    super.initState();
    // Force-refresh the ID token so freshly-assigned role claims (synced to the
    // auth token by the syncUserClaims trigger) reach the Firestore security
    // rules. This heals sessions that signed in BEFORE a role was granted —
    // without it, per-role queries (task_submissions, users) stay denied until
    // the admin logs out and back in. The Firestore SDK re-runs active
    // listeners automatically once the refreshed token lands.
    _auth.currentUser?.getIdToken(true);
    _originalErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint(
        '⚠️ [AdminDashboard] ErrorWidget caught: ${details.exception}',
      );
      return Container(
        padding: const EdgeInsets.all(AppSizes.md),
        margin: const EdgeInsets.all(AppSizes.sm),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertTriangle,
              size: 16,
              color: AppColors.error,
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Widget error — data loading...',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    };
  }
 
  @override
  void dispose() {
    if (_originalErrorWidgetBuilder != null) {
      ErrorWidget.builder = _originalErrorWidgetBuilder!;
    }
    super.dispose();
  }
 
  /// Human-readable label for each admin role.
  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'task_review_admin':
        return 'Task Reviewer';
      case 'kyc_admin':
        return 'KYC Admin';
      case 'payment_admin':
        return 'Payment Admin';
      case 'support_admin':
        return 'Support Admin';
      case 'admin':
        return 'Admin';
      default:
        return 'Admin';
    }
  }
 
  /// Every role the admin holds (handles legacy single-role docs).
  List<String> _rolesOf(Map<String, dynamic> data) {
    final raw = data['roles'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    final single = data['role']?.toString();
    return single == null ? <String>[] : [single];
  }
 
  /// Support-desk summary: open tickets + active chats.
  Widget _buildSupportAdminStats(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _supportCountCard(
            isDark,
            stream: _firestore
                .collection('support_requests')
                .where('status', whereIn: ['open', 'pending', 'in_progress'])
                .snapshots(),
            label: 'Open Tickets',
            icon: LucideIcons.helpCircle,
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: _supportCountCard(
            isDark,
            stream: _firestore
                .collection('support_chats')
                .where('status', isEqualTo: 'open')
                .snapshots(),
            label: 'Active Chats',
            icon: LucideIcons.messageSquare,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
 
  Widget _supportCountCard(
    bool isDark, {
    required Stream<QuerySnapshot> stream,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return _StatShell(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon, color: color, size: 40, iconSize: 19),
          const SizedBox(height: AppSizes.md),
          StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Text(
                '$count',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
 
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.adminLogin, (_) => false);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
 
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'Admin workspace',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.06),
            ),
            child: IconButton(
              icon: const Icon(LucideIcons.logOut, size: 19),
              tooltip: 'Logout',
              onPressed: () => _handleLogout(context),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
 
          if (snapshot.hasError) {
            return _buildErrorState(
              'Failed to load admin profile',
              onRetry: () => setState(() {}),
            );
          }
 
          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          // Every role the admin actually holds (multi-role support). Falls back
          // to full-admin only when the profile carries no role at all.
          final myRoles = _rolesOf(data);
          final baseRoles = myRoles.isEmpty ? const ['admin'] : myRoles;
          final isSuper =
              baseRoles.contains('admin') || baseRoles.contains('super_admin');
          // A super admin may scope into a single role via the picker; every
          // other admin sees the COMBINED dashboard for all roles they hold, so
          // the screen changes with whatever roles are assigned to them.
          final Set<String> activeRoles = (isSuper && widget.activeRole != null)
              ? {widget.activeRole!}
              : baseRoles.toSet();
          final bool superView =
              activeRoles.contains('admin') ||
              activeRoles.contains('super_admin');
          bool has(String r) => superView || activeRoles.contains(r);
          bool holds(String r) => activeRoles.contains(r);
          final isTaskReviewer = has('task_review_admin');
          final isKycAdmin = has('kyc_admin');
          final isPaymentAdmin = has('payment_admin');
          final isSupportAdmin = has('support_admin');
          final roleLabel = superView
              ? 'Super Admin'
              : activeRoles.map(_roleLabel).join(' \u2022 ');
 
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSizes.sm),
 
                    // ── Welcome Header ──────────────────────────────────────────
                    _buildWelcomeHeader(roleLabel: roleLabel),
                    const SizedBox(height: 28),
 
                    // ── Analytics (role-specific) ───────────────────────────────
                    if (!superView) ...[
                      _buildSectionLabel(context, 'Overview', isDark),
                      const SizedBox(height: AppSizes.md),
                      if (isTaskReviewer)
                        _buildTaskReviewerStats(user.uid, isDark),
                      if (isKycAdmin) ...[
                        if (isTaskReviewer) const SizedBox(height: AppSizes.md),
                        _buildKycAdminStats(isDark),
                      ],
                      if (isPaymentAdmin && !isKycAdmin) ...[
                        if (isTaskReviewer) const SizedBox(height: AppSizes.md),
                        _buildPaymentAdminStats(isDark),
                      ],
                      if (isSupportAdmin) ...[
                        if (isTaskReviewer || isKycAdmin || isPaymentAdmin)
                          const SizedBox(height: AppSizes.md),
                        _buildSupportAdminStats(isDark),
                      ],
                    ],
 
                    const SizedBox(height: 28),
 
                    // ── Administrative Actions ──────────────────────────────────
                    if (isTaskReviewer || isKycAdmin || isPaymentAdmin) ...[
                      _buildSectionLabel(context, 'Reviews & payouts', isDark),
                      const SizedBox(height: AppSizes.md),
                    ],
 
                    if (has('task_review_admin')) ...[
                      _ActionTile(
                        icon: LucideIcons.checkSquare,
                        title: 'Review Task Submissions',
                        subtitle: 'Approve or reject completed tasks',
                        color: AppColors.success,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.adminReview),
                      ),
                      const SizedBox(height: AppSizes.sm),
                    ],
                    if (has('kyc_admin')) ...[
                      _ActionTile(
                        icon: LucideIcons.fileCheck,
                        title: 'Review KYC Submissions',
                        subtitle: 'Approve or reject employee KYC',
                        color: AppColors.warning,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.adminKyc),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _ActionTile(
                        icon: LucideIcons.wallet,
                        title: 'Process Withdrawals',
                        subtitle: 'Approve pending payout requests',
                        color: AppColors.error,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.adminWithdrawals,
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                    ],
                    // Payment admin: payouts only (no KYC access). Skipped when the
                    // admin also holds kyc_admin, since that block already renders it.
                    if (isPaymentAdmin && !isKycAdmin) ...[
                      _ActionTile(
                        icon: LucideIcons.wallet,
                        title: 'Process Withdrawals',
                        subtitle: 'Approve pending payout requests',
                        color: AppColors.error,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.adminWithdrawals,
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                    ],
                    if (superView) ...[
                      const SizedBox(height: 24),
                      _buildSectionLabel(context, 'Platform', isDark),
                      const SizedBox(height: AppSizes.md),
                      _ActionTile(
                        icon: LucideIcons.users,
                        title: 'Manage Users',
                        subtitle: 'Suspend, activate, or view employee activity',
                        color: AppColors.info,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.adminUsers),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _ActionTile(
                        icon: LucideIcons.clipboardList,
                        title: 'Manage Tasks',
                        subtitle: 'Edit, pause, and delete tasks',
                        color: AppColors.primary,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.adminTasks),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _ActionTile(
                        icon: LucideIcons.settings,
                        title: 'Platform Settings',
                        subtitle: 'Configure global system parameters',
                        color: AppColors.primary,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.adminSettings,
                        ),
                      ),
                    ],
 
                    // ── Support Desk (support_admin + full admins) ──────────
                    if (has('support_admin')) ...[
                      const SizedBox(height: 24),
                      _buildSectionLabel(context, 'Support', isDark),
                      const SizedBox(height: AppSizes.md),
                      _ActionTile(
                        icon: LucideIcons.helpCircle,
                        title: 'Support Tickets',
                        subtitle: 'Resolve employee & client tickets',
                        color: AppColors.info,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.adminSupport,
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      _ActionTile(
                        icon: LucideIcons.messageSquare,
                        title: 'Live Chats',
                        subtitle: 'Reply to client conversations',
                        color: AppColors.success,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.adminSupportChats,
                        ),
                      ),
                    ],
 
                    // ── Mail / Inbox (all admin roles) ──────────────────────
                    if (has('support_admin')) ...[
                      const SizedBox(height: AppSizes.sm),
                      _ActionTile(
                        icon: LucideIcons.mail,
                        title: 'Employee Mail',
                        subtitle: 'Threaded messages with employees',
                        color: AppColors.info,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.adminMail),
                      ),
                    ],
 
                    if (superView) ...[
                      const SizedBox(height: 32),
                      _buildSectionLabel(context, 'Review overview', isDark),
                      const SizedBox(height: AppSizes.md),
                      _buildFullAnalyticsStats(isDark),
                      const SizedBox(height: 28),
                      _buildSectionLabel(context, 'Platform overview', isDark),
                      const SizedBox(height: AppSizes.md),
                      _buildPlatformStatsSection(isDark),
                    ],
 
                    // ── Review History (task_review_admin) ──────────────────────
                    if (holds('task_review_admin')) ...[
                      const SizedBox(height: 32),
                      _buildSectionLabel(context, 'Review History', isDark),
                      const SizedBox(height: AppSizes.md),
                      _ReviewHistorySection(adminUid: user.uid, isDark: isDark),
                    ],
 
                    // ── KYC & Withdrawal History (kyc_admin) ────────────────────
                    if (holds('kyc_admin')) ...[
                      const SizedBox(height: 32),
                      _buildSectionLabel(context, 'KYC Review History', isDark),
                      const SizedBox(height: AppSizes.md),
                      _KycHistorySection(adminUid: user.uid, isDark: isDark),
                      const SizedBox(height: 28),
                      _buildSectionLabel(context, 'Withdrawal History', isDark),
                      const SizedBox(height: AppSizes.md),
                      _WithdrawalHistorySection(isDark: isDark),
                    ],
 
                    // ── Withdrawal History (payment_admin) ──────────────────
                    if (holds('payment_admin') && !holds('kyc_admin')) ...[
                      const SizedBox(height: 32),
                      _buildSectionLabel(context, 'Withdrawal History', isDark),
                      const SizedBox(height: AppSizes.md),
                      _WithdrawalHistorySection(isDark: isDark),
                    ],
 
                    const SizedBox(height: AppSizes.xxl),
                    const SizedBox(height: AppSizes.xxxl),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
 
  // ── Section label ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(BuildContext context, String text, bool isDark) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              letterSpacing: 0,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
 
  // ── Welcome Header (now shows role label) ─────────────────────────────────
  Widget _buildWelcomeHeader({required String roleLabel}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.72),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ClipRect(
                child: Align(
                  widthFactor: 0.5,
                  heightFactor: 0.5,
                  alignment: const Alignment(-0.1, -0.4),
                  child: Image.asset(
                    'assets/images/sherize_logo.png',
                    width: 120,
                    height: 120,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sherize',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.shieldCheck,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          roleLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
 
  // ── Task-reviewer-specific analytics (no revenue/KYC) ────────────────────
  Widget _buildTaskReviewerStats(String adminUid, bool isDark) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_submissions')
          // ponytail: single unfiltered read caps at 200 so the shared "Pending"
          // queue and this reviewer's counts share one stream. Fine at current
          // volume; if submissions exceed ~200, split into a pending count() +
          // a reviewedBy==adminUid query so per-reviewer totals stay exact.
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _buildStatsGridLoading();
        }
        if (snap.hasError) {
          return _buildStatsGridError('Failed to load review stats');
        }
 
        final docs = snap.data?.docs ?? [];
        int pending = 0;
        int approvedToday = 0;
        int rejectedToday = 0;
        int totalReviewed = 0;
 
        for (final d in docs) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          final status = (data['status'] as String?) ?? '';
          final reviewedAt = data['reviewedAt'];
          final isToday = reviewedAt is Timestamp &&
              reviewedAt.toDate().isAfter(todayStart);
          // Approved/rejected counts belong to THIS reviewer only. Pending is the
          // shared queue (not yet reviewed by anyone), so it stays global.
          final reviewedByMe = data['reviewedBy'] == adminUid;
 
          if (status == 'pending_admin_review') {
            pending++;
          } else if (status == 'approved' && reviewedByMe) {
            totalReviewed++;
            if (isToday) approvedToday++;
          } else if (status == 'rejected' && reviewedByMe) {
            totalReviewed++;
            if (isToday) rejectedToday++;
          }
        }
 
        return _buildStatsGrid([
          _StatCardData(
            icon: LucideIcons.clock,
            label: 'Pending Reviews',
            value: pending.toString(),
            color: AppColors.warning,
          ),
          _StatCardData(
            icon: LucideIcons.checkCircle,
            label: 'Approved Today',
            value: approvedToday.toString(),
            color: AppColors.success,
          ),
          _StatCardData(
            icon: LucideIcons.xCircle,
            label: 'Rejected Today',
            value: rejectedToday.toString(),
            color: AppColors.error,
          ),
          _StatCardData(
            icon: LucideIcons.clipboardCheck,
            label: 'Total Reviewed',
            value: totalReviewed.toString(),
            color: AppColors.info,
          ),
        ]);
      },
    );
  }
 
  // ── KYC admin analytics (KYC + withdrawals only) ─────────────────────────
  Widget _buildKycAdminStats(bool isDark) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('kycStatus', whereIn: ['pending', 'approved', 'rejected'])
          .limit(200)
          .snapshots(),
      builder: (context, kycSnap) {
        if (kycSnap.connectionState == ConnectionState.waiting &&
            !kycSnap.hasData) {
          return _buildStatsGridLoading();
        }
        if (kycSnap.hasError) {
          return _buildStatsGridError('Failed to load KYC stats');
        }
 
        final kycDocs = kycSnap.data?.docs ?? [];
        int pendingKyc = 0;
        int kycApprovedToday = 0;
        int kycRejectedToday = 0;
 
        for (final d in kycDocs) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          final kycStatus = (data['kycStatus'] as String?) ?? '';
          final reviewedAt = data['kycReviewedAt'];
          final isToday = reviewedAt is Timestamp &&
              reviewedAt.toDate().isAfter(todayStart);
 
          if (kycStatus == 'pending') {
            pendingKyc++;
          } else if (kycStatus == 'approved' && isToday) {
            kycApprovedToday++;
          } else if (kycStatus == 'rejected' && isToday) {
            kycRejectedToday++;
          }
        }
 
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('withdraw_requests')
              .where('status', isEqualTo: 'pending')
              .limit(100)
              .snapshots(),
          builder: (context, withdrawSnap) {
            final pendingWithdrawals = withdrawSnap.data?.docs.length ?? 0;
 
            return _buildStatsGrid([
              _StatCardData(
                icon: LucideIcons.fileCheck,
                label: 'Pending KYC',
                value: pendingKyc.toString(),
                color: AppColors.warning,
              ),
              _StatCardData(
                icon: LucideIcons.checkCircle,
                label: 'KYC Approved Today',
                value: kycApprovedToday.toString(),
                color: AppColors.success,
              ),
              _StatCardData(
                icon: LucideIcons.xCircle,
                label: 'KYC Rejected Today',
                value: kycRejectedToday.toString(),
                color: AppColors.error,
              ),
              _StatCardData(
                icon: LucideIcons.wallet,
                label: 'Pending Withdrawals',
                value: pendingWithdrawals.toString(),
                color: AppColors.info,
              ),
            ]);
          },
        );
      },
    );
  }
 
  // ── Payment admin analytics (payouts only) ───────────────────────────────
  // Reads ONLY withdraw_requests + payout_history, both permitted for
  // payment_admin via isAdmin(). Avoids the super-admin-only users list and the
  // task_submissions collection (task-admins only), which is why the generic
  // full-admin dashboard failed to load for this role.
  Widget _buildPaymentAdminStats(bool isDark) {
    final currency =
        NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0);
 
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdraw_requests')
          .where('status', isEqualTo: 'pending')
          .limit(200)
          .snapshots(),
      builder: (context, pendingSnap) {
        if (pendingSnap.connectionState == ConnectionState.waiting &&
            !pendingSnap.hasData) {
          return _buildStatsGridLoading();
        }
        if (pendingSnap.hasError) {
          return _buildStatsGridError('Failed to load payout stats');
        }
 
        final pendingDocs = pendingSnap.data?.docs ?? [];
        num pendingAmount = 0;
        for (final d in pendingDocs) {
          final data = (d.data() as Map<String, dynamic>?) ?? {};
          pendingAmount += (data['amount'] as num?) ?? 0;
        }
 
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('payout_history')
              .limit(100)
              .snapshots(),
          builder: (context, payoutSnap) {
            final processedCount = payoutSnap.data?.docs.length ?? 0;
 
            return _buildStatsGrid([
              _StatCardData(
                icon: LucideIcons.wallet,
                label: 'Pending Withdrawals',
                value: pendingDocs.length.toString(),
                color: AppColors.warning,
              ),
              _StatCardData(
                icon: LucideIcons.indianRupee,
                label: 'Pending Amount',
                value: currency.format(pendingAmount),
                color: AppColors.error,
              ),
              _StatCardData(
                icon: LucideIcons.checkCircle,
                label: 'Payouts Processed',
                value: processedCount.toString(),
                color: AppColors.success,
              ),
            ]);
          },
        );
      },
    );
  }
 
  // ── Full analytics (super_admin / admin) ─────────────────────────────────
  Widget _buildFullAnalyticsStats(bool isDark) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
 
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('task_submissions').limit(100).snapshots(),
      builder: (context, submissionsSnap) {
        if (submissionsSnap.connectionState == ConnectionState.waiting &&
            !submissionsSnap.hasData) {
          return _buildStatsGridLoading();
        }
        if (submissionsSnap.hasError) {
          return _buildStatsGridError('Failed to load review stats');
        }
 
        final docs = submissionsSnap.data?.docs ?? [];
        int pendingCount = 0;
        int approvedToday = 0;
 
        for (final doc in docs) {
          final d = (doc.data() as Map<String, dynamic>?) ?? {};
          final status = (d['status'] as String?) ?? '';
          if (status == 'pending_admin_review') {
            pendingCount++;
          } else if (status == 'approved') {
            final reviewedAt = d['reviewedAt'];
            if (reviewedAt is Timestamp &&
                reviewedAt.toDate().isAfter(todayStart)) {
              approvedToday++;
            }
          }
        }
 
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('platform_earnings')
              .doc('global')
              .snapshots(),
          builder: (context, earningsSnap) {
            final eData =
                earningsSnap.data?.data() as Map<String, dynamic>? ?? {};
            final totalRevenue =
                NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
                    .format(eData['totalRevenue'] ?? 0);
            final netProfit =
                NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0)
                    .format(eData['netProfit'] ?? 0);
 
            return _buildStatsGrid([
              _StatCardData(
                icon: LucideIcons.clock,
                label: 'Pending Reviews',
                value: pendingCount.toString(),
                color: AppColors.warning,
              ),
              _StatCardData(
                icon: LucideIcons.checkCircle,
                label: 'Approved Today',
                value: approvedToday.toString(),
                color: AppColors.success,
              ),
              _StatCardData(
                icon: LucideIcons.trendingUp,
                label: 'Gross Revenue',
                value: totalRevenue,
                color: AppColors.success,
              ),
              _StatCardData(
                icon: LucideIcons.award,
                label: 'Net Profits',
                value: netProfit,
                color: AppColors.accent,
              ),
            ]);
          },
        );
      },
    );
  }
 
  // ── Platform stats (workers / KYC / payouts) ─────────────────────────────
  Widget _buildPlatformStatsSection(bool isDark) {
    return FutureBuilder<_PlatformStats>(
      future: _fetchPlatformStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildStatsGridLoading();
        }
 
        if (snapshot.hasError) {
          return _buildStatsGridError('Failed to load platform stats');
        }
 
        final stats = snapshot.data;
        if (stats == null) {
          return _buildEmptyStatsState('No platform data available');
        }
 
        return _buildStatsGrid([
          _StatCardData(
            icon: LucideIcons.users,
            label: 'Total Employees',
            value: stats.totalWorkers.toString(),
            color: AppColors.info,
          ),
          _StatCardData(
            icon: LucideIcons.fileCheck,
            label: 'Pending KYC',
            value: stats.pendingKyc.toString(),
            color: AppColors.warning,
          ),
          _StatCardData(
            icon: LucideIcons.clipboardList,
            label: 'Active Tasks',
            value: stats.activeTasks.toString(),
            color: AppColors.success,
          ),
          _StatCardData(
            icon: LucideIcons.wallet,
            label: 'Pending Payouts',
            value: stats.pendingWithdrawals.toString(),
            color: AppColors.error,
          ),
        ]);
      },
    );
  }
 
  Future<_PlatformStats> _fetchPlatformStats() async {
    try {
      final results = await Future.wait([
        _firestore
            .collection('users')
            .where('role', isEqualTo: 'worker')
            .limit(100)
            .get(),
        _firestore
            .collection('users')
            .where('kycStatus', isEqualTo: 'pending')
            .limit(100)
            .get(),
        _firestore
            .collection('tasks')
            .where('status', isEqualTo: 'active')
            .limit(100)
            .get(),
        _firestore
            .collection('withdraw_requests')
            .where('status', isEqualTo: 'pending')
            .limit(100)
            .get(),
      ]);
 
      return _PlatformStats(
        totalWorkers: results[0].docs.length,
        pendingKyc: results[1].docs.length,
        activeTasks: results[2].docs.length,
        pendingWithdrawals: results[3].docs.length,
      );
    } catch (e) {
      debugPrint('❌ [AdminDashboard] _fetchPlatformStats error: $e');
      rethrow;
    }
  }
 
  // ── Grid helpers ──────────────────────────────────────────────────────────
  Widget _buildStatsGrid(List<_StatCardData> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = constraints.maxWidth >= 700 && !largeText
            ? 4
            : constraints.maxWidth >= 340 && !largeText
            ? 2
            : 1;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _StatCard(
                    icon: item.icon,
                    label: item.label,
                    value: item.value,
                    color: item.color,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
 
  Widget _buildStatsGridLoading() {
    return const SizedBox(
        height: 120, child: Center(child: CircularProgressIndicator()));
  }
 
  Widget _buildStatsGridError(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.xl),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertTriangle,
              size: 30, color: AppColors.error),
          const SizedBox(height: AppSizes.sm),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600)),
          TextButton(
              onPressed: () => setState(() {}), child: const Text('Retry')),
        ],
      ),
    );
  }
 
  Widget _buildEmptyStatsState(String message) {
    return Center(child: Text(message));
  }
 
  Widget _buildErrorState(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withValues(alpha: 0.1),
            ),
            child: const Icon(LucideIcons.alertTriangle,
                size: 38, color: AppColors.error),
          ),
          const SizedBox(height: AppSizes.md),
          Text(message,
              style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 15)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
 
  // ── Logout ────────────────────────────────────────────────────────────────
  void _handleLogout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(LucideIcons.logOut,
                  size: 18, color: AppColors.error),
            ),
            const SizedBox(width: 12),
            Text('Logout',
                style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to logout from the admin panel?',
          style: TextStyle(color: isDark ? Colors.white70 : AppColors.textBody),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                      color: isDark ? Colors.white38 : AppColors.textMuted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await Provider.of<AuthService>(context, listen: false).logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.adminLogin, (route) => false);
              }
            },
            child: const Text('Logout',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
 
// ─── Shared UI building blocks ────────────────────────────────────────────────
 
/// Rounded gradient icon tile used by stat cards and action tiles.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
 
  const _IconTile({
    required this.icon,
    required this.color,
    this.size = 42,
    this.iconSize = 20,
  });
 
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
 
/// Card shell for stat tiles: rounded, bordered, with a soft decorative glow.
class _StatShell extends StatelessWidget {
  final Color color;
  final Widget child;
 
  const _StatShell({required this.color, required this.child});
 
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -22,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}
 
/// Friendly empty-state card.
class _EmptyState extends StatelessWidget {
  final String text;
  final bool isDark;
 
  const _EmptyState({required this.text, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.xl, vertical: AppSizes.xl),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.textLight.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDark ? Colors.white : AppColors.textMuted)
                  .withValues(alpha: 0.08),
            ),
            child: Icon(LucideIcons.inbox,
                size: 28,
                color: isDark ? Colors.white30 : AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white54 : AppColors.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
 
/// Small coloured pill (status badges).
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
 
  const _Pill({required this.label, required this.color});
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
 
/// Shared shell for history cards: status-coloured accent strip + icon tile.
class _HistoryCardShell extends StatelessWidget {
  final Color statusColor;
  final IconData statusIcon;
  final bool isDark;
  final Widget child;
 
  const _HistoryCardShell({
    required this.statusColor,
    required this.statusIcon,
    required this.isDark,
    required this.child,
  });
 
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : statusColor.withValues(alpha: 0.14),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: statusColor.withValues(alpha: 0.85)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconTile(
                        icon: statusIcon,
                        color: statusColor,
                        size: 38,
                        iconSize: 18),
                    const SizedBox(width: 12),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
// ─── Review History Section ───────────────────────────────────────────────────
// Shows ONLY the submissions the signed-in admin personally reviewed
// (reviewedBy == their uid), newest first, with an optional single-day filter.
class _ReviewHistorySection extends StatefulWidget {
  final String adminUid;
  final bool isDark;
 
  const _ReviewHistorySection({
    required this.adminUid,
    required this.isDark,
  });
 
  @override
  State<_ReviewHistorySection> createState() => _ReviewHistorySectionState();
}
 
class _ReviewHistorySectionState extends State<_ReviewHistorySection> {
  // When set, only reviews made on this calendar day are shown.
  // Defaults to today; the clear (×) button switches back to all dates.
  DateTime? _selectedDate = DateTime.now();
 
  // Base query: this admin's reviews only. `reviewedBy` is written on both the
  // approve and reject paths, so it attributes every reviewed submission.
  // Optionally narrowed to a single day; always newest first.
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('task_submissions')
        .where('reviewedBy', isEqualTo: widget.adminUid);
 
    if (_selectedDate != null) {
      final start = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final end = start.add(const Duration(days: 1));
      q = q
          .where('reviewedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('reviewedAt', isLessThan: Timestamp.fromDate(end));
    }
 
    return q.orderBy('reviewedAt', descending: true).limit(50);
  }
 
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }
 
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(context),
        const SizedBox(height: 14),
        StreamBuilder<QuerySnapshot>(
          stream: _buildQuery().snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(
                  heightFactor: 2, child: CircularProgressIndicator());
            }
            // Missing composite index (or transient error) → index-free fallback.
            if (snap.hasError) {
              return _buildFallback(context);
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _buildEmptyHistory(context);
            return _buildList(docs);
          },
        ),
      ],
    );
  }
 
  // Fallback avoids the composite index: filter by reviewedBy only (single-field,
  // no index needed), then apply the date filter + sort on the client.
  Widget _buildFallback(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_submissions')
          .where('reviewedBy', isEqualTo: widget.adminUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              heightFactor: 2, child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return _buildEmptyHistory(context);
        }
        final filtered = snap.data!.docs.where((d) {
          if (_selectedDate == null) return true;
          final at = (d.data() as Map)['reviewedAt'];
          if (at is! Timestamp) return false;
          final dt = at.toDate();
          return dt.year == _selectedDate!.year &&
              dt.month == _selectedDate!.month &&
              dt.day == _selectedDate!.day;
        }).toList()
          ..sort((a, b) {
            final aAt = (a.data() as Map)['reviewedAt'];
            final bAt = (b.data() as Map)['reviewedAt'];
            if (aAt is Timestamp && bAt is Timestamp) return bAt.compareTo(aAt);
            return 0;
          });
        if (filtered.isEmpty) return _buildEmptyHistory(context);
        return _buildList(filtered.take(50).toList());
      },
    );
  }
 
  Widget _buildList(List<QueryDocumentSnapshot> docs) {
    return Column(
      children: docs.map((doc) {
        final d = (doc.data() as Map<String, dynamic>?) ?? {};
        return _ReviewHistoryCard(
            data: d, docId: doc.id, isDark: widget.isDark);
      }).toList(),
    );
  }
 
  Widget _buildFilterBar(BuildContext context) {
    final hasDate = _selectedDate != null;
    final label =
        hasDate ? DateFormat('dd MMM yyyy').format(_selectedDate!) : 'All dates';
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Theme.of(context).cardColor,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: hasDate
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : (widget.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.textLight.withValues(alpha: 0.3)),
              ),
            ),
            child: InkWell(
              onTap: _pickDate,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(LucideIcons.calendar,
                          size: 15, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              widget.isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                    Icon(LucideIcons.chevronDown,
                        size: 16,
                        color: widget.isDark
                            ? Colors.white38
                            : AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasDate) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setState(() => _selectedDate = null),
            icon: const Icon(LucideIcons.x, size: 18),
            tooltip: 'Clear date',
            color: widget.isDark ? Colors.white54 : AppColors.textMuted,
            style: IconButton.styleFrom(
              backgroundColor: (widget.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.06),
            ),
          ),
        ],
      ],
    );
  }
 
  Widget _buildEmptyHistory(BuildContext context) {
    final msg = _selectedDate == null
        ? 'No reviewed submissions yet'
        : 'No reviews on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}';
    return _EmptyState(text: msg, isDark: widget.isDark);
  }
}
 
/// Single history card for a reviewed submission.
class _ReviewHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isDark;
 
  const _ReviewHistoryCard({
    required this.data,
    required this.docId,
    required this.isDark,
  });
 
  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? '';
    final isApproved = status == 'approved';
    final workerName = (data['workerName'] as String?) ??
        (data['userId'] as String?)?.substring(0, 6) ??
        'Unknown Employee';
    final taskTitle = (data['taskTitle'] as String?) ??
        (data['campaignName'] as String?) ??
        'Task';
    final reviewedAt = data['reviewedAt'];
    final reviewedAtDate = reviewedAt is Timestamp
        ? DateFormat('dd MMM · hh:mm a').format(reviewedAt.toDate())
        : 'Recently';
    final rejectionReason = (data['rejectionReason'] as String?) ?? '';
 
    final statusColor = isApproved ? AppColors.success : AppColors.error;
    final statusLabel = isApproved ? 'Approved' : 'Rejected';
    final statusIcon =
        isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;
 
    return _HistoryCardShell(
      statusColor: statusColor,
      statusIcon: statusIcon,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  taskTitle,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Employee: $workerName',
            style: TextStyle(
              color: isDark ? Colors.white60 : AppColors.textBody,
              fontSize: 12.5,
            ),
          ),
          if (!isApproved && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $rejectionReason',
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.clock,
                  size: 11,
                  color: isDark ? Colors.white30 : AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                reviewedAtDate,
                style: TextStyle(
                  color: isDark ? Colors.white38 : AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
 
// ─── Data Models ──────────────────────────────────────────────────────────────
class _PlatformStats {
  final int totalWorkers;
  final int pendingKyc;
  final int activeTasks;
  final int pendingWithdrawals;
 
  const _PlatformStats({
    required this.totalWorkers,
    required this.pendingKyc,
    required this.activeTasks,
    required this.pendingWithdrawals,
  });
}
 
class _StatCardData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
 
  const _StatCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
 
// ─── Stat Card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
 
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _StatShell(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _IconTile(icon: icon, color: color, size: 40, iconSize: 19),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
 
// ─── Action Tile ──────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
 
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
 
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.08),
        highlightColor: color.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _IconTile(icon: icon, color: color, size: 46, iconSize: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.3,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
 
// ─── KYC History Section ─────────────────────────────────────────────────────
class _KycHistorySection extends StatelessWidget {
  final String adminUid;
  final bool isDark;
  const _KycHistorySection({required this.adminUid, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('kycReviewedBy', isEqualTo: adminUid)
          .where('kycStatus', whereIn: ['approved', 'rejected'])
          .orderBy('kycReviewedAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              heightFactor: 2, child: CircularProgressIndicator());
        }
        // Fallback without orderBy if index missing
        if (snap.hasError) {
          return _KycHistorySectionFallback(adminUid: adminUid, isDark: isDark);
        }
 
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmpty(context, 'No KYC reviews yet');
        }
 
        return Column(
          children: docs.map((doc) {
            final d = (doc.data() as Map<String, dynamic>?) ?? {};
            return _KycHistoryCard(data: d, isDark: isDark);
          }).toList(),
        );
      },
    );
  }
 
  Widget _buildEmpty(BuildContext context, String text) =>
      _EmptyState(text: text, isDark: isDark);
}
 
class _KycHistorySectionFallback extends StatelessWidget {
  final String adminUid;
  final bool isDark;
  const _KycHistorySectionFallback(
      {required this.adminUid, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('kycReviewedBy', isEqualTo: adminUid)
          .where('kycStatus', whereIn: ['approved', 'rejected'])
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              heightFactor: 2, child: CircularProgressIndicator());
        }
        if (snap.hasError || !(snap.hasData) || snap.data!.docs.isEmpty) {
          return _EmptyState(text: 'No KYC history available.', isDark: isDark);
        }
        final docs = List.from(snap.data!.docs)
          ..sort((a, b) {
            final aT = (a.data() as Map)['kycReviewedAt'];
            final bT = (b.data() as Map)['kycReviewedAt'];
            if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
            return 0;
          });
 
        return Column(
          children: docs.map((doc) {
            final d = (doc.data() as Map<String, dynamic>?) ?? {};
            return _KycHistoryCard(data: d, isDark: isDark);
          }).toList(),
        );
      },
    );
  }
}
 
class _KycHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  const _KycHistoryCard({required this.data, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    final kycStatus = (data['kycStatus'] as String?) ?? '';
    final isApproved = kycStatus == 'approved';
    final name = (data['name'] as String?) ?? 'Unknown Employee';
    final email = (data['email'] as String?) ?? '';
    final reviewedAt = data['kycReviewedAt'];
    final reviewedStr = reviewedAt is Timestamp
        ? DateFormat('dd MMM · hh:mm a').format(reviewedAt.toDate())
        : 'Recently';
    final rejectionReason = (data['kycRejectionReason'] as String?) ?? '';
 
    final statusColor = isApproved ? AppColors.success : AppColors.error;
    final statusLabel = isApproved ? 'Approved' : 'Rejected';
    final statusIcon =
        isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;
 
    return _HistoryCardShell(
      statusColor: statusColor,
      statusIcon: statusIcon,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: statusLabel, color: statusColor),
            ],
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(email,
                style: TextStyle(
                    color: isDark ? Colors.white60 : AppColors.textBody,
                    fontSize: 12.5)),
          ],
          if (!isApproved && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $rejectionReason',
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.clock,
                  size: 11,
                  color: isDark ? Colors.white30 : AppColors.textMuted),
              const SizedBox(width: 4),
              Text(reviewedStr,
                  style: TextStyle(
                      color: isDark ? Colors.white38 : AppColors.textMuted,
                      fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}
 
// ─── Withdrawal History Section ───────────────────────────────────────────────
class _WithdrawalHistorySection extends StatelessWidget {
  final bool isDark;
  const _WithdrawalHistorySection({required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdraw_requests')
          .where('status', whereIn: ['approved', 'rejected'])
          .orderBy('processedAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              heightFactor: 2, child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _WithdrawalHistorySectionFallback(isDark: isDark);
        }
 
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmpty(context, 'No withdrawal decisions yet');
        }
 
        return Column(
          children: docs.map((doc) {
            final d = (doc.data() as Map<String, dynamic>?) ?? {};
            return _WithdrawalHistoryCard(data: d, isDark: isDark);
          }).toList(),
        );
      },
    );
  }
 
  Widget _buildEmpty(BuildContext context, String text) =>
      _EmptyState(text: text, isDark: isDark);
}
 
class _WithdrawalHistorySectionFallback extends StatelessWidget {
  final bool isDark;
  const _WithdrawalHistorySectionFallback({required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdraw_requests')
          .where('status', whereIn: ['approved', 'rejected'])
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              heightFactor: 2, child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
          return _EmptyState(
              text: 'No withdrawal history available.', isDark: isDark);
        }
        final docs = List.from(snap.data!.docs)
          ..sort((a, b) {
            final aT = (a.data() as Map)['processedAt'];
            final bT = (b.data() as Map)['processedAt'];
            if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
            return 0;
          });
 
        return Column(
          children: docs.map((doc) {
            final d = (doc.data() as Map<String, dynamic>?) ?? {};
            return _WithdrawalHistoryCard(data: d, isDark: isDark);
          }).toList(),
        );
      },
    );
  }
}
 
class _WithdrawalHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  const _WithdrawalHistoryCard({required this.data, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? '';
    final isApproved = status == 'approved';
    final workerName = (data['workerName'] as String?) ??
        (data['userId'] as String?)?.substring(0, 6) ??
        'Unknown Employee';
    final amount = data['amount'];
    final amountStr =
        amount != null ? '₹${NumberFormat.compact().format(amount)}' : '₹—';
    final processedAt = data['processedAt'];
    final processedStr = processedAt is Timestamp
        ? DateFormat('dd MMM · hh:mm a').format(processedAt.toDate())
        : 'Recently';
    final rejectionReason = (data['rejectionReason'] as String?) ?? '';
    final upiId = (data['upiId'] as String?) ?? '';
 
    final statusColor = isApproved ? AppColors.success : AppColors.error;
    final statusLabel = isApproved ? 'Paid' : 'Rejected';
    final statusIcon =
        isApproved ? LucideIcons.checkCircle2 : LucideIcons.xCircle;
 
    return _HistoryCardShell(
      statusColor: statusColor,
      statusIcon: statusIcon,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workerName,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Amount
              Text(
                amountStr,
                style: TextStyle(
                  color: isApproved ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Pill(label: statusLabel, color: statusColor),
              if (upiId.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'UPI: $upiId',
                    style: TextStyle(
                        color: isDark ? Colors.white54 : AppColors.textMuted,
                        fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (!isApproved && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $rejectionReason',
              style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.clock,
                  size: 11,
                  color: isDark ? Colors.white30 : AppColors.textMuted),
              const SizedBox(width: 4),
              Text(processedStr,
                  style: TextStyle(
                      color: isDark ? Colors.white38 : AppColors.textMuted,
                      fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }
}