import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/constants.dart';
import '../../../../widgets/custom_button.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../widgets/custom_popup_menu.dart';
import '../../../../services/support_service.dart';
import '../../../../core/utils/snackbar_utils.dart';

class ContactSection extends StatefulWidget {
  const ContactSection({Key? key}) : super(key: key);

  @override
  State<ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends State<ContactSection> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  String _issueType = 'General Inquiry';
  XFile? _screenshot;
  bool _isSubmittingForm = false;

  final List<String> _issueTypes = [
    'General Inquiry',
    'Task Issue',
    'Payment Problem',
    'Account Settings',
    'Report a Bug',
    'Other'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _screenshot = pickedFile);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Failed to pick image: $e');
      }
    }
  }

  void _submitSupportRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmittingForm = true);

    final error = await SupportService().submitSupportRequest(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim(),
      issueType: _issueType,
      screenshot: _screenshot,
    );

    if (!mounted) return;

    setState(() => _isSubmittingForm = false);

    if (error == null) {
      // Success
      SnackBarUtils.showSuccess('Support request submitted successfully.');

      // Clear Form
      _formKey.currentState!.reset();
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _subjectController.clear();
      _messageController.clear();
      setState(() {
        _issueType = 'General Inquiry';
        _screenshot = null;
      });
    } else {
      // Error
      SnackBarUtils.showError(error);
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        SnackBarUtils.showError('Could not open $urlString');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.screenPaddingH,
        vertical: AppSizes.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick Reach Header
          Text(
            'Quick Contact',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                LucideIcons.clock,
                size: 13,
                color: isDark ? Colors.white54 : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                AppConstants.supportHours,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: _QuickContactCard(
                  icon: LucideIcons.mail,
                  title: 'Email Us',
                  subtitle: AppConstants.supportEmail,
                  color: AppColors.primary,
                  onTap: () =>
                      _launchUrl('mailto:${AppConstants.supportEmail}'),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _QuickContactCard(
                  icon: LucideIcons.phone,
                  title: 'Call Us',
                  subtitle: AppConstants.supportPhone,
                  color: AppColors.info,
                  onTap: () =>
                      _launchUrl('tel:${AppConstants.supportPhone}'),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),

          // Divider
          Row(
            children: [
              Expanded(
                child: Divider(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                child: Text(
                  'Or Submit a Request',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),

          // Contact Form
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppSizes.radiusXl),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.textDark.withValues(alpha: 0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tell us what happened',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Issue Type Dropdown
                  Text(
                    'Issue Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.textBody,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Theme.of(context).scaffoldBackgroundColor
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: CustomPopupMenuFormField<String>(
                      initialValue: _issueType,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.textDark,
                        fontSize: 15,
                      ),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _issueType = newValue);
                        }
                      },
                      items: _issueTypes
                          .map((value) => CustomPopupMenuItem<String>(
                                value: value,
                                label: value,
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),

                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          hintText: 'John Doe',
                          prefixIcon: LucideIcons.user,
                          validator: (value) =>
                              value == null || value.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: CustomTextField(
                          controller: _phoneController,
                          label: 'Phone (Optional)',
                          hintText: '+1 234...',
                          prefixIcon: LucideIcons.phone,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),

                  CustomTextField(
                    controller: _emailController,
                    label: 'Email',
                    hintText: 'john@example.com',
                    prefixIcon: LucideIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (!value.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.md),

                  CustomTextField(
                    controller: _subjectController,
                    label: 'Subject',
                    hintText: 'Brief summary of the issue',
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSizes.md),

                  CustomTextField(
                    controller: _messageController,
                    label: 'Message',
                    hintText: 'Provide details about your issue...',
                    maxLines: 4,
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Screenshot Picker
                  Text(
                    'Attachment (Optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.textBody,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  InkWell(
                    onTap: _pickScreenshot,
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                    child: Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Theme.of(context).scaffoldBackgroundColor
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                        border: Border.all(
                          color: _screenshot != null
                              ? AppColors.primary
                              : Theme.of(context).dividerColor.withValues(alpha: 0.1),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _screenshot != null
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : (isDark ? Colors.white12 : Colors.white),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _screenshot != null ? LucideIcons.image : LucideIcons.uploadCloud,
                              color: _screenshot != null ? AppColors.primary : (isDark ? Colors.white54 : AppColors.textMuted),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _screenshot != null ? 'Screenshot Attached' : 'Upload Screenshot',
                                  style: TextStyle(
                                    fontWeight: _screenshot != null ? FontWeight.w600 : FontWeight.w500,
                                    color: _screenshot != null 
                                      ? (isDark ? Colors.white : AppColors.textDark)
                                      : (isDark ? Colors.white70 : AppColors.textBody),
                                  ),
                                ),
                                if (_screenshot != null)
                                  Text(
                                    _screenshot!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_screenshot != null)
                            IconButton(
                              icon: const Icon(LucideIcons.x, size: 18),
                              onPressed: () => setState(() => _screenshot = null),
                              color: AppColors.error,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.xl),

                  CustomButton(
                    label: 'Submit Request',
                    icon: LucideIcons.send,
                    onPressed: _isSubmittingForm ? null : _submitSupportRequest,
                    isLoading: _isSubmittingForm,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xxl),
        ],
      ),
    );
  }
}

class _QuickContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDark;

  const _QuickContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
