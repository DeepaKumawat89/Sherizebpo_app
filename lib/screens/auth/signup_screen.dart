import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_popup_menu.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isVerifyingEmail = false;
  bool _emailVerificationSent = false;
  bool _emailVerified = false;
  String _verificationSentForEmail = '';
  String _gender = 'Female';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ────────────────────────────────────────────────────

  void _showSnackBar(String message, Color color) {
    if (color == AppColors.success) {
      SnackBarUtils.showSuccess(message);
    } else if (color == AppColors.error) {
      SnackBarUtils.showError(message);
    } else {
      SnackBarUtils.showInfo(message);
    }
  }

  /// Validates name, age (≥ 20), and email format before sending
  bool _validateBeforeSend() {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnackBar('Please enter your full name.', AppColors.error);
      return false;
    }
    final age = int.tryParse(_ageCtrl.text.trim());
    if (age == null || age < 20) {
      _showSnackBar('You must be at least 20 years old to register.', AppColors.error);
      return false;
    }
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showSnackBar('Please enter a valid email address.', AppColors.error);
      return false;
    }
    return true;
  }

  // ─── Send Verification Email via Cloud Function ─────────────────
  //
  // WHY Cloud Function?
  //   The client-side linkWithCredential() and updateEmail() both throw
  //   [firebase_auth/requires-recent-login] even for newly signed-in users.
  //   The Cloud Function uses the Firebase Admin SDK which has elevated
  //   privileges and sets the email directly — no recent-login required.
  //
  Future<void> _sendVerificationEmail() async {
    if (!_validateBeforeSend()) return;

    final email = _emailCtrl.text.trim();
    setState(() => _isVerifyingEmail = true);

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('sendEmailVerificationLink');
      await callable.call({'email': email});

      setState(() {
        _emailVerificationSent = true;
        _emailVerified = false;
        _verificationSentForEmail = email;
      });

      _showSnackBar(
        'Verification link sent to $email. Check your inbox or spam folder.',
        AppColors.success,
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? 'Failed to send verification email.';
      _showSnackBar(msg, AppColors.error);
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', AppColors.error);
    } finally {
      if (mounted) setState(() => _isVerifyingEmail = false);
    }
  }

  // ─── Check If Email Was Verified ────────────────────────────────

  Future<void> _checkEmailVerification() async {
    setState(() => _isVerifyingEmail = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final freshUser = FirebaseAuth.instance.currentUser;
      if (freshUser != null && freshUser.emailVerified) {
        setState(() => _emailVerified = true);
        _showSnackBar('Email verified successfully!', AppColors.success);
      } else {
        _showSnackBar(
          'Email not verified yet. Please check your inbox or spam and click the link.',
          AppColors.warning,
        );
      }
    } catch (e) {
      _showSnackBar('Error checking verification: ${e.toString()}', AppColors.error);
    } finally {
      if (mounted) setState(() => _isVerifyingEmail = false);
    }
  }

  // ─── Reset Email (allow user to change and resend) ──────────────

  void _changeEmail() {
    setState(() {
      _emailVerificationSent = false;
      _emailVerified = false;
      _verificationSentForEmail = '';
    });
  }

  // ─── Save Profile to Firestore ───────────────────────────────────

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_emailVerified) {
      _showSnackBar('Please verify your email address to continue.', AppColors.error);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _nameCtrl.text.trim(),
          'fullName': _nameCtrl.text.trim(),
          'gender': _gender,
          'age': int.parse(_ageCtrl.text.trim()),
          'email': _emailCtrl.text.trim(),
          'emailVerified': true,
          'kycStatus': 'pending',
          'onboardingStatus': 'applicant', // new joiners browse/apply to jobs until hired
          'walletBalance': 0,
          'totalTasksCompleted': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.dashboard, (_) => false,
          );
        }
      }
    } catch (e) {
      _showSnackBar('Failed to save profile: ${e.toString()}', AppColors.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'Unknown';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Complete Profile',
          style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textDark,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.screenPaddingH),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.md),
                Text(
                  'Tell us about yourself',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  'Please complete your profile to continue. For ${AppConstants.appName}, '
                  'registration requires you to be at least 20 years old.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppSizes.xxxl),

                // ── Mobile Number (read-only) ──────────────────────
                _buildLabel('Mobile Number'),
                const SizedBox(height: AppSizes.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md, vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.smartphone, color: AppColors.textMuted, size: 20),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          userPhone,
                          style: const TextStyle(
                            color: AppColors.textDark, fontSize: 15, fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(LucideIcons.checkCircle2, color: AppColors.success, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.lg),

                // ── Full Name ──────────────────────────────────────
                _buildLabel('Full Name'),
                const SizedBox(height: AppSizes.sm),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDecoration('Enter your full name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter your full name' : null,
                ),
                const SizedBox(height: AppSizes.lg),

                // ── Gender ─────────────────────────────────────────
                _buildLabel('Gender'),
                const SizedBox(height: AppSizes.sm),
                CustomPopupMenuFormField<String>(
                  initialValue: _gender,
                  decoration: _inputDecoration('Select gender'),
                  items: const [
                    CustomPopupMenuItem(value: 'Female', label: 'Female'),
                    CustomPopupMenuItem(value: 'Male', label: 'Male'),
                    CustomPopupMenuItem(value: 'Other', label: 'Other'),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? 'Female'),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Please select your gender' : null,
                ),
                const SizedBox(height: AppSizes.lg),

                // ── Age ────────────────────────────────────────────
                _buildLabel('Age'),
                const SizedBox(height: AppSizes.sm),
                TextFormField(
                  controller: _ageCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration('Enter your age (20+)'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your age';
                    final age = int.tryParse(v.trim());
                    if (age == null) return 'Invalid age';
                    if (age < 20) return 'You must be at least 20 years old';
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.lg),

                // ── Email Address ──────────────────────────────────
                _buildLabel('Email Address'),
                const SizedBox(height: AppSizes.sm),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  // Lock field once verification was sent (until "Change" is tapped)
                  enabled: !_emailVerificationSent && !_emailVerified,
                  decoration: _inputDecoration('Enter your valid email id').copyWith(
                    suffixIcon: _emailVerified
                        ? const Icon(LucideIcons.checkCircle2, color: AppColors.success)
                        : null,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your email';
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSizes.md),

                // ── Email Verification Buttons ─────────────────────
                if (!_emailVerified) ...[
                  if (_emailVerificationSent) ...[
                    // "Check Status" + "Change Email" row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: _outlinedStyle(AppColors.primary),
                            onPressed: _isVerifyingEmail ? null : _checkEmailVerification,
                            icon: _isVerifyingEmail
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.refreshCw, size: 18),
                            label: const Text(
                              'Check Verification Status',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        OutlinedButton.icon(
                          style: _outlinedStyle(AppColors.error),
                          onPressed: _isVerifyingEmail ? null : _changeEmail,
                          icon: const Icon(LucideIcons.pencil, size: 16, color: AppColors.error),
                          label: const Text(
                            'Change',
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSizes.sm),
                      child: Text(
                        'Verification link sent to $_verificationSentForEmail. '
                        'Check your inbox or spam, then tap "Check Verification Status". '
                        'Wrong email? Tap "Change".',
                        style: const TextStyle(color: AppColors.primary, fontSize: 13),
                      ),
                    ),
                  ] else ...[
                    // "Send Verification Email" button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: _outlinedStyle(AppColors.primary),
                        onPressed: _isVerifyingEmail ? null : _sendVerificationEmail,
                        icon: _isVerifyingEmail
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.mail, size: 18),
                        label: const Text(
                          'Send Verification Email',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],

                if (_emailVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSizes.sm),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.checkCircle2, color: AppColors.success, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Email verified: ${_emailCtrl.text.trim()}',
                          style: const TextStyle(
                            color: AppColors.success, fontSize: 13, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: AppSizes.xxxl),

                // ── Complete Signup ────────────────────────────────
                CustomButton(
                  label: 'Complete Signup',
                  onPressed: _saveProfile,
                  isLoading: _isLoading,
                  isDisabled: _isLoading || !_emailVerified,
                ),

                const SizedBox(height: AppSizes.md),

                // ── Skip Option ────────────────────────────────────
                TextButton(
                  onPressed: () {
                    if (mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context, AppRoutes.dashboard, (_) => false,
                      );
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Skip / Do later',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),

                const SizedBox(height: AppSizes.xxxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Reusable Widget Helpers ──────────────────────────────────────

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.textLabel, fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    );
  }

  ButtonStyle _outlinedStyle(Color color) {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      side: BorderSide(color: color.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
    );
  }
}
