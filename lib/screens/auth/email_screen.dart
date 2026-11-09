import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';
 
class EmailScreen extends StatefulWidget {
  const EmailScreen({Key? key}) : super(key: key);
 
  @override
  State<EmailScreen> createState() => _EmailScreenState();
}
 
class _EmailScreenState extends State<EmailScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
 
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
 
  void _showSnackBar(String message, Color color) {
    if (color == AppColors.success) {
      SnackBarUtils.showSuccess(message);
    } else if (color == AppColors.error) {
      SnackBarUtils.showError(message);
    } else {
      SnackBarUtils.showInfo(message);
    }
  }
 
  Future<void> _sendVerification() async {
    
    if (!_formKey.currentState!.validate()) return;
 
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
 
    final authService = context.read<AuthService>();
    final error = await authService.sendEmailVerification(email);
 
    if (error == null) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.emailVerify, arguments: {'email': email});
    } else {
      _showSnackBar(error, AppColors.error);
      
      // If the session is truly dead, send them back to login
      if (error.contains('Session expired') || error.contains('signed in')) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
      }
    }
 
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Back to login and sign out
        context.read<AuthService>().logout();
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: const Icon(LucideIcons.arrowLeft,
                  size: 20, color: AppColors.textDark),
            ),
            onPressed: () {
              context.read<AuthService>().logout();
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
            },
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPaddingH),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSizes.md),
 
                          // ── Icon ───────────────────────────────
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 92,
                                    height: 92,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      gradient: AppDecorations.primaryGradient,
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.32),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(LucideIcons.mail,
                                        size: 26, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSizes.lg),
                          Text(
                            'Enter Email',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Text(
                            'Please provide your email address for account recovery and important updates.',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.textMuted,
                                      height: 1.5,
                                    ),
                          ),
                          const SizedBox(height: AppSizes.xxxl),
 
                          // ── Field card ─────────────────────────
                          Container(
                            padding: const EdgeInsets.all(AppSizes.lg),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.borderLight),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Email Address',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: AppColors.textLabel,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: AppSizes.sm),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textDark,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. name@example.com',
                                    hintStyle: const TextStyle(
                                      color: AppColors.textPlaceholder,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    filled: true,
                                    fillColor: AppColors.surfaceElevated,
                                    prefixIcon: const Icon(LucideIcons.mail,
                                        size: 19, color: AppColors.primary),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: AppSizes.md, vertical: 17),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                      borderSide: const BorderSide(
                                          color: AppColors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                      borderSide: const BorderSide(
                                          color: AppColors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                      borderSide: const BorderSide(
                                          color: AppColors.primary, width: 2),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                      borderSide: const BorderSide(
                                          color: AppColors.error),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg),
                                      borderSide: const BorderSide(
                                          color: AppColors.error, width: 2),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter your email address';
                                    }
                                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                                      return 'Please enter a valid email address';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: AppSizes.xl),
                          CustomButton(
                            label: 'Send Verification Link',
                            onPressed: _sendVerification,
                            isLoading: _isLoading,
                            isDisabled: _isLoading,
                          ),
                          const SizedBox(height: AppSizes.xxxl),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}