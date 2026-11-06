import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../services/security_service.dart';
import '../../services/auth_service.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';

enum PasscodeMode { setup, verifySetup, lock, enterCurrentToChange }

class PasscodeScreen extends StatefulWidget {
  final PasscodeMode mode;
  final GlobalKey<NavigatorState>? navigatorKey;

  const PasscodeScreen({Key? key, required this.mode, this.navigatorKey}) : super(key: key);

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _firstPin = '';
  String _errorText = '';
  bool _resetting = false;
  late PasscodeMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    
    // Automatically trigger biometrics if in lock mode
    if (_currentMode == PasscodeMode.lock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerBiometrics();
      });
    }
  }

  Future<void> _triggerBiometrics() async {
    if (!mounted || _resetting) return;
    final security = context.read<SecurityService>();
    if (security.isBiometricsEnabled && !security.isAuthenticating) {
      final success = await security.authenticateWithBiometrics();
      if (!success && mounted) {
        setState(() => _errorText = security.biometricError ?? 'Use your passcode to unlock.');
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCompleted(String pin) async {
    if (_resetting) return;
    final security = context.read<SecurityService>();
    setState(() => _errorText = '');

    switch (_currentMode) {
      case PasscodeMode.setup:
        setState(() {
          _firstPin = pin;
          _currentMode = PasscodeMode.verifySetup;
          _pinController.clear();
        });
        _focusNode.requestFocus();
        break;

      case PasscodeMode.verifySetup:
        if (pin == _firstPin) {
          await security.setPasscode(pin);
          if (mounted) {
            SnackBarUtils.showSuccess('Passcode set successfully');
            Navigator.pop(context);
          }
        } else {
          setState(() {
            _errorText = 'Passcodes do not match. Try again.';
            _pinController.clear();
          });
          _focusNode.requestFocus();
        }
        break;

      case PasscodeMode.lock:
        final isValid = await security.verifyPasscode(pin);
        if (!mounted) return;
        if (isValid) {
          // SecurityService automatically updates _isLocked = false
          // Main.dart will remove this screen
        } else {
          setState(() {
            _errorText = 'Incorrect passcode';
            _pinController.clear();
          });
          _focusNode.requestFocus();
        }
        break;

      case PasscodeMode.enterCurrentToChange:
        final isValid = await security.verifyPasscode(pin);
        if (!mounted) return;
        if (isValid) {
          setState(() {
            _currentMode = PasscodeMode.setup;
            _pinController.clear();
          });
          _focusNode.requestFocus();
        } else {
          setState(() {
            _errorText = 'Incorrect passcode';
            _pinController.clear();
          });
          _focusNode.requestFocus();
        }
        break;
    }
  }

  String get _titleText {
    switch (_currentMode) {
      case PasscodeMode.setup:
        return 'Set a Passcode';
      case PasscodeMode.verifySetup:
        return 'Verify Passcode';
      case PasscodeMode.lock:
        return 'Enter Passcode';
      case PasscodeMode.enterCurrentToChange:
        return 'Enter Current Passcode';
    }
  }

  String get _subtitleText {
    switch (_currentMode) {
      case PasscodeMode.setup:
        return 'Choose a 4-digit PIN for extra security.';
      case PasscodeMode.verifySetup:
        return 'Re-enter your 4-digit PIN to confirm.';
      case PasscodeMode.lock:
        return 'Please enter your PIN to unlock the app.';
      case PasscodeMode.enterCurrentToChange:
        return 'Verify your identity to change the PIN.';
    }
  }

  Future<void> _handleForgotPasscode() async {
    if (_resetting) return;
    final navigator = widget.navigatorKey?.currentState ?? Navigator.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Forgot Passcode?',
            style: TextStyle(
                color: isDark ? Colors.white : AppColors.textDark,
                fontWeight: FontWeight.bold)),
        content: Text(
            'To reset your passcode, you must log out and log back in. Do you want to log out now?',
            style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textBody)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final auth = context.read<AuthService>();
      final security = context.read<SecurityService>();
      setState(() => _resetting = true);
      try {
        await auth.logout();
        navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
        await security.clearPasscode();
      } catch (_) {
        if (mounted) {
          setState(() => _errorText = 'Unable to reset the passcode. Please try again.');
        }
      } finally {
        if (mounted) setState(() => _resetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultPinTheme = PinTheme(
      width: 60,
      height: 70,
      textStyle: TextStyle(
        fontSize: 24,
        color: isDark ? Colors.white : AppColors.textDark,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: isDark ? Colors.white10 : AppColors.border,
        ),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.primary, width: 2),
    );

    final errorPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.error, width: 2),
      color: AppColors.errorBg.withValues(alpha: isDark ? 0.1 : 1.0),
    );

    return PopScope(
      // Prevent back navigation while the app is locked.
      canPop: _currentMode != PasscodeMode.lock,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: _currentMode == PasscodeMode.lock
            ? null // No back button on lock screen
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                iconTheme: IconThemeData(
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_currentMode == PasscodeMode.lock)
                  const Spacer(),
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSizes.xl),
                Text(
                  _titleText,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  _subtitleText,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : AppColors.textBody,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.xxl),
                Pinput(
                  enabled: !_resetting,
                  length: 4,
                  controller: _pinController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  obscuringCharacter: '•',
                  autofocus: true,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: focusedPinTheme,
                  errorPinTheme: errorPinTheme,
                  forceErrorState: _errorText.isNotEmpty,
                  onCompleted: _onCompleted,
                  onChanged: (value) {
                    if (_errorText.isNotEmpty) {
                      setState(() => _errorText = '');
                    }
                  },
                ),
                if (_errorText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSizes.md),
                    child: Text(
                      _errorText,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSizes.xxl),
                
                // Show Biometrics Button if locked and enabled
                if (_currentMode == PasscodeMode.lock &&
                    context.watch<SecurityService>().isBiometricsEnabled)
                  TextButton.icon(
                    onPressed: _resetting || context.watch<SecurityService>().isAuthenticating ? null : _triggerBiometrics,
                    icon: const Icon(Icons.fingerprint, size: 28),
                    label: const Text('Use Biometrics'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.xl, vertical: AppSizes.md),
                    ),
                  ),
                  
                const Spacer(),
                if (_currentMode == PasscodeMode.lock)
                  TextButton(
                    onPressed: _resetting ? null : _handleForgotPasscode,
                    child: Text(
                      'Forgot Passcode?',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
