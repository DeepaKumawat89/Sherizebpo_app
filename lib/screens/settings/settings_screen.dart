import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
 
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../services/security_service.dart';
import '../../widgets/developer_credit.dart';
import 'passcode_screen.dart';
 
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
 
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
 
class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _openPlayStore() async {
    final uri = Uri.parse(AppConstants.playStoreUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      SnackBarUtils.showError('Could not open the app store');
    }
  }
 
  Future<void> _requestAccountDeletion() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query: 'subject=${Uri.encodeComponent('Sherize account deletion request')}'
          '&body=${Uri.encodeComponent('Please delete my Sherize account and associated personal data.\n\nRegistered email or Employee ID: ')}',
    );
    bool launched;
    try {
      launched = await launchUrl(uri);
    } on PlatformException {
      launched = false;
    }
    if (!launched) {
      SnackBarUtils.showError(
          'Could not open email. Contact ${AppConstants.supportEmail}.');
    }
  }
 
  Future<void> _handleLogout(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Logout', 
          style: TextStyle(color: isDark ? Colors.white : AppColors.textDark, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to log out?',
          style: TextStyle(color: isDark ? Colors.white70 : AppColors.textBody)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white38 : AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
 
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: isDark ? Colors.white : AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.screenPaddingH,
          vertical: AppSizes.screenPaddingV,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel(context, 'Account'),
                const SizedBox(height: AppSizes.sm),
                _card(context, [
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.user,
                    title: 'Edit Profile',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.editProfile),
                  ),
                  _divider(isDark),
                  Consumer<AuthService>(
                    builder: (context, auth, _) {
                      return _buildListTile(
                        context: context,
                        icon: LucideIcons.fingerprint,
                        title: 'Employee ID',
                        subtitle: auth.workerId ?? 'Not Assigned',
                        trailingIcon: LucideIcons.copy,
                        onTap: () {
                          if (auth.workerId != null) {
                            Clipboard.setData(
                                ClipboardData(text: auth.workerId!));
                            SnackBarUtils.showInfo(
                                'Employee ID copied to clipboard');
                          }
                        },
                      );
                    },
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.landmark,
                    title: 'Bank / UPI Details',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.bankDetails),
                  ),
                ]),
                const SizedBox(height: AppSizes.xxl),
 
                _sectionLabel(context, 'Preferences'),
                const SizedBox(height: AppSizes.sm),
                _card(context, [
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.bell,
                    title: 'Notifications',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.notifications),
                  ),
                ]),
                const SizedBox(height: AppSizes.xxl),
 
                _sectionLabel(context, 'Security'),
                const SizedBox(height: AppSizes.sm),
                Consumer<SecurityService>(
                  builder: (context, security, _) {
                    return _card(context, [
                      SwitchListTile(
                        activeThumbColor: AppColors.primary,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.lg, vertical: AppSizes.xs),
                        secondary: _iconTile(
                          isDark: isDark,
                          child: Icon(LucideIcons.lock,
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.textDark,
                              size: 20),
                        ),
                        title: Text('App Lock',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color:
                                  isDark ? Colors.white : AppColors.textDark,
                            )),
                        subtitle: Text(
                          security.isPasscodeEnabled
                              ? 'Passcode enabled'
                              : 'Passcode disabled',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                isDark ? Colors.white38 : AppColors.textMuted,
                          ),
                        ),
                        value: security.isPasscodeEnabled,
                        onChanged: (value) {
                          if (value) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PasscodeScreen(
                                      mode: PasscodeMode.setup)),
                            );
                          } else {
                            security.clearPasscode();
                          }
                        },
                      ),
                      if (security.isPasscodeEnabled) ...[
                        _divider(isDark),
                        _buildListTile(
                          context: context,
                          icon: LucideIcons.key,
                          title: 'Change Passcode',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PasscodeScreen(
                                      mode: PasscodeMode.enterCurrentToChange)),
                            );
                          },
                        ),
                        _divider(isDark),
                        SwitchListTile(
                          activeThumbColor: AppColors.primary,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.lg, vertical: AppSizes.xs),
                          secondary: _iconTile(
                            isDark: isDark,
                            child: Icon(Icons.fingerprint,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.textDark,
                                size: 20),
                          ),
                          title: Text('Unlock with Biometrics',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textDark,
                              )),
                          value: security.isBiometricsEnabled,
                          onChanged: security.isAuthenticating
                              ? null
                              : (value) async {
                                  final changed = await security
                                      .setBiometricsEnabled(value);
                                  if (!changed && context.mounted) {
                                    SnackBarUtils.showError(
                                        security.biometricError ??
                                            'Unable to enable biometrics. Try again.');
                                  }
                                },
                        ),
                      ],
                    ]);
                  },
                ),
                const SizedBox(height: AppSizes.xxl),
 
                _sectionLabel(context, 'Support & About'),
                const SizedBox(height: AppSizes.sm),
                _card(context, [
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.helpCircle,
                    title: 'Help Center',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.messageSquare,
                    title: 'FAQs',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.star,
                    title: 'Rate the App',
                    onTap: _openPlayStore,
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.shield,
                    title: 'Privacy Policy',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.privacyPolicy),
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.fileText,
                    title: 'Terms of Service',
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.termsOfService),
                  ),
                  _divider(isDark),
                  _buildListTile(
                    context: context,
                    icon: LucideIcons.userX,
                    title: 'Request Account Deletion',
                    subtitle: 'Delete your account and associated personal data',
                    iconColor: AppColors.error,
                    iconBackgroundColor: AppColors.error.withValues(alpha: 0.1),
                    onTap: _requestAccountDeletion,
                  ),
                ]),
                const SizedBox(height: AppSizes.xxxl),
 
                _card(
                  context,
                  [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.lg, vertical: AppSizes.xs),
                      leading: _iconTile(
                        isDark: isDark,
                        background: AppColors.error.withValues(alpha: 0.1),
                        child: const Icon(LucideIcons.logOut,
                            color: AppColors.error, size: 20),
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 16),
                      ),
                      onTap: () => _handleLogout(context),
                    ),
                  ],
                  borderColor: AppColors.error.withValues(alpha: 0.25),
                ),
 
                const SizedBox(height: AppSizes.xl),
                Center(
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
                          color: isDark ? Colors.white24 : AppColors.textLight,
                        ),
                      ),
                      const SizedBox(height: AppSizes.md),
                      DeveloperCredit(
                        color: isDark ? Colors.white38 : AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
 
                const SizedBox(height: AppSizes.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
 
  Widget _sectionLabel(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: AppSizes.xs),
      child: Text(
        text,
        style: TextStyle(
            color: isDark ? Colors.white54 : AppColors.textLabel,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1),
      ),
    );
  }
 
  Widget _divider(bool isDark) {
    return Divider(
      height: 1,
      indent: AppSizes.lg + 40 + AppSizes.base,
      endIndent: AppSizes.lg,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : AppColors.border.withValues(alpha: 0.5),
    );
  }
 
  Widget _iconTile({
    required bool isDark,
    required Widget child,
    Color? background,
  }) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ??
            (isDark
                ? Colors.white.withValues(alpha: 0.05)
                : AppColors.surfaceVariant),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: child,
    );
  }
 
  Widget _card(BuildContext context, List<Widget> children,
      {Color? borderColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSizes.radiusLg);
 
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      // Material (instead of a decorated Container) so tile ripples are visible.
      child: Material(
        color: Theme.of(context).cardColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: borderColor ?? Theme.of(context).dividerColor,
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
 
  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? iconBackgroundColor,
    String? trailingText,
    String? subtitle,
    IconData trailingIcon = LucideIcons.chevronRight,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.xs),
      leading: _iconTile(
        isDark: isDark,
        background: iconBackgroundColor,
        child: Icon(icon,
            color: iconColor ?? (isDark ? Colors.white70 : AppColors.textDark),
            size: 20),
      ),
      title: Text(title,
          style: TextStyle(
            fontWeight: FontWeight.w600, 
            fontSize: 16,
            color: isDark ? Colors.white : AppColors.textDark,
          )),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white38 : AppColors.textMuted,
      )) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(trailingText,
                style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: AppSizes.sm),
          ],
          Icon(trailingIcon,
              color: isDark ? Colors.white38 : AppColors.textLight,
              size: trailingIcon == LucideIcons.chevronRight ? 20 : 18),
        ],
      ),
      onTap: onTap,
    );
  }
}
 