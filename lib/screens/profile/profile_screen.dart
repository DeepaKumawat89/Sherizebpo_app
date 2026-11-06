import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/auth_service.dart';
import '../../services/platform_settings_service.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/developer_credit.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  Future<void> _handleLogout(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.logOut,
                    color: AppColors.error, size: 24),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                'Logout',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Are you sure you want to log out?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white54 : AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSizes.xl),
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      label: 'Cancel',
                      variant: CustomButtonVariant.outlined,
                      height: 44,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: CustomButton(
                      label: 'Logout',
                      variant: CustomButtonVariant.danger,
                      height: 44,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.logout();
      if (context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('User not logged in.')));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

          final String userName = data['fullName'] ?? data['name'] ?? 'No Name';
          final String userPhone = data['phone'] ??
              data['phoneNumber'] ??
              currentUser.phoneNumber ??
              'No Phone';
          final String rawEmail =
              (data['email'] ?? currentUser.email ?? '').toString();
          // Workers see their Employee ID — never the internal <id>@sherize.app
          // address, which exists only to satisfy Firebase Auth's email login.
          final String employeeIdRaw = (data['employeeId'] ?? '').toString().trim();
          final String employeeId = employeeIdRaw.isNotEmpty
              ? employeeIdRaw
              : (rawEmail.contains('@')
                  ? rawEmail.split('@').first
                  : (data['workerId'] ?? '').toString());
          final String profileImageUrl = data['profileImage'] ??
              data['profileImageUrl'] ??
              data['avatar_url'] ??
              '';

          final dbStatus =
              (data['kycStatus'] ?? data['kyc_status'] ?? 'pending')
                  .toString()
                  .toLowerCase();
          String kycStatus = 'KYC Pending';
          Color kycColor = AppColors.warning;
          if (dbStatus == 'submitted' || dbStatus == 'under review') {
            kycStatus = 'Under Review';
            kycColor = AppColors.info;
          } else if (dbStatus == 'approved' || dbStatus == 'verified') {
            kycStatus = 'Verified';
            kycColor = AppColors.success;
          } else if (dbStatus == 'rejected') {
            kycStatus = 'Rejected';
            kycColor = AppColors.error;
          }

          final num earnings = data['walletBalance'] ??
              data['total_earnings'] ??
              data['earnings'] ??
              0;
          final num completedTasks = data['totalTasksCompleted'] ??
              data['tasks_completed'] ??
              data['completedTasks'] ??
              0;
          final num userRating = (data['rating'] as num?)?.toDouble() ?? 0.0;
          final String initial =
              userName.isNotEmpty ? userName.characters.first.toUpperCase() : 'U';

          return CustomScrollView(
            slivers: [
              // ── Profile Header ──
              SliverToBoxAdapter(
                child: ProfileHeader(
                  userName: userName,
                  employeeId: employeeId,
                  initial: initial,
                  profileImageUrl: profileImageUrl,
                  kycStatus: kycStatus,
                  kycColor: kycColor,
                ),
              ),

              // ── Content ──
              SliverPadding(
                padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Stats Row ──
                    _buildStatsRow(context, earnings, completedTasks, userRating),
                    const SizedBox(height: AppSizes.md),

                    // ── KYC Status ──
                    _buildKycBanner(context, kycStatus, kycColor,
                        isVerified: kycStatus == 'Verified'),
                    const SizedBox(height: AppSizes.xxl),

                    // ── Personal Info ──
                    _buildSection(context, 'Personal Information', [
                      _InfoRow(
                          icon: LucideIcons.user,
                          label: 'Name',
                          value: userName),
                      _InfoRow(
                          icon: LucideIcons.hash,
                          label: 'Employee ID',
                          value: employeeId.isNotEmpty ? employeeId : 'N/A'),
                      _InfoRow(
                          icon: LucideIcons.phone,
                          label: 'Phone',
                          value: userPhone),
                      _InfoRow(
                          icon: LucideIcons.users,
                          label: 'Gender',
                          value: data['gender'] ?? 'Not set'),
                      _InfoRow(
                          icon: LucideIcons.calendar,
                          label: 'DOB',
                          value: data['dateOfBirth'] ?? 'Not set'),
                      _InfoRow(
                          icon: LucideIcons.mapPin,
                          label: 'City',
                          value: data['city'] ?? 'Not set'),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Work Info ──
                    _buildSection(context, 'Work Information', [
                      _ActionRow(
                        icon: LucideIcons.history,
                        label: 'Task History',
                        color: AppColors.primary,
                        onTap: () => Navigator.pushNamed(context, AppRoutes.taskHistory),
                      ),
                      _InfoRow(
                          icon: LucideIcons.languages,
                          label: 'Language',
                          value: data['language'] ?? 'Not set'),
                      _InfoRow(
                          icon: LucideIcons.graduationCap,
                          label: 'Education',
                          value: data['education'] ?? 'Not set'),
                      _InfoRow(
                          icon: LucideIcons.briefcase,
                          label: 'Experience',
                          value: data['experience'] ?? 'Not set'),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Payment Settings ──
                    _buildSection(context, 'Payment', [
                      _ActionRow(
                        icon: LucideIcons.landmark,
                        label: 'Bank / UPI Details',
                        color: AppColors.primary,
                        onTap: () => Navigator.pushNamed(context, AppRoutes.bankDetails),
                      ),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Account Actions ──
                    _buildSection(context, 'Account', [
                      _ActionRow(
                        icon: LucideIcons.shieldCheck,
                        label: 'KYC Verification',
                        color: kycColor,
                        onTap: () => Navigator.pushNamed(context, AppRoutes.kyc),
                      ),
                      _ActionRow(
                        icon: LucideIcons.settings,
                        label: 'Settings',
                        color: AppColors.primary,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.settings),
                      ),
                      _ActionRow(
                        icon: LucideIcons.bell,
                        label: 'Notifications',
                        color: AppColors.info,
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.notifications),
                      ),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Support & Legal ──
                    _buildSection(context, 'Support & About', [
                      _ActionRow(
                        icon: LucideIcons.helpCircle,
                        label: 'Help & Support',
                        color: AppColors.primary,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.help),
                      ),
                      _ActionRow(
                        icon: LucideIcons.messageSquare,
                        label: 'FAQs',
                        color: AppColors.success,
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.help),
                      ),
                      _ActionRow(
                        icon: LucideIcons.shield,
                        label: 'Privacy Policy',
                        color: AppColors.info,
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.privacyPolicy),
                      ),
                      _ActionRow(
                        icon: LucideIcons.fileText,
                        label: 'Terms of Service',
                        color: AppColors.accent,
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.termsOfService),
                      ),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Logout ──
                    _buildSection(context, ' ', [
                      _ActionRow(
                        icon: LucideIcons.logOut,
                        label: 'Logout',
                        color: AppColors.error,
                        isDestructive: true,
                        onTap: () => _handleLogout(context),
                      ),
                    ]),
                    const SizedBox(height: AppSizes.xl),

                    // ── Version Footer ──
                    _buildVersionFooter(context),
                    const SizedBox(height: AppSizes.xxxl),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, num earnings, num tasks, num rating) {
    final earningsEnabled =
        context.watch<PlatformSettingsService>().earningsSystemEnabled;
    final stats = <Widget>[
      if (earningsEnabled)
        _StatMini(
          icon: LucideIcons.banknote,
          label: 'Earnings',
          value: '₹${earnings.toStringAsFixed(0)}',
          color: AppColors.success,
        ),
      _StatMini(
        icon: LucideIcons.checkSquare,
        label: 'Tasks',
        value: tasks.toString(),
        color: AppColors.info,
      ),
      _StatMini(
        icon: LucideIcons.star,
        label: 'Rating',
        value: rating.toStringAsFixed(1),
        color: AppColors.accent,
      ),
    ];

    return Row(
      children: [
        for (int i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSizes.sm),
          Expanded(child: stats[i]),
        ],
      ],
    );
  }

  Widget _buildKycBanner(BuildContext context, String status, Color color,
      {bool isVerified = false}) {
    return InkWell(
      onTap: isVerified
          ? null
          : () => Navigator.pushNamed(context, AppRoutes.kyc),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(
              status == 'Verified'
                  ? LucideIcons.checkCircle2
                  : status == 'Rejected'
                      ? LucideIcons.xCircle
                      : LucideIcons.clock,
              size: 18,
              color: color,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KYC Status',
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isVerified)
                    Text(
                      status == 'Rejected'
                          ? 'Resubmit your documents to get verified'
                          : 'Complete verification to unlock payouts',
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: AppDecorations.statusBadge(color),
              child: Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!isVerified) ...[
              const SizedBox(width: AppSizes.sm),
              Icon(LucideIcons.chevronRight, size: 16, color: color),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVersionFooter(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        children: [
          Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white38 : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Version ${AppConstants.appVersion}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white24 : AppColors.textPlaceholder,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          DeveloperCredit(
            color: isDark ? Colors.white38 : AppColors.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<Widget> dividedChildren = [];
    for (int i = 0; i < children.length; i++) {
      dividedChildren.add(children[i]);
      if (i < children.length - 1) {
        dividedChildren.add(
          Divider(
            height: 1,
            indent: 52,
            endIndent: 0,
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.trim().isNotEmpty) ...[
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.white38 : AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSizes.md),
        ],
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
            boxShadow: isDark ? null : AppDecorations.shadowSm,
          ),
          child: Column(children: dividedChildren),
        ),
      ],
    );
  }
}

// ─── Sub-Widgets ───────────────────────────────────────────────
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.userName,
    required this.employeeId,
    required this.initial,
    required this.profileImageUrl,
    required this.kycStatus,
    required this.kycColor,
  });

  final String userName;
  final String employeeId;
  final String initial;
  final String profileImageUrl;
  final String kycStatus;
  final Color kycColor;

  Future<void> _copyEmployeeId(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: employeeId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Employee ID copied')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy Employee ID. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final avatarFallback = ColoredBox(
      color: colors.primaryContainer,
      child: Center(
        child: Text(initial,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: colors.onPrimaryContainer,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );

    return Material(
      color: Color.alphaBlend(colors.primary.withValues(alpha: 0.04), theme.cardColor),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.screenPaddingH, 8, AppSizes.screenPaddingH, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(LucideIcons.arrowLeft, size: 20),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      ),
                    Expanded(child: Text('Profile', style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 0))),
                    IconButton.filledTonal(
                      tooltip: 'Edit profile',
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.editProfile),
                      icon: const Icon(LucideIcons.edit3, size: 20),
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: 'Profile photo',
                      image: true,
                      child: ExcludeSemantics(
                        child: SizedBox.square(
                          dimension: 72,
                          child: ClipOval(
                            child: profileImageUrl.isEmpty
                                ? avatarFallback
                                : Image.network(
                                    profileImageUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context)).round(),
                                    frameBuilder: (_, child, frame, loaded) => loaded || frame != null ? child : avatarFallback,
                                    errorBuilder: (_, __, ___) => avatarFallback,
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
                          Text(userName, style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700, letterSpacing: 0,
                          )),
                          const SizedBox(height: 8),
                          Text('Employee ID', style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant, letterSpacing: 0,
                          )),
                          Row(
                            children: [
                              Expanded(child: Text(employeeId.isEmpty ? 'Not assigned' : employeeId,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
                              )),
                              IconButton(
                                tooltip: 'Copy Employee ID',
                                onPressed: employeeId.isEmpty ? null : () => _copyEmployeeId(context),
                                icon: const Icon(LucideIcons.copy, size: 18),
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            label: 'KYC status: $kycStatus',
                            child: ExcludeSemantics(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: kycColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(kycStatus == 'Verified' ? LucideIcons.shieldCheck
                                        : kycStatus == 'Rejected' ? LucideIcons.shieldAlert : LucideIcons.clock,
                                      size: 16, color: colors.onSurface,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(child: Text(kycStatus, style: theme.textTheme.labelMedium?.copyWith(
                                      color: colors.onSurface, fontWeight: FontWeight.w600, letterSpacing: 0,
                                    ))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatMini({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: AppDecorations.iconBoxRound(color: color),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.white38 : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(icon, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isDark ? Colors.white38 : AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDestructive;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.color,
    this.isDestructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDestructive ? color : (isDark ? Colors.white : AppColors.textDark),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight, 
              size: 18, 
              color: isDark ? Colors.white12 : AppColors.border
            ),
          ],
        ),
      ),
    );
  }
}
