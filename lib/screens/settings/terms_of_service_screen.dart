import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Terms of Service',
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
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
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
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.fileText,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  const Text(
                    'Terms of Service',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    'Effective from: April 1, 2025',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
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
              icon: LucideIcons.userCheck,
              iconColor: AppColors.success,
              title: '1. Eligibility & Account Registration',
              content: [
                const _BulletItem(
                  title: 'Age Requirement',
                  body:
                      'You must be at least 18 years of age to register and use the Sherize platform.',
                ),
                const _BulletItem(
                  title: 'Accurate Information',
                  body:
                      'You agree to provide accurate, complete, and current information during registration. Providing false information may result in immediate account termination.',
                ),
                const _BulletItem(
                  title: 'One Account Per Person',
                  body:
                      'Each individual is permitted only one employee account. Creating multiple accounts for any reason is strictly prohibited and will result in a permanent ban.',
                ),
                const _BulletItem(
                  title: 'Account Security',
                  body:
                      'You are responsible for maintaining the confidentiality of your login credentials. Any activity under your account is your responsibility.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.clipboardList,
              iconColor: AppColors.primary,
              title: '2. Task Completion & Work Standards',
              content: [
                const _BulletItem(
                  title: 'Honest Performance',
                  body:
                      'You must complete all accepted tasks honestly and in good faith. Fabricating calls, falsifying task results, or misrepresenting your work is a serious violation.',
                ),
                const _BulletItem(
                  title: 'Task Acceptance',
                  body:
                      'Accepting a task constitutes a commitment to attempt it. Repeatedly accepting tasks without completion may result in account restrictions.',
                ),
                const _BulletItem(
                  title: 'Script Adherence',
                  body:
                      'For calling tasks, you are required to follow the provided client scripts and guidelines. Deviating in a way that harms the client relationship is prohibited.',
                ),
                const _BulletItem(
                  title: 'Lead Data Confidentiality',
                  body:
                      'All lead information (customer phone numbers, names, etc.) provided for tasks is strictly confidential and must not be shared, stored, or used outside the platform.',
                ),
                const _BulletItem(
                  title: 'Quality Standards',
                  body:
                      'Submissions are reviewed by our admin team. Low-quality or fraudulent submissions may be rejected without payment and could lead to deductions or suspension.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.indianRupee,
              iconColor: AppColors.accent,
              title: '3. Earnings, Payments & Withdrawals',
              content: [
                const _BulletItem(
                  title: 'Pending Approval',
                  body:
                      'All earnings are placed in a "Pending" state following task submission. Funds are only released and added to your wallet after admin review and approval.',
                ),
                const _BulletItem(
                  title: 'Minimum Withdrawal Limit',
                  body:
                      'A minimum wallet balance is required before you can initiate a withdrawal. This minimum amount is subject to change and will be communicated within the app.',
                ),
                const _BulletItem(
                  title: 'Bank Details Accuracy',
                  body:
                      'You are responsible for ensuring your bank account number and IFSC code are accurate. We are not liable for failed transfers due to incorrect bank details provided by you.',
                ),
                const _BulletItem(
                  title: 'Tax Deductions (TDS)',
                  body:
                      'As per applicable Indian tax laws, TDS (Tax Deducted at Source) may be deducted from payouts where applicable. You are responsible for your own tax obligations.',
                ),
                const _BulletItem(
                  title: 'KYC Requirement for Payouts',
                  body:
                      'Your KYC (Know Your Customer) must be verified and approved before any withdrawal request can be processed. This is a mandatory legal requirement.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.shieldOff,
              iconColor: AppColors.error,
              title: '4. Prohibited Conduct',
              content: [
                const _BulletItem(
                  title: 'Fraud & Misrepresentation',
                  body:
                      'Submitting fake call logs, generating artificial task completions, or any other form of fraud results in immediate permanent termination and may be reported to law enforcement.',
                ),
                const _BulletItem(
                  title: 'Data Misuse',
                  body:
                      'Sharing, selling, or misusing any customer lead data or platform information accessed through the app is strictly prohibited.',
                ),
                const _BulletItem(
                  title: 'Platform Manipulation',
                  body:
                      'Using automated bots, scripts, or any tools to manipulate task acceptance, call simulation, or any other platform feature is forbidden.',
                ),
                const _BulletItem(
                  title: 'Harassment',
                  body:
                      'Any form of harassment—toward customers, platform administrators, or fellow team members—will result in immediate suspension.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.scale,
              iconColor: AppColors.info,
              title: '5. Termination & Suspension',
              content: [
                const _BulletItem(
                  title: 'By You',
                  body:
                      'You may terminate your account at any time by contacting our support team. Pending earnings at the time of termination will be processed after a 30-day review period.',
                ),
                const _BulletItem(
                  title: 'By Us',
                  body:
                      'We reserve the right to suspend or permanently terminate your account for any violation of these Terms, without prior notice if the violation is severe.',
                ),
                const _BulletItem(
                  title: 'Effect of Termination',
                  body:
                      'Upon termination, your access to the platform, tasks, and wallet will be revoked. Accumulated earnings from verified tasks before termination will be processed as per our policy.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.refreshCw,
              iconColor: AppColors.teal,
              title: '6. Changes to These Terms',
              content: [
                const _BulletItem(
                  title: 'Right to Modify',
                  body:
                      'We reserve the right to modify these Terms at any time. We will provide at least 7 days notice for material changes via in-app notification or registered email.',
                ),
                const _BulletItem(
                  title: 'Acceptance of Changes',
                  body:
                      'Continued use of the platform after the effective date of the revised Terms constitutes your acceptance of the new terms.',
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),

            _buildSection(
              isDark: isDark,
              icon: LucideIcons.building,
              iconColor: AppColors.violet,
              title: '7. Governing Law',
              content: [
                const _BulletItem(
                  title: 'Jurisdiction',
                  body:
                      'These Terms are governed by the laws of India. Any disputes arising out of or in connection with these Terms shall be subject to the exclusive jurisdiction of the courts in Hyderabad, Telangana, India.',
                ),
                const _BulletItem(
                  title: 'Dispute Resolution',
                  body:
                      'We encourage dispute resolution through direct negotiation first. If unresolved within 30 days, disputes shall be settled through binding arbitration as per the Arbitration and Conciliation Act, 1996.',
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
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle,
              color: isDark ? AppColors.warningLight : AppColors.warning,
              size: 18),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              'Please read these Terms of Service ("Terms") carefully before using the Sherize platform. By accessing or using the app, you agree to be bound by these Terms. If you do not agree, you must not use the platform.',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textBody,
                height: 1.7,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
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
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Icon(icon, size: 18, color: iconColor),
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
                            color: iconColor.withValues(alpha: 0.6),
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
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.helpCircle,
                  color: isDark ? Colors.white54 : AppColors.textMuted,
                  size: 18),
              const SizedBox(width: AppSizes.sm),
              Text(
                'Questions About These Terms?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'For any legal queries or disputes, please contact our support team.',
            style: TextStyle(
              color: isDark ? Colors.white60 : AppColors.textBody,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            'legal@sherize.app',
            style: TextStyle(
              color: isDark ? AppColors.primaryLight : AppColors.primary,
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
