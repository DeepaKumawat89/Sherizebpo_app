import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../routes.dart';
import '../../services/platform_settings_service.dart';
import '../../services/mail_service.dart';
import '../jobs/applicant_home_screen.dart';
import '../../widgets/earnings_card.dart';
import '../../widgets/task_summary_card.dart';
import '../../widgets/onboarding_checklist_card.dart';
import '../../widgets/shimmer_box.dart';
import '../profile/profile_screen.dart';
import '../tasks/task_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key, this.initialTab = 0})
      : assert(initialTab >= 0 && initialTab < 3),
        super(key: key);

  final int initialTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late int _currentTab;
  late final List<bool> _visitedTabs;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _visitedTabs = List<bool>.generate(3, (index) => index == _currentTab);
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    if (_currentTab == 0) _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _visitedTabs[0]
              ? FadeTransition(
                  opacity: _fadeAnim,
                  child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _buildLoadingSkeleton();
            }

            final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

            // New joiners who haven't been hired yet only see job openings —
            // the task marketplace stays locked until onboardingStatus=='active'.
            if ((data['onboardingStatus'] ?? '').toString() == 'applicant') {
              return const ApplicantHomeScreen();
            }

            final userName = data['fullName'] ?? data['name'] ?? 'Employee';
            final firstName = userName.toString().split(' ').first;

            final settings = context.watch<PlatformSettingsService>();

            return CustomScrollView(
              slivers: [
                // ── Custom App Bar ───────────────────────────────
                _buildAppBar(context, firstName, data, isDark),

                // ── Dashboard Content ────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPaddingH,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: AppSizes.lg),
                      
                      // ── Global Announcement Banner ──
                      if (settings.announcement.trim().isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: AppSizes.lg),
                          padding: const EdgeInsets.all(AppSizes.md),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.primary.withValues(alpha: 0.12) : AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                            border: Border.all(
                              color: isDark 
                                ? AppColors.primary.withValues(alpha: 0.25)
                                : AppColors.primaryMuted.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(LucideIcons.megaphone, color: AppColors.primary, size: 20),
                              const SizedBox(width: AppSizes.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Announcement',
                                      style: TextStyle(
                                        color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      settings.announcement,
                                      style: TextStyle(
                                        color: isDark ? Colors.white.withValues(alpha: 0.9) : AppColors.textDark,
                                        height: 1.4,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // ── Earnings Card ──
                      if (settings.earningsSystemEnabled) ...[
                        _buildEarningsSection(data, user.uid),
                        const SizedBox(height: AppSizes.xl),
                      ],

                      // ── Onboarding Checklist ──
                      _buildOnboardingIfNeeded(data),

                      // ── Task Summary ──
                      _buildTaskSummary(user.uid),
                      const SizedBox(height: AppSizes.xl),

                      // ── Quick Actions ──
                      _buildQuickActions(context, data, isDark, settings.earningsSystemEnabled),
                      const SizedBox(height: AppSizes.xxxl),

                      const SizedBox(height: AppSizes.xxxl),
                    ]),
                  ),
                ),
              ],
            );
          },
                  ),
                )
              : const SizedBox.shrink(),
          _visitedTabs[1]
              ? const TaskListScreen()
              : const SizedBox.shrink(),
          _visitedTabs[2]
              ? const ProfileScreen()
              : const SizedBox.shrink(),
        ],
      ),

      // ── Bottom Nav ──────────────────────────────────────────
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // APP BAR
  // ═══════════════════════════════════════════════════════════
  Widget _buildAppBar(
      BuildContext context, String firstName, Map<String, dynamic> data, bool isDark) {
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetIcon;
    if (hour < 12) {
      greeting = 'Good Morning';
      greetIcon = LucideIcons.sunrise;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      greetIcon = LucideIcons.sun;
    } else {
      greeting = 'Good Evening';
      greetIcon = LucideIcons.sunset;
    }

    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U';

    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + AppSizes.md,
            left: AppSizes.screenPaddingH,
            right: AppSizes.screenPaddingH,
            bottom: AppSizes.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: () => _selectTab(2),
                    child: _buildAvatar(initial, data),
                  ),
                  const Spacer(),
                  // Inbox / Mail
                  _buildMailIconButton(context),
                  const SizedBox(width: AppSizes.sm),
                  // Notification Bell
                  _buildIconButton(
                    context: context,
                    icon: LucideIcons.bell,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.notifications),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  // Settings
                  _buildIconButton(
                    context: context,
                    icon: LucideIcons.settings,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.settings),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              Row(
                children: [
                  Icon(greetIcon, size: 18, color: AppColors.accent),
                  const SizedBox(width: AppSizes.sm),
                  Text(
                    greeting,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white54 : AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                firstName,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String initial, Map<String, dynamic> data) {
    final profileUrl = data['profileImage'] ??
        data['profileImageUrl'] ??
        data['avatar_url'] ??
        '';

    return Container(
      width: AppSizes.avatarMd,
      height: AppSizes.avatarMd,
      decoration: BoxDecoration(
        gradient: AppDecorations.primaryLightGradient,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).cardColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: profileUrl.toString().isNotEmpty
          ? ClipOval(
              child: Image.network(
                profileUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
    );
  }

  Widget _buildIconButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
    bool hasBadge = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
          boxShadow: isDark ? null : AppDecorations.shadowSm,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20, color: isDark ? Colors.white70 : AppColors.textBody),
            if (hasBadge)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Mail icon (worker inbox) with a live unread badge.
  Widget _buildMailIconButton(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _buildIconButton(
        context: context,
        icon: LucideIcons.mail,
        onTap: () => Navigator.pushNamed(context, AppRoutes.inbox),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: MailService().myThreads(uid),
      builder: (context, snap) {
        var hasUnread = false;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (MailService.isUnreadFor(uid, data)) {
              hasUnread = true;
              break;
            }
          }
        }
        return _buildIconButton(
          context: context,
          icon: LucideIcons.mail,
          hasBadge: hasUnread,
          onTap: () => Navigator.pushNamed(context, AppRoutes.inbox),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // EARNINGS SECTION
  // ═══════════════════════════════════════════════════════════
  Widget _buildEarningsSection(Map<String, dynamic> data, String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('worker_wallets')
          .doc(uid)
          .snapshots(),
      builder: (context, walletSnap) {
        double totalEarned = 0;
        if (walletSnap.hasData && walletSnap.data!.exists) {
          final walletData = walletSnap.data!.data() as Map<String, dynamic>;
          totalEarned = (walletData['balance'] ?? 0.0).toDouble();
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('earnings_pending')
              .where('userId', isEqualTo: uid)
              .where('status', isEqualTo: 'pending_admin_approval')
              .limit(30)
              .snapshots(),
          builder: (context, pendingSnap) {
            double pendingAmount = 0;
            if (pendingSnap.hasData) {
              for (var doc in pendingSnap.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                pendingAmount += (d['payout'] ?? 0).toDouble();
              }
            }

            return EarningsCard(
              totalEarned: totalEarned,
              pendingAmount: pendingAmount,
              onWithdraw: () => Navigator.pushNamed(context, AppRoutes.earnings),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ONBOARDING
  // ═══════════════════════════════════════════════════════════
  Widget _buildOnboardingIfNeeded(Map<String, dynamic> data) {
    final kycStatus = (data['kycStatus'] ?? data['kyc_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final profileComplete = (data['fullName'] ?? '').toString().isNotEmpty &&
        (data['phone'] ?? data['phoneNumber'] ?? '').toString().isNotEmpty;
    final kycDone = kycStatus == 'approved' || kycStatus == 'verified';
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_submissions')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final taskDone = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        if (profileComplete && kycDone && taskDone) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.xl),
          child: OnboardingChecklistCard(
            isProfileComplete: profileComplete,
            isKycDone: kycDone,
            isFirstTaskDone: taskDone,
            onCompleteProfile: () =>
                Navigator.pushNamed(context, AppRoutes.editProfile),
            onCompleteKyc: () => Navigator.pushNamed(context, AppRoutes.kyc),
            onStartTask: () => _selectTab(1),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TASK SUMMARY
  // ═══════════════════════════════════════════════════════════
  Widget _buildTaskSummary(String uid) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('task_assignments')
          .where('userId', isEqualTo: uid)
          .limit(50)
          .get(),
      builder: (context, snap) {
        int active = 0, pending = 0, done = 0;
        if (snap.hasData) {
          for (var doc in snap.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final status = (d['status'] ?? '').toString().toLowerCase();
            if (status == 'in_progress' || status == 'accepted') {
              active++;
            } else if (status == 'pending' ||
                status == 'pending_admin_review') {
              pending++;
            } else if (status == 'completed' || status == 'approved') {
              done++;
            }
          }
        }

        return TaskSummaryCard(
          activeTasks: active,
          pendingTasks: pending,
          completedTasks: done,
          onViewAll: () => _selectTab(1),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // QUICK ACTIONS
  // ═══════════════════════════════════════════════════════════
  Widget _buildQuickActions(BuildContext context, Map<String, dynamic> data,
      bool isDark, bool earningsEnabled) {
    // Build the action cards, omitting "Earnings" when the earnings system is
    // disabled, then lay them out two-per-row (a lone trailing card keeps its
    // half-width via a Spacer so the grid stays aligned).
    final cards = <Widget>[
      _QuickActionCard(
        icon: LucideIcons.phoneCall,
        label: 'Find Tasks',
        subtitle: 'Browse marketplace',
        gradient: AppDecorations.primaryGradient,
        onTap: () => _selectTab(1),
      ),
      if (earningsEnabled)
        _QuickActionCard(
          icon: LucideIcons.wallet,
          label: 'Earnings',
          subtitle: 'View balance',
          gradient: AppDecorations.accentGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.earnings),
        ),
      _QuickActionCard(
        icon: LucideIcons.shieldCheck,
        label: 'KYC',
        subtitle: 'Verify identity',
        gradient: AppDecorations.warmGradient,
        onTap: () => Navigator.pushNamed(context, AppRoutes.kyc),
      ),
      _QuickActionCard(
        icon: LucideIcons.helpCircle,
        label: 'Help',
        subtitle: 'Get support',
        gradient: AppDecorations.violetGradient,
        onTap: () => Navigator.pushNamed(context, AppRoutes.help),
      ),
    ];

    final rows = <Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSizes.md));
      rows.add(Row(
        children: [
          Expanded(child: cards[i]),
          const SizedBox(width: AppSizes.md),
          if (i + 1 < cards.length)
            Expanded(child: cards[i + 1])
          else
            const Spacer(),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: isDark ? Colors.white : AppColors.textDark,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSizes.md),
        ...rows,
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BOTTOM NAV
  // ═══════════════════════════════════════════════════════════
  void _selectTab(int index) {
    if (index == _currentTab) return;
    setState(() {
      _currentTab = index;
      _visitedTabs[index] = true;
      if (index == 0 && _fadeCtrl.value == 0) {
        _fadeCtrl.forward();
      }
    });
  }

  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusRound),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(
                alpha: isDark ? 0.28 : 0.12,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusRound),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surface.withValues(alpha: isDark ? 0.80 : 0.86),
                borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.88),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Row(
                  children: [
                    _buildNavItem(0, LucideIcons.home, 'Home'),
                    _buildNavItem(1, LucideIcons.clipboardList, 'Task'),
                    _buildNavItem(2, LucideIcons.user, 'Profile'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = _currentTab == index;
    final activeColor = isDark ? AppColors.primaryLight : AppColors.primary;
    final inactiveColor = isDark ? Colors.white54 : AppColors.navInactive;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.surface.withValues(
                    alpha: isDark ? 0.72 : 0.96,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSizes.radiusRound),
            border: isActive
                ? Border.all(
                    color: activeColor.withValues(alpha: 0.12),
                  )
                : null,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.secondary.withValues(
                        alpha: isDark ? 0.18 : 0.08,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectTab(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: isActive ? activeColor : inactiveColor,
                ),
                const SizedBox(height: 4),
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 11,
                    height: 1,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LOADING SKELETON
  // ═══════════════════════════════════════════════════════════
  Widget _buildLoadingSkeleton() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSizes.screenPaddingH),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: AppSizes.xl),
            ShimmerBox(width: 120, height: 16),
            SizedBox(height: AppSizes.sm),
            ShimmerBox(width: 200, height: 28),
            SizedBox(height: AppSizes.xxl),
            ShimmerCard(height: 160),
            SizedBox(height: AppSizes.lg),
            ShimmerCard(height: 120),
            SizedBox(height: AppSizes.lg),
            ShimmerCard(height: 100),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback? onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
          boxShadow: isDark ? null : AppDecorations.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: (gradient as LinearGradient)
                        .colors
                        .first
                        .withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isDark ? Colors.white54 : AppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
