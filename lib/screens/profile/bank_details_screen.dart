// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:lucide_icons/lucide_icons.dart';

// import '../../core/constants/constants.dart';
// import '../../core/theme/app_decorations.dart';
// import '../../core/utils/snackbar_utils.dart';
// import '../../widgets/custom_button.dart';

// class BankDetailsScreen extends StatefulWidget {
//   const BankDetailsScreen({Key? key}) : super(key: key);

//   @override
//   State<BankDetailsScreen> createState() => _BankDetailsScreenState();
// }

// class _BankDetailsScreenState extends State<BankDetailsScreen> {
//   final _formKey = GlobalKey<FormState>();
//   final _upiController = TextEditingController();
//   final _accountController = TextEditingController();
//   final _ifscController = TextEditingController();
//   final _bankNameController = TextEditingController();
//   final _accountHolderController = TextEditingController();

//   bool _isLoading = true;
//   bool _isSaving = false;
//   String _paymentMode = 'upi'; // 'upi' or 'bank'

//   @override
//   void initState() {
//     super.initState();
//     _loadExistingDetails();
//   }

//   @override
//   void dispose() {
//     _upiController.dispose();
//     _accountController.dispose();
//     _ifscController.dispose();
//     _bankNameController.dispose();
//     _accountHolderController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadExistingDetails() async {
//     final user = FirebaseAuth.instance.currentUser;
//     if (user == null) return;

//     try {
//       final doc = await FirebaseFirestore.instance
//           .collection('users')
//           .doc(user.uid)
//           .get();

//       if (doc.exists && mounted) {
//         final data = doc.data() ?? {};
//         final bank = data['bankDetails'] as Map<String, dynamic>? ?? {};

//         setState(() {
//           _paymentMode = bank['paymentMode'] ?? 'upi';
//           _upiController.text = bank['upiId'] ?? '';
//           _accountController.text = bank['accountNumber'] ?? '';
//           _ifscController.text = bank['ifscCode'] ?? '';
//           _bankNameController.text = bank['bankName'] ?? '';
//           _accountHolderController.text = bank['accountHolder'] ?? '';
//           _isLoading = false;
//         });
//       } else {
//         if (mounted) setState(() => _isLoading = false);
//       }
//     } catch (e) {
//       debugPrint('Error loading bank details: $e');
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _saveDetails() async {
//     if (!_formKey.currentState!.validate()) {
//       SnackBarUtils.showInfo('Please correct the highlighted errors before saving.');
//       return;
//     }

//     final user = FirebaseAuth.instance.currentUser;
//     if (user == null) return;

//     setState(() => _isSaving = true);

//     try {
//       final Map<String, dynamic> bankDetails = {
//         'paymentMode': _paymentMode,
//         'updatedAt': FieldValue.serverTimestamp(),
//       };

//       if (_paymentMode == 'upi') {
//         bankDetails['upiId'] = _upiController.text.trim();
//         bankDetails['upiVerified'] = false;
//       } else {
//         bankDetails['accountNumber'] = _accountController.text.trim();
//         bankDetails['ifscCode'] = _ifscController.text.trim().toUpperCase();
//         bankDetails['bankName'] = _bankNameController.text.trim();
//         bankDetails['accountHolder'] = _accountHolderController.text.trim();
//       }

//       await FirebaseFirestore.instance
//           .collection('users')
//           .doc(user.uid)
//           .update({'bankDetails': bankDetails})
//           .timeout(const Duration(seconds: 10), onTimeout: () {
//             throw Exception('Network timeout. Please check your connection.');
//           });

//       if (!mounted) return;
//       SnackBarUtils.showSuccess('Bank details saved successfully!');
//       Navigator.pop(context);
//     } catch (e) {
//       if (!mounted) return;
//       SnackBarUtils.showError('Failed to save: $e');
//     } finally {
//       if (mounted) setState(() => _isSaving = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     return Scaffold(
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       appBar: AppBar(
//         title: const Text('Payment Details'),
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : SingleChildScrollView(
//               padding: const EdgeInsets.all(AppSizes.screenPaddingH),
//               child: Form(
//                 key: _formKey,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Info banner
//                     Container(
//                       padding: const EdgeInsets.all(AppSizes.lg),
//                       decoration: BoxDecoration(
//                         color: AppColors.info.withValues(alpha: 0.1),
//                         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//                         border: Border.all(
//                             color: AppColors.info.withValues(alpha: 0.2)),
//                       ),
//                       child: Row(
//                         children: [
//                           const Icon(LucideIcons.info,
//                               size: 20, color: AppColors.info),
//                           const SizedBox(width: AppSizes.md),
//                           Expanded(
//                             child: Text(
//                               'Add your payment details to receive withdrawals. '
//                               'You can use UPI (fastest) or a bank account.',
//                               style: TextStyle(
//                                 color: isDark ? Colors.white70 : AppColors.info,
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.w500,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     const SizedBox(height: AppSizes.xxl),

//                     Text(
//                       'PAYMENT METHOD',
//                       style: Theme.of(context).textTheme.labelSmall?.copyWith(
//                             color: isDark ? Colors.white38 : AppColors.textMuted,
//                             fontWeight: FontWeight.w700,
//                             letterSpacing: 1.2,
//                           ),
//                     ),
//                     const SizedBox(height: AppSizes.md),
//                     Container(
//                       decoration: BoxDecoration(
//                         color: Theme.of(context).cardColor,
//                         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//                         border: Border.all(
//                             color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
//                         boxShadow: isDark ? null : AppDecorations.shadowSm,
//                       ),
//                       child: Column(
//                         children: [
//                           _PaymentModeOption(
//                             icon: LucideIcons.smartphone,
//                             label: 'UPI ID',
//                             subtitle: 'Fastest — instant transfer',
//                             isSelected: _paymentMode == 'upi',
//                             onTap: () => setState(() => _paymentMode = 'upi'),
//                             isFirst: true,
//                           ),
//                           Divider(
//                             height: 1,
//                             indent: 56,
//                             color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
//                           ),
//                           _PaymentModeOption(
//                             icon: LucideIcons.landmark,
//                             label: 'Bank Account',
//                             subtitle: 'NEFT/IMPS transfer',
//                             isSelected: _paymentMode == 'bank',
//                             onTap: () => setState(() => _paymentMode = 'bank'),
//                             isFirst: false,
//                           ),
//                         ],
//                       ),
//                     ),
//                     const SizedBox(height: AppSizes.xxl),

//                     if (_paymentMode == 'upi') ...[
//                       Text(
//                         'UPI DETAILS',
//                         style: Theme.of(context).textTheme.labelSmall?.copyWith(
//                               color: isDark ? Colors.white38 : AppColors.textMuted,
//                               fontWeight: FontWeight.w700,
//                               letterSpacing: 1.2,
//                             ),
//                       ),
//                       const SizedBox(height: AppSizes.md),
//                       _buildTextField(
//                         context: context,
//                         controller: _upiController,
//                         label: 'UPI ID',
//                         hint: 'example@upi or 9876543210@paytm',
//                         icon: LucideIcons.atSign,
//                         keyboardType: TextInputType.emailAddress,
//                         validator: (val) {
//                           if (val == null || val.trim().isEmpty) {
//                             return 'UPI ID is required';
//                           }
//                           if (!val.contains('@')) {
//                             return 'Enter a valid UPI ID (e.g. name@upi)';
//                           }
//                           return null;
//                         },
//                       ),
//                     ],

//                     if (_paymentMode == 'bank') ...[
//                       Text(
//                         'BANK ACCOUNT DETAILS',
//                         style: Theme.of(context).textTheme.labelSmall?.copyWith(
//                               color: isDark ? Colors.white38 : AppColors.textMuted,
//                               fontWeight: FontWeight.w700,
//                               letterSpacing: 1.2,
//                             ),
//                       ),
//                       const SizedBox(height: AppSizes.md),
//                       _buildTextField(
//                         context: context,
//                         controller: _accountHolderController,
//                         label: 'Account Holder Name',
//                         hint: 'As per bank records',
//                         icon: LucideIcons.user,
//                         validator: (val) {
//                           if (val == null || val.trim().isEmpty) {
//                             return 'Account holder name is required';
//                           }
//                           return null;
//                         },
//                       ),
//                       const SizedBox(height: AppSizes.md),
//                       _buildTextField(
//                         context: context,
//                         controller: _accountController,
//                         label: 'Account Number',
//                         hint: 'Enter bank account number',
//                         icon: LucideIcons.hash,
//                         keyboardType: TextInputType.number,
//                         validator: (val) {
//                           if (val == null || val.trim().isEmpty) {
//                             return 'Account number is required';
//                           }
//                           if (val.trim().length < 9) {
//                             return 'Enter a valid account number';
//                           }
//                           return null;
//                         },
//                       ),
//                       const SizedBox(height: AppSizes.md),
//                       _buildTextField(
//                         context: context,
//                         controller: _ifscController,
//                         label: 'IFSC Code',
//                         hint: 'e.g. SBIN0001234',
//                         icon: LucideIcons.building,
//                         textCapitalization: TextCapitalization.characters,
//                         validator: (val) {
//                           if (val == null || val.trim().isEmpty) {
//                             return 'IFSC code is required';
//                           }
//                           if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$')
//                               .hasMatch(val.trim().toUpperCase())) {
//                             return 'Enter a valid IFSC code';
//                           }
//                           return null;
//                         },
//                       ),
//                       const SizedBox(height: AppSizes.md),
//                       _buildTextField(
//                         context: context,
//                         controller: _bankNameController,
//                         label: 'Bank Name',
//                         hint: 'e.g. State Bank of India',
//                         icon: LucideIcons.landmark,
//                         validator: (val) {
//                           if (val == null || val.trim().isEmpty) {
//                             return 'Bank name is required';
//                           }
//                           return null;
//                         },
//                       ),
//                     ],

//                     const SizedBox(height: AppSizes.xxxl),
//                     CustomButton(
//                       label: _isSaving ? 'Saving...' : 'Save Payment Details',
//                       icon: LucideIcons.save,
//                       isLoading: _isSaving,
//                       onPressed: _isSaving ? null : _saveDetails,
//                     ),
//                     const SizedBox(height: AppSizes.xxxl),
//                   ],
//                 ),
//               ),
//             ),
//     );
//   }

//   Widget _buildTextField({
//     required BuildContext context,
//     required TextEditingController controller,
//     required String label,
//     required String hint,
//     required IconData icon,
//     TextInputType keyboardType = TextInputType.text,
//     TextCapitalization textCapitalization = TextCapitalization.none,
//     String? Function(String?)? validator,
//   }) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     return Container(
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(AppSizes.radiusLg),
//         border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
//         boxShadow: isDark ? null : AppDecorations.shadowSm,
//       ),
//       child: TextFormField(
//         controller: controller,
//         keyboardType: keyboardType,
//         textCapitalization: textCapitalization,
//         validator: validator,
//         style: Theme.of(context).textTheme.bodyLarge?.copyWith(
//               color: isDark ? Colors.white : AppColors.textDark,
//               fontSize: 15,
//               fontWeight: FontWeight.w600,
//             ),
//         decoration: InputDecoration(
//           labelText: label,
//           hintText: hint,
//           prefixIcon: Padding(
//             padding: const EdgeInsets.only(left: 16, right: 12),
//             child: Icon(icon, size: 18, color: AppColors.primary),
//           ),
//           prefixIconConstraints:
//               const BoxConstraints(minWidth: 42, minHeight: 42),
//           labelStyle: TextStyle(
//             color: isDark ? Colors.white38 : AppColors.textMuted,
//             fontSize: 13,
//             fontWeight: FontWeight.w600,
//           ),
//           hintStyle: TextStyle(
//             color: isDark ? Colors.white24 : AppColors.textPlaceholder,
//             fontSize: 14,
//             fontWeight: FontWeight.w400,
//           ),
//           border: InputBorder.none,
//           enabledBorder: InputBorder.none,
//           focusedBorder: InputBorder.none,
//           contentPadding: const EdgeInsets.symmetric(
//               horizontal: AppSizes.lg, vertical: AppSizes.lg),
//           errorStyle: const TextStyle(fontSize: 12, color: AppColors.error),
//         ),
//       ),
//     );
//   }
// }

// class _PaymentModeOption extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String subtitle;
//   final bool isSelected;
//   final VoidCallback onTap;
//   final bool isFirst;

//   const _PaymentModeOption({
//     required this.icon,
//     required this.label,
//     required this.subtitle,
//     required this.isSelected,
//     required this.onTap,
//     this.isFirst = false,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.vertical(
//         top: isFirst ? const Radius.circular(AppSizes.radiusLg) : Radius.zero,
//         bottom:
//             !isFirst ? const Radius.circular(AppSizes.radiusLg) : Radius.zero,
//       ),
//       child: Padding(
//         padding: const EdgeInsets.symmetric(
//             horizontal: AppSizes.lg, vertical: AppSizes.md),
//         child: Row(
//           children: [
//             Container(
//               width: 36,
//               height: 36,
//               decoration: BoxDecoration(
//                 color: isSelected 
//                     ? AppColors.primary.withValues(alpha: 0.1) 
//                     : (isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background),
//                 borderRadius: BorderRadius.circular(AppSizes.radiusSm),
//               ),
//               child: Icon(icon,
//                   size: 16,
//                   color: isSelected ? AppColors.primary : (isDark ? Colors.white38 : AppColors.textMuted)),
//             ),
//             const SizedBox(width: AppSizes.md),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     label,
//                     style: TextStyle(
//                       color: isDark ? Colors.white : AppColors.textDark,
//                       fontSize: 15,
//                       fontWeight:
//                           isSelected ? FontWeight.w700 : FontWeight.w500,
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     subtitle,
//                     style: TextStyle(
//                       color: isDark ? Colors.white54 : AppColors.textMuted,
//                       fontSize: 12,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             Container(
//               width: 22,
//               height: 22,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 border: Border.all(
//                   color: isSelected ? AppColors.primary : (isDark ? Colors.white12 : AppColors.border),
//                   width: isSelected ? 6 : 2,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


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
    final textTheme = Theme.of(context).textTheme;
 
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Payment Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(AppSizes.screenPaddingH),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Info banner
                        Container(
                          padding: const EdgeInsets.all(AppSizes.base),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.info
                                    .withValues(alpha: isDark ? 0.20 : 0.12),
                                AppColors.info
                                    .withValues(alpha: isDark ? 0.06 : 0.03),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(AppSizes.radiusLg),
                            border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: AppColors.info,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.wallet,
                                  size: 19,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: AppSizes.md),
                              Expanded(
                                child: Text(
                                  'Add your payment details to receive withdrawals. '
                                  'You can use UPI (fastest) or a bank account.',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textBody,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSizes.xxl),
 
                        _SectionHeader(
                          title: 'Payment method',
                          isDark: isDark,
                        ),
                        const SizedBox(height: AppSizes.md),
                        _PaymentModeOption(
                          icon: LucideIcons.smartphone,
                          label: 'UPI ID',
                          subtitle: 'Fastest — instant transfer',
                          isSelected: _paymentMode == 'upi',
                          onTap: () => setState(() => _paymentMode = 'upi'),
                          isFirst: true,
                        ),
                        const SizedBox(height: AppSizes.md),
                        _PaymentModeOption(
                          icon: LucideIcons.landmark,
                          label: 'Bank Account',
                          subtitle: 'NEFT/IMPS transfer',
                          isSelected: _paymentMode == 'bank',
                          onTap: () => setState(() => _paymentMode = 'bank'),
                          isFirst: false,
                        ),
                        const SizedBox(height: AppSizes.xxl),
 
                        if (_paymentMode == 'upi') ...[
                          _SectionHeader(
                            title: 'UPI details',
                            isDark: isDark,
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
                          _SectionHeader(
                            title: 'Bank account details',
                            isDark: isDark,
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
                          const SizedBox(height: AppSizes.base),
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
                          const SizedBox(height: AppSizes.base),
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
                          const SizedBox(height: AppSizes.base),
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
                          label:
                              _isSaving ? 'Saving...' : 'Save Payment Details',
                          icon: LucideIcons.save,
                          isLoading: _isSaving,
                          onPressed: _isSaving ? null : _saveDetails,
                        ),
                        const SizedBox(height: AppSizes.xxxl),
                      ],
                    ),
                  ),
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
    final accent = isDark ? AppColors.primaryLight : AppColors.primary;
    final idleBorder =
        isDark ? Colors.white.withValues(alpha: 0.10) : AppColors.border;
 
    OutlineInputBorder outline(Color color, {double width = 1}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: BorderSide(color: color, width: width),
      );
    }
 
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      cursorColor: accent,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: isDark ? Colors.white : AppColors.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 58, minHeight: 34),
        labelStyle: TextStyle(
          color: isDark ? Colors.white54 : AppColors.textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.white24 : AppColors.textPlaceholder,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        border: outline(idleBorder),
        enabledBorder: outline(idleBorder),
        focusedBorder: outline(accent, width: 1.6),
        errorBorder: outline(AppColors.error.withValues(alpha: 0.7)),
        focusedErrorBorder: outline(AppColors.error, width: 1.6),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.base, vertical: AppSizes.base),
        errorStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.error,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
 
class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
 
  const _SectionHeader({required this.title, required this.isDark});
 
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: isDark ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
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
    final accent = isDark ? AppColors.primaryLight : AppColors.primary;
    final radius = BorderRadius.circular(AppSizes.radiusLg);
 
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected
            ? accent.withValues(alpha: isDark ? 0.10 : 0.05)
            : Theme.of(context).cardColor,
        borderRadius: radius,
        border: Border.all(
          color: isSelected
              ? accent
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : AppColors.border),
          width: isSelected ? 1.6 : 1,
        ),
        boxShadow: (isDark || isSelected) ? null : AppDecorations.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.base, vertical: AppSizes.base),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : AppColors.background),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white54 : AppColors.textMuted),
                  ),
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
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? accent : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? accent
                          : (isDark ? Colors.white24 : AppColors.border),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(LucideIcons.check,
                          size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
 