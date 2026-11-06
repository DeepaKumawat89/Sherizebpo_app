import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft,
              color: isDark ? Colors.white : AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.xl),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSizes.radiusXl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.shield,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    'Last updated: September 16, 2026',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xl),

            _buildIntro(isDark),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.database,
              title: '1. Information We Collect',
              content: [
                const _BulletItem(
                  title: 'Personal Identification',
                  body:
                      'Your full name, mobile number, and email address registered during account creation.',
                ),
                const _BulletItem(
                  title: 'KYC Documents',
                  body:
                      'Aadhaar card, PAN card, or other government-issued identification documents required for financial compliance and payment eligibility.',
                ),
                const _BulletItem(
                  title: 'Bank & Financial Details',
                  body:
                      'Bank account number and IFSC code, which are collected solely to process earnings withdrawals and payouts.',
                ),
                const _BulletItem(
                  title: 'Task & Activity Data',
                  body:
                      'Records of tasks accepted, calls made, and submissions completed for quality assurance and earning calculations.',
                ),
                const _BulletItem(
                  title: 'Device & Usage Data',
                  body:
                      'Authentication activity, notification tokens, task activity, and technical error details needed to operate, secure, and improve the app.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.settings,
              title: '2. How We Use Your Information',
              content: [
                const _BulletItem(
                  title: 'Account Management',
                  body:
                      'To create, maintain, and secure your employee account on the Sherize platform.',
                ),
                const _BulletItem(
                  title: 'Task Assignment',
                  body:
                      'To match you with appropriate BPO tasks based on your profile and skill eligibility.',
                ),
                const _BulletItem(
                  title: 'Earnings & Payouts',
                  body:
                      'To accurately calculate your earnings and facilitate bank transfers once admin approval is granted.',
                ),
                const _BulletItem(
                  title: 'KYC Compliance',
                  body:
                      'To fulfill legal and regulatory obligations under Indian financial laws (RBI guidelines, PMLA).',
                ),
                const _BulletItem(
                  title: 'Customer Support',
                  body:
                      'To resolve issues, answer queries, and improve our services based on your feedback.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.share2,
              title: '3. Information Sharing',
              content: [
                const _BulletItem(
                  title: 'We Do NOT Sell Your Data',
                  body:
                      'Your personal information is never sold or rented to third parties for commercial purposes.',
                ),
                const _BulletItem(
                  title: 'Payment Processors',
                  body:
                      'Bank details are shared with verified payment gateways (e.g., Razorpay) solely for processing withdrawals.',
                ),
                const _BulletItem(
                  title: 'Legal Requirements',
                  body:
                      'We may disclose information if required by law, court order, or government regulation.',
                ),
                const _BulletItem(
                  title: 'Client Businesses',
                  body:
                      'Your task results may be shared with the business client who owns the task, but your personal identity is kept confidential.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.lock,
              title: '4. Data Security',
              content: [
                const _BulletItem(
                  title: 'Encrypted Storage',
                  body:
                      'All data is stored on Google Firebase with industry-standard encryption at rest and in transit (TLS/SSL).',
                ),
                const _BulletItem(
                  title: 'Access Controls',
                  body:
                      'Strict Firestore Security Rules ensure employees can only access their own data. Admin access is protected by role-based authentication.',
                ),
                const _BulletItem(
                  title: 'KYC Document Security',
                  body:
                      'Identity documents are stored in a private Firebase Storage bucket and are not publicly accessible.',
                ),
                const _BulletItem(
                  title: 'Incident Response',
                  body:
                      'In the unlikely event of a security breach, affected users will be notified immediately via the registered email address.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.userCheck,
              title: '5. Your Rights',
              content: [
                const _BulletItem(
                  title: 'Access & Correction',
                  body:
                      'You can view and update your profile information at any time from Settings > Edit Profile.',
                ),
                const _BulletItem(
                  title: 'Account Deletion',
                  body:
                      'Request deletion from Settings > Request Account Deletion. We delete your account and associated personal data, except records that must be retained for legal, fraud-prevention, or financial compliance purposes.',
                ),
                const _BulletItem(
                  title: 'Data Portability',
                  body:
                      'You may request a copy of your personal data in a standard format by reaching out to support.',
                ),
                const _BulletItem(
                  title: 'Opt-out of Notifications',
                  body:
                      'Manage your notification preferences from Settings > Notifications at any time.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.cookie,
              title: '6. App Storage & Operations',
              content: [
                const _BulletItem(
                  title: 'Operational Data',
                  body:
                      'We process technical and activity data needed to provide app features, investigate errors, and protect accounts. We do not use this data for third-party advertising.',
                ),
                const _BulletItem(
                  title: 'Session Persistence',
                  body:
                      'We store secure authentication tokens locally on your device to keep you logged in across sessions.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.refreshCw,
              title: '7. Policy Updates',
              content: [
                const _BulletItem(
                  title: 'Notification of Changes',
                  body:
                      'We will notify you of any significant changes to this policy via in-app notification or email at least 7 days before they take effect.',
                ),
                const _BulletItem(
                  title: 'Continued Use',
                  body:
                      'Continued use of the platform after policy changes constitutes acceptance of the updated terms.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildContactCard(isDark),
            const SizedBox(height: AppSizes.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        'At Sherize, we are committed to protecting your privacy. This Policy explains what information we collect, how we use it, and your rights with respect to it. By using our app, you agree to the practices described in this document.',
        style: TextStyle(
          color: isDark ? Colors.white70 : AppColors.textBody,
          height: 1.7,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSection({
    required bool isDark,
    required IconData icon,
    required String title,
    required List<_BulletItem> content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : AppColors.borderLight,
            ),
          ),
          child: Column(
            children: content.map((item) {
              final isLast = item == content.last;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.body,
                                style: TextStyle(
                                  color: isDark ? Colors.white60 : AppColors.textBody,
                                  height: 1.6,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : AppColors.borderLight,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.info.withValues(alpha: isDark ? 0.15 : 0.08),
            AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.mail,
                  color: isDark ? AppColors.infoLight : AppColors.info,
                  size: 20),
              const SizedBox(width: AppSizes.sm),
              Text(
                'Privacy Concerns?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'If you have any questions about this Privacy Policy or how your data is handled, please contact our Data Protection Officer.',
            style: TextStyle(
              color: isDark ? Colors.white60 : AppColors.textBody,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            AppConstants.supportEmail,
            style: TextStyle(
              color: isDark ? AppColors.infoLight : AppColors.info,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Text(
            'Sherize Team',
            style: TextStyle(
              color: isDark ? Colors.white38 : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletItem {
  final String title;
  final String body;
  const _BulletItem({required this.title, required this.body});
}
