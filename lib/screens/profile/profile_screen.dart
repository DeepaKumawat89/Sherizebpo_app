import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/auth_service.dart';
import '../../services/platform_settings_service.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/developer_credit.dart';
import 'profile_information_screen.dart';

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
          final String employeeIdRaw = (data['employeeId'] ?? '').toString().trim();
          final String employeeId = employeeIdRaw.isNotEmpty
              ? employeeIdRaw
              : (data['workerId'] ?? '').toString().trim();
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
          final String initial =
              userName.isNotEmpty ? userName.characters.first.toUpperCase() : 'U';

          return CustomScrollView(
            slivers: [
              // ── Profile Header ──
              ProfileHeader(
                userName: userName,
                employeeId: employeeId,
                initial: initial,
                profileImageUrl: profileImageUrl,
                kycStatus: kycStatus,
                kycColor: kycColor,
              ),

              // ── Content ──
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 360
                      ? AppSizes.base
                      : AppSizes.screenPaddingH,
                  AppSizes.xl,
                  MediaQuery.sizeOf(context).width < 360
                      ? AppSizes.base
                      : AppSizes.screenPaddingH,
                  AppSizes.xxxl,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Stats Row ──
                    _buildStatsRow(context, earnings),
                    const SizedBox(height: AppSizes.md),

                    // ── KYC Status ──
                    _buildKycBanner(context, kycStatus, kycColor,
                        isVerified: kycStatus == 'Verified'),
                    const SizedBox(height: AppSizes.xxl),

                    _ProfileCategoryGroup(
                      title: 'Personal & Work Information',
                      children: [
                        _ProfileCategoryCard(
                          embedded: true,
                          icon: LucideIcons.user,
                          title: 'Personal Information',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileInformationScreen(
                                title: 'Personal Information',
                                icon: LucideIcons.user,
                                items: [
                                  ProfileInformationItem(
                                      icon: LucideIcons.user,
                                      label: 'Name',
                                      value: userName),
                                  ProfileInformationItem(
                                      icon: LucideIcons.hash,
                                      label: 'Employee ID',
                                      value: employeeId.isNotEmpty
                                          ? employeeId
                                          : 'N/A'),
                                  ProfileInformationItem(
                                      icon: LucideIcons.phone,
                                      label: 'Phone',
                                      value: userPhone),
                                  ProfileInformationItem(
                                      icon: LucideIcons.users,
                                      label: 'Gender',
                                      value: (data['gender'] ?? 'Not set')
                                          .toString()),
                                  ProfileInformationItem(
                                      icon: LucideIcons.calendar,
                                      label: 'DOB',
                                      value: (data['dateOfBirth'] ?? 'Not set')
                                          .toString()),
                                  ProfileInformationItem(
                                      icon: LucideIcons.mapPin,
                                      label: 'City',
                                      value: (data['city'] ?? 'Not set')
                                          .toString()),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _ProfileCategoryCard(
                          embedded: true,
                          icon: LucideIcons.briefcase,
                          title: 'Work Information',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileInformationScreen(
                                title: 'Work Information',
                                icon: LucideIcons.briefcase,
                                showTaskHistory: true,
                                items: [
                                  ProfileInformationItem(
                                      icon: LucideIcons.languages,
                                      label: 'Language',
                                      value: (data['language'] ?? 'Not set')
                                          .toString()),
                                  ProfileInformationItem(
                                      icon: LucideIcons.graduationCap,
                                      label: 'Education',
                                      value: (data['education'] ?? 'Not set')
                                          .toString()),
                                  ProfileInformationItem(
                                      icon: LucideIcons.briefcase,
                                      label: 'Experience',
                                      value: (data['experience'] ?? 'Not set')
                                          .toString()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildStatsRow(BuildContext context, num earnings) {
    final earningsEnabled =
        context.watch<PlatformSettingsService>().earningsSystemEnabled;
    if (!earningsEnabled) return const SizedBox.shrink();

    final stats = <Widget>[
      _StatMini(
        icon: LucideIcons.banknote,
        label: 'Earnings',
        value: '₹${earnings.toStringAsFixed(0)}',
        color: AppColors.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 340 ? 2 : stats.length;
        final spacing = AppSizes.sm * (columns - 1);
        final cardWidth = (constraints.maxWidth - spacing) / columns;

        return Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: [
            for (final stat in stats)
              SizedBox(width: cardWidth, child: stat),
          ],
        );
      },
    );
  }

  Widget _buildKycBanner(BuildContext context, String status, Color color,
      {bool isVerified = false}) {
    return GestureDetector(
      onTap: isVerified
          ? null
          : () => Navigator.pushNamed(context, AppRoutes.kyc),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.base),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Icon(
                status == 'Verified'
                    ? LucideIcons.checkCircle2
                    : status == 'Rejected'
                        ? LucideIcons.xCircle
                        : LucideIcons.clock,
                size: 19,
                color: color,
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KYC Status',
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.sm,
                  vertical: AppSizes.xs,
                ),
                decoration: AppDecorations.statusBadge(color),
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
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
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
        ],
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border.withValues(alpha: 0.7),
            ),
            boxShadow: isDark ? null : AppDecorations.shadowMd,
          ),
          child: Column(children: dividedChildren),
        ),
      ],
    );
  }
}

class _ProfileCategoryCard extends StatelessWidget {
  const _ProfileCategoryCard({
    this.embedded = false,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final bool embedded;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: embedded ? BorderRadius.zero : BorderRadius.circular(AppSizes.radiusXl),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.base),
        decoration: BoxDecoration(
          color: embedded ? Colors.transparent : Theme.of(context).cardColor,
          borderRadius:
              embedded ? BorderRadius.zero : BorderRadius.circular(AppSizes.radiusXl),
          border: embedded
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.border.withValues(alpha: 0.7),
                ),
          boxShadow: embedded || isDark ? null : AppDecorations.shadowMd,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: isDark ? Colors.white24 : AppColors.textPlaceholder,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCategoryGroup extends StatelessWidget {
  const _ProfileCategoryGroup({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppSizes.radiusRound),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border.withValues(alpha: 0.7),
            ),
            boxShadow: isDark ? null : AppDecorations.shadowMd,
          ),
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 68,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
              ],
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 360
        ? AppSizes.base
        : AppSizes.screenPaddingH;
    final avatarFallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: AppDecorations.primaryLightGradient,
      ),
      child: Center(
        child: Text(initial,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );

    return SliverAppBar(
      expandedHeight: 200,
      collapsedHeight: 72,
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      backgroundColor:
          isDark ? AppColors.secondary : AppColors.primaryDark,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppSizes.radiusXxl),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final settings = context
              .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
          final collapseRange = settings == null
              ? 0.0
              : settings.maxExtent - settings.minExtent;
          final collapseProgress = collapseRange <= 0
              ? 0.0
              : (1 -
                      (settings!.currentExtent - settings.minExtent) /
                          collapseRange)
                  .clamp(0.0, 1.0);
          final pinnedOpacity = Curves.easeOut.transform(
            ((collapseProgress - 0.62) / 0.38).clamp(0.0, 1.0),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppSizes.radiusXxl),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppDecorations.darkGradient
                  : AppDecorations.primaryGradient,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSizes.sm,
              horizontalPadding,
              AppSizes.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      _HeaderIconButton(
                        label: 'Back',
                        icon: LucideIcons.arrowLeft,
                        onTap: () => Navigator.maybePop(context),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: Navigator.canPop(context) ? AppSizes.sm : 0,
                        ),
                        child: Text(
                          'Profile',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ),
                    _HeaderIconButton(
                      label: 'Edit profile',
                      icon: LucideIcons.edit3,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.editProfile,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: 'Profile photo',
                      image: true,
                      child: ExcludeSemantics(
                        child: Container(
                          width: 88,
                          height: 88,
                          padding: const EdgeInsets.all(AppSizes.xs),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary
                                    .withValues(alpha: 0.20),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: profileImageUrl.isEmpty
                                ? avatarFallback
                                : Image.network(
                                    profileImageUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: (84 *
                                            MediaQuery.devicePixelRatioOf(
                                                context))
                                        .round(),
                                    frameBuilder: (_, child, frame, loaded) =>
                                        loaded || frame != null
                                            ? child
                                            : avatarFallback,
                                    errorBuilder: (_, __, ___) =>
                                        avatarFallback,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.base),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Row(
                            children: [
                              Text(
                                'Employee ID :',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  employeeId.isEmpty ? 'Not assigned' : employeeId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ],
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
    ),
  ),
              IgnorePointer(
                ignoring: pinnedOpacity == 0,
                child: Opacity(
                  opacity: pinnedOpacity,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: SizedBox(
                        height: 72,
                        child: Row(
                          children: [
                            if (Navigator.canPop(context)) ...[
                              _HeaderIconButton(
                                label: 'Back',
                                icon: LucideIcons.arrowLeft,
                                onTap: () => Navigator.maybePop(context),
                              ),
                              const SizedBox(width: AppSizes.sm),
                            ],
                            Expanded(
                              child: Text(
                                'Profile',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            _HeaderIconButton(
                              label: 'Edit profile',
                              icon: LucideIcons.edit3,
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppRoutes.editProfile,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
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
      constraints: const BoxConstraints(minHeight: 124),
      padding: const EdgeInsets.all(AppSizes.base),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border.withValues(alpha: 0.7),
        ),
        boxShadow: isDark ? null : AppDecorations.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: AppDecorations.iconBox(color: color),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
        horizontal: AppSizes.base,
        vertical: AppSizes.base,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.base,
          vertical: AppSizes.base,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDestructive ? color : (isDark ? Colors.white : AppColors.textDark),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight, 
              size: 18, 
              color: isDark ? Colors.white24 : AppColors.textPlaceholder
            ),
          ],
        ),
      ),
    );
  }
}
