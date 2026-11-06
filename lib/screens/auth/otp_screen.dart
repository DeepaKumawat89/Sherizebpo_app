import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../widgets/custom_button.dart';

/// OTP verification screen with 6-digit input, countdown timer,
/// resend functionality, and navigation to Dashboard on success.
class OtpScreen extends StatefulWidget {
  const OtpScreen({Key? key}) : super(key: key);

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // ─── Controllers & Focus Nodes ──────────────────────────────
  final List<TextEditingController> _controllers =
      List.generate(AppConstants.otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(AppConstants.otpLength, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  bool _navigating = false;
  String? _verificationId;
  String? _errorText;

  // ─── Resend Timer ───────────────────────────────────────────
  Timer? _resendTimer;
  int _resendSeconds = 30;
  bool get _canResend => _resendSeconds == 0;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Auto-focus the first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startResendTimer() {
    _resendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  // ─── OTP Helpers ────────────────────────────────────────────
  String get _otpValue => _controllers.map((c) => c.text).join();

  bool get _isOtpComplete => _otpValue.length == AppConstants.otpLength;

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  // ─── Input Handler ──────────────────────────────────────────
  void _onDigitChanged(String value, int index) {
    // Clear error on any input
    setState(() => _errorText = null);

    // OS one-time-code autofill / paste: the whole code arrives in one field.
    // Split it across the boxes and auto-submit.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        for (int i = 0; i < AppConstants.otpLength; i++) {
          _controllers[i].text = i < digits.length ? digits[i] : '';
        }
        final focusIndex =
            (digits.length >= AppConstants.otpLength ? AppConstants.otpLength - 1 : digits.length)
                .clamp(0, AppConstants.otpLength - 1);
        _focusNodes[focusIndex].requestFocus();
        if (_isOtpComplete) {
          FocusScope.of(context).unfocus();
          _onVerify(); // auto-submit once all digits are present
        }
        return;
      }
    }

    if (value.length == 1 && index < AppConstants.otpLength - 1) {
      // Move to next field
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // Move to previous field on backspace
      _focusNodes[index - 1].requestFocus();
    }

    // Auto-verify when all digits are filled
    if (_isOtpComplete) {
      FocusScope.of(context).unfocus();
    }
  }

  // ─── Key Handler (for backspace on empty field) ─────────────
  void _onKeyEvent(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  // ─── Verify OTP ─────────────────────────────────────────────
  Future<void> _onVerify() async {
    if (_isLoading || _isResending) return;

    if (!_isOtpComplete) {
      setState(() =>
          _errorText = 'Please enter all ${AppConstants.otpLength} digits');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final verificationId =
      _verificationId ?? args?['verificationId'] as String?;

    final authService = Provider.of<AuthService>(context, listen: false);
    final errorMsg = await authService.verifyOtp(
      smsCode: _otpValue,
      verificationId: verificationId,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (errorMsg == null) {
      _onVerified();
    } else {
      setState(() => _errorText = errorMsg);
    }
  }

  void _onVerified() {
    if (!mounted || _navigating) return;
    _navigating = true;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.verifyGate, (_) => false);
  }

  // ─── Resend OTP ─────────────────────────────────────────────
  Future<void> _onResend() async {
    if (!_canResend || _isLoading || _isResending) return;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final phone = args?['phone'] as String?;
    if (phone == null || phone.isEmpty) {
      setState(() => _errorText = 'Go back and enter your phone number again.');
      return;
    }
    setState(() {
      _isResending = true;
      _errorText = null;
    });
    _clearOtp();
    try {
      await context.read<AuthService>().sendOtp(
        phone,
        onVerified: _onVerified,
        onCodeSent: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _isResending = false;
          });
          _startResendTimer();
          SnackBarUtils.showSuccess('A new OTP has been sent. Use the latest SMS.');
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isResending = false;
            _errorText = error;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isResending = false;
        _errorText = 'Could not resend OTP. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Read phone from route arguments (passed from LoginScreen)
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final phone =
        args?['phone'] as String? ?? '${AppConstants.countryCode} XXXXX XXXXX';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
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
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: const Icon(
                LucideIcons.arrowLeft,
                size: 20,
                color: AppColors.textDark,
              ),
            ),
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false),
          ),
          title: const Text(
            'Verify OTP',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.xxl),

                // ── Lock Icon ─────────────────────────────
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: AppDecorations.primaryGradient,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.shieldCheck,
                            size: 28,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSizes.xl),

                // ── Heading ───────────────────────────────────
                Center(
                  child: Text(
                    'Enter Verification Code',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Center(
                  child: Text(
                    'We\'ve sent a ${AppConstants.otpLength}-digit code to\n$phone',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ),
                const SizedBox(height: AppSizes.xxxl),

                // ── OTP Input Row ─────────────────────────────
                AutofillGroup(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      AppConstants.otpLength,
                      (index) => _buildOtpBox(index),
                    ),
                  ),
                ),

                // ── Error Text ────────────────────────────────
                if (_errorText != null) ...[
                  const SizedBox(height: AppSizes.md),
                  Center(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSizes.xxxl),

                // ── Verify Button ─────────────────────────────
                CustomButton(
                  label: 'Verify',
                  onPressed: _onVerify,
                  isLoading: _isLoading,
                  isDisabled: !_isOtpComplete || _isResending,
                ),
                const SizedBox(height: AppSizes.xxl),

                // ── Resend Section ────────────────────────────
                Center(
                  child: _canResend
                      ? TextButton(
                          onPressed: _isLoading || _isResending ? null : _onResend,
                          child: Text(
                            _isResending ? 'Sending OTP...' : 'Resend OTP',
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Text(
                          'Resend code in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: AppColors.textPlaceholder,
                            fontSize: 13,
                          ),
                        ),
                ),
                const SizedBox(height: AppSizes.xxxl),

                // ── Security Note ─────────────────────────────
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.shield,
                        size: 14, color: AppColors.textLight),
                    SizedBox(width: AppSizes.xs),
                    Text(
                      'Your data is encrypted and secure',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Single OTP Box ─────────────────────────────────────────
  Widget _buildOtpBox(int index) {
    final bool isFilled = _controllers[index].text.isNotEmpty;
    final bool isFocused = _focusNodes[index].hasFocus;

    return SizedBox(
      width: 52,
      height: 60,
      child: KeyboardListener(
        focusNode: FocusNode(), // wrapper focus node for key events
        onKeyEvent: (event) => _onKeyEvent(event, index),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // Box 0 accepts the full code so the OS one-time-code autofill can
          // deliver it here; _onDigitChanged then distributes it to the rest.
          maxLength: index == 0 ? AppConstants.otpLength : 1,
          autofillHints:
              index == 0 ? const [AutofillHints.oneTimeCode] : null,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.primary,
              ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: isFilled ? AppColors.surfaceVariant : AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: AppSizes.base),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide(
                color: _errorText != null
                    ? AppColors.error
                    : (isFocused ? AppColors.primary : AppColors.border),
                width: isFocused ? 2.0 : 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide(
                color: _errorText != null ? AppColors.error : AppColors.border,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide(
                color: _errorText != null ? AppColors.error : AppColors.primary,
                width: 2.0,
              ),
            ),
          ),
          onChanged: (value) => _onDigitChanged(value, index),
        ),
      ),
    );
  }
}
