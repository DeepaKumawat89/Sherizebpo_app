import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/constants/constants.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';
import '../../widgets/developer_credit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.useEmployeeId = false});

  final bool useEmployeeId;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late bool _useEmployeeId;
  bool _mobileLogin = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _useEmployeeId = widget.useEmployeeId;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _employeeIdCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _changeMethod({required bool mobile, bool employee = false}) {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _passwordCtrl.clear();
    setState(() {
      _mobileLogin = mobile;
      _useEmployeeId = employee;
      _obscurePassword = true;
      _error = null;
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldownSeconds--);
      if (_cooldownSeconds == 0) timer.cancel();
    });
  }

  Future<void> _login() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      final error = _useEmployeeId
          ? await auth.loginWithEmployeeId(
              _employeeIdCtrl.text.trim(), _passwordCtrl.text)
          : await auth.loginWithEmailPassword(
              _emailCtrl.text.trim(), _passwordCtrl.text);
      if (!mounted) return;
      if (error == null) {
        TextInput.finishAutofillContext();
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.dashboard, (_) => false);
      } else {
        setState(() => _error = error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Login failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendOtp() async {
    if (_loading ||
        _cooldownSeconds > 0 ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final phone = '+91${_phoneCtrl.text.trim()}';
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });
    _startCooldown();
    try {
      await context.read<AuthService>().sendOtp(
        phone,
        onVerified: () {
          if (!mounted || !_mobileLogin) return;
          Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.verifyGate, (_) => false);
        },
        onCodeSent: (verificationId) {
          if (!mounted ||
              !_mobileLogin ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          setState(() => _loading = false);
          Navigator.pushNamed(context, AppRoutes.otp, arguments: {
            'phone': phone,
            'verificationId': verificationId,
          });
        },
        onError: (error) {
          if (!mounted || !_mobileLogin) return;
          setState(() {
            _loading = false;
            _error = error;
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to send OTP. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        errorMaxLines: 3,
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );

  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_mobileLogin)
              TextFormField(
                key: const ValueKey('login-phone'),
                controller: _phoneCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 10,
                decoration: _decoration('Mobile number', LucideIcons.phone)
                    .copyWith(prefixText: '+91 ', counterText: ''),
                validator: (value) =>
                    RegExp(r'^\d{10}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Enter a valid 10-digit mobile number',
                onFieldSubmitted: (_) => _sendOtp(),
              )
            else ...[
              TextFormField(
                key:
                    ValueKey(_useEmployeeId ? 'login-employee' : 'login-email'),
                controller: _useEmployeeId ? _employeeIdCtrl : _emailCtrl,
                enabled: !_loading,
                keyboardType: _useEmployeeId
                    ? TextInputType.text
                    : TextInputType.emailAddress,
                textCapitalization: _useEmployeeId
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                textInputAction: TextInputAction.next,
                autofillHints: [
                  _useEmployeeId ? AutofillHints.username : AutofillHints.email
                ],
                autocorrect: false,
                enableSuggestions: false,
                decoration: _decoration(
                  _useEmployeeId ? 'Employee ID' : 'Email address',
                  _useEmployeeId ? LucideIcons.user : LucideIcons.mail,
                ),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (_useEmployeeId) {
                    return RegExp(r'^SHR-?(?:\d{4}|\d{6})$',
                                caseSensitive: false)
                            .hasMatch(input)
                        ? null
                        : 'Enter a valid Employee ID (e.g. SHR-4450)';
                  }
                  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)
                      ? null
                      : 'Enter a valid email address';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('login-password'),
                controller: _passwordCtrl,
                enabled: !_loading,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: _decoration('Password', LucideIcons.lock).copyWith(
                  suffixIcon: IconButton(
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: _loading
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                        _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                        size: 20),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password'
                    : null,
                onFieldSubmitted: (_) => _login(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.errorDark)),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading || (_mobileLogin && _cooldownSeconds > 0)
                  ? null
                  : _mobileLogin
                      ? _sendOtp
                      : _login,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                          semanticsLabel: 'Signing in'),
                    )
                  : Text(_mobileLogin
                      ? _cooldownSeconds > 0
                          ? 'Resend in ${_cooldownSeconds}s'
                          : 'Send OTP'
                      : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Do you want to exit Sherize?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: ClipRect(
                        key: const ValueKey('login-logo'),
                        child: Align(
                          widthFactor: 0.5,
                          heightFactor: 0.5,
                          alignment: const Alignment(-0.1, -0.4),
                          child: Image.asset(
                            'assets/images/sherize_logo.png',
                            width: 320,
                            height: 320,
                            semanticLabel: 'Sherize',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _mobileLogin ? 'Mobile login' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                                letterSpacing: 0,
                              ),
                    ),
                    const SizedBox(height: 24),
                    if (!_mobileLogin) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Email')),
                          ButtonSegment(
                              value: true, label: Text('Employee ID')),
                        ],
                        selected: {_useEmployeeId},
                        showSelectedIcon: false,
                        direction: MediaQuery.sizeOf(context).width < 360 ||
                                MediaQuery.textScalerOf(context).scale(14) > 20
                            ? Axis.vertical
                            : Axis.horizontal,
                        onSelectionChanged: _loading
                            ? null
                            : (selection) => _changeMethod(
                                mobile: false, employee: selection.single),
                        style: SegmentedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                          selectedBackgroundColor: AppColors.primarySoft,
                          selectedForegroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.textBody,
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    _buildForm(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _changeMethod(mobile: !_mobileLogin),
                      icon: Icon(
                        _mobileLogin
                            ? LucideIcons.mail
                            : LucideIcons.smartphone,
                        size: 18,
                      ),
                      label: Text(
                        _mobileLogin
                            ? 'Login with email'
                            : 'Login with mobile number',
                        textAlign: TextAlign.center,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        foregroundColor: AppColors.textBody,
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: [
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.of(context)
                                  .pushReplacementNamed(AppRoutes.publicJobs),
                          icon: const Icon(LucideIcons.briefcase, size: 16),
                          label: const Text('Job Portal'),
                          style: TextButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              foregroundColor: AppColors.textMuted),
                        ),
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pushNamed(
                                  context, AppRoutes.adminLogin),
                          icon: const Icon(LucideIcons.shieldCheck, size: 16),
                          label: const Text('Admin Login'),
                          style: TextButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              foregroundColor: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const DeveloperCredit(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
