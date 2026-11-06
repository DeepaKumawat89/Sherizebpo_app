import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/custom_button.dart';

class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({Key? key}) : super(key: key);

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _upiController = TextEditingController();
  final _accountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountHolderController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMode = 'upi'; // 'upi' or 'bank'

  @override
  void initState() {
    super.initState();
    _loadExistingDetails();
  }

  @override
  void dispose() {
    _upiController.dispose();
    _accountController.dispose();
    _ifscController.dispose();
    _bankNameController.dispose();
    _accountHolderController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data() ?? {};
        final bank = data['bankDetails'] as Map<String, dynamic>? ?? {};

        setState(() {
          _paymentMode = bank['paymentMode'] ?? 'upi';
          _upiController.text = bank['upiId'] ?? '';
          _accountController.text = bank['accountNumber'] ?? '';
          _ifscController.text = bank['ifscCode'] ?? '';
          _bankNameController.text = bank['bankName'] ?? '';
          _accountHolderController.text = bank['accountHolder'] ?? '';
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading bank details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) {
      SnackBarUtils.showInfo('Please correct the highlighted errors before saving.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final Map<String, dynamic> bankDetails = {
        'paymentMode': _paymentMode,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_paymentMode == 'upi') {
        bankDetails['upiId'] = _upiController.text.trim();
        bankDetails['upiVerified'] = false;
      } else {
        bankDetails['accountNumber'] = _accountController.text.trim();
        bankDetails['ifscCode'] = _ifscController.text.trim().toUpperCase();
        bankDetails['bankName'] = _bankNameController.text.trim();
        bankDetails['accountHolder'] = _accountHolderController.text.trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'bankDetails': bankDetails})
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception('Network timeout. Please check your connection.');
          });

      if (!mounted) return;
      SnackBarUtils.showSuccess('Bank details saved successfully!');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Payment Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.screenPaddingH),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(AppSizes.lg),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                        border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.info,
                              size: 20, color: AppColors.info),
                          const SizedBox(width: AppSizes.md),
                          Expanded(
                            child: Text(
                              'Add your payment details to receive withdrawals. '
                              'You can use UPI (fastest) or a bank account.',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : AppColors.info,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    Text(
                      'PAYMENT METHOD',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isDark ? Colors.white38 : AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                        border: Border.all(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                        boxShadow: isDark ? null : AppDecorations.shadowSm,
                      ),
                      child: Column(
                        children: [
                          _PaymentModeOption(
                            icon: LucideIcons.smartphone,
                            label: 'UPI ID',
                            subtitle: 'Fastest — instant transfer',
                            isSelected: _paymentMode == 'upi',
                            onTap: () => setState(() => _paymentMode = 'upi'),
                            isFirst: true,
                          ),
                          Divider(
                            height: 1,
                            indent: 56,
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                          ),
                          _PaymentModeOption(
                            icon: LucideIcons.landmark,
                            label: 'Bank Account',
                            subtitle: 'NEFT/IMPS transfer',
                            isSelected: _paymentMode == 'bank',
                            onTap: () => setState(() => _paymentMode = 'bank'),
                            isFirst: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),

                    if (_paymentMode == 'upi') ...[
                      Text(
                        'UPI DETAILS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: isDark ? Colors.white38 : AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: AppSizes.md),
                      _buildTextField(
                        context: context,
                        controller: _upiController,
                        label: 'UPI ID',
                        hint: 'example@upi or 9876543210@paytm',
                        icon: LucideIcons.atSign,
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'UPI ID is required';
                          }
                          if (!val.contains('@')) {
                            return 'Enter a valid UPI ID (e.g. name@upi)';
                          }
                          return null;
                        },
                      ),
                    ],

                    if (_paymentMode == 'bank') ...[
                      Text(
                        'BANK ACCOUNT DETAILS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: isDark ? Colors.white38 : AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: AppSizes.md),
                      _buildTextField(
                        context: context,
                        controller: _accountHolderController,
                        label: 'Account Holder Name',
                        hint: 'As per bank records',
                        icon: LucideIcons.user,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Account holder name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSizes.md),
                      _buildTextField(
                        context: context,
                        controller: _accountController,
                        label: 'Account Number',
                        hint: 'Enter bank account number',
                        icon: LucideIcons.hash,
                        keyboardType: TextInputType.number,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Account number is required';
                          }
                          if (val.trim().length < 9) {
                            return 'Enter a valid account number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSizes.md),
                      _buildTextField(
                        context: context,
                        controller: _ifscController,
                        label: 'IFSC Code',
                        hint: 'e.g. SBIN0001234',
                        icon: LucideIcons.building,
                        textCapitalization: TextCapitalization.characters,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'IFSC code is required';
                          }
                          if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$')
                              .hasMatch(val.trim().toUpperCase())) {
                            return 'Enter a valid IFSC code';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSizes.md),
                      _buildTextField(
                        context: context,
                        controller: _bankNameController,
                        label: 'Bank Name',
                        hint: 'e.g. State Bank of India',
                        icon: LucideIcons.landmark,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Bank name is required';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: AppSizes.xxxl),
                    CustomButton(
                      label: _isSaving ? 'Saving...' : 'Save Payment Details',
                      icon: LucideIcons.save,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _saveDetails,
                    ),
                    const SizedBox(height: AppSizes.xxxl),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        validator: validator,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isDark ? Colors.white : AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 42, minHeight: 42),
          labelStyle: TextStyle(
            color: isDark ? Colors.white38 : AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: TextStyle(
            color: isDark ? Colors.white24 : AppColors.textPlaceholder,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg, vertical: AppSizes.lg),
          errorStyle: const TextStyle(fontSize: 12, color: AppColors.error),
        ),
      ),
    );
  }
}

class _PaymentModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;

  const _PaymentModeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(AppSizes.radiusLg) : Radius.zero,
        bottom:
            !isFirst ? const Radius.circular(AppSizes.radiusLg) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected 
                    ? AppColors.primary.withValues(alpha: 0.1) 
                    : (isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Icon(icon,
                  size: 16,
                  color: isSelected ? AppColors.primary : (isDark ? Colors.white38 : AppColors.textMuted)),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : (isDark ? Colors.white12 : AppColors.border),
                  width: isSelected ? 6 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
