import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
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
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textDark),
            onPressed: () {
              context.read<AuthService>().logout();
              Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
            },
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSizes.xl),
                  Text(
                    'Enter Email',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'Please provide your email address for account recovery and important updates.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                  const SizedBox(height: AppSizes.xxxl),
                  Text(
                    'Email Address',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.textLabel,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'e.g. name@example.com',
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(LucideIcons.mail, color: AppColors.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 16),
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
                  const Spacer(),
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
      ),
    );
  }
}
