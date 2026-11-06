import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pinput/pinput.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';
import '../../routes.dart';
import '../../widgets/custom_button.dart';

class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({Key? key}) : super(key: key);

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _verificationService = VerificationService();
  final _otpController = TextEditingController();

  String _email = '';
  bool _isLoading = false;
  bool _isResending = false;

  Timer? _resendTimer;
  int _secondsRemaining = 60;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _email = args?['email'] as String? ?? '';
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 60;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
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

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) return;

    setState(() => _isLoading = true);

    final error = await _verificationService.verifyEmailOtp(otp, _email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error == null) {
      // OTP verified successfully
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.success,
        (_) => false,
      );
    } else {
      _showSnackBar(error, AppColors.warning);
      _otpController.clear();
    }
  }

  Future<void> _resendLink() async {
    if (_email.isEmpty || _secondsRemaining > 0) return;
    setState(() => _isResending = true);

    final authService = context.read<AuthService>();
    final error = await authService.sendEmailVerification(_email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (error == null) {
      _showSnackBar('Verification code resent to $_email', AppColors.success);
      _startTimer();
    } else {
      _showSnackBar(error, AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: const TextStyle(
        fontSize: 22,
        color: AppColors.textDark,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.primary, width: 2),
      borderRadius: BorderRadius.circular(12),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Go back to Email entry screen
        Navigator.pushReplacementNamed(context, AppRoutes.email, arguments: {'email': _email});
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textDark),
            onPressed: () {
              Navigator.pushReplacementNamed(context, AppRoutes.email, arguments: {'email': _email});
            },
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.xl),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.mailOpen,
                        color: AppColors.primary, size: 40),
                  ),
                ),
                const SizedBox(height: AppSizes.xxxl),
                Text(
                  'Enter Verification Code',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  'We\'ve sent a 6-digit code to\n$_email',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: AppSizes.xxl),
                Center(
                  child: Pinput(
                    length: 6,
                    controller: _otpController,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: focusedPinTheme,
                    showCursor: true,
                    onCompleted: (pin) => _verifyOtp(),
                  ),
                ),
                const SizedBox(height: AppSizes.xxxl),
                CustomButton(
                  label: 'Verify Code',
                  isLoading: _isLoading,
                  isDisabled: _isLoading || _isResending || _otpController.text.length != 6,
                  onPressed: _verifyOtp,
                ),
                const SizedBox(height: AppSizes.lg),
                TextButton(
                  onPressed: (_isResending || _isLoading || _secondsRemaining > 0)
                      ? null
                      : _resendLink,
                  child: _isResending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _secondsRemaining > 0
                              ? 'Resend Code in ${_secondsRemaining}s'
                              : 'Resend Code',
                          style: TextStyle(
                            color: _secondsRemaining > 0
                                ? AppColors.textLight
                                : AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
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
}
