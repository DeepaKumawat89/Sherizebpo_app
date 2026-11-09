import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';
 
/// Production-ready Admin Login Screen.
///
/// Authenticates admin users via email + password (Firebase Auth),
/// validates Firestore role == 'admin', and navigates to Admin Dashboard.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({Key? key}) : super(key: key);
 
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}
 
class _AdminLoginScreenState extends State<AdminLoginScreen> {
  static const Color _headerIndigo = Color(0xFF6366F1);
  static const Color _referenceDeepIndigo = Color(0xFF3C2FE3);
  static const Color _referenceIndigo = Color(0xFF4638E5);
  static const Color _referenceBlueViolet = Color(0xFF5144E7);
  static const Color _referenceViolet = Color(0xFF675BE9);
  static const Color _referenceSoftViolet = Color(0xFF8176EA);
  static const Color _referenceLavenderViolet = Color(0xFF9B91F0);
 
  static const LinearGradient _blueReferenceGradient = LinearGradient(
    colors: [
      _referenceDeepIndigo,
      _referenceIndigo,
      _referenceBlueViolet,
      _referenceViolet,
      _referenceSoftViolet,
      _referenceLavenderViolet,
    ],
    stops: [0.0, 0.20, 0.42, 0.64, 0.84, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
 
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
 
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
 
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
 
  // ─── Login Handler ───────────────────────────────────────────
  Future<void> _handleLogin() async {
    // Clear previous error
    setState(() => _errorMessage = null);
 
    // Validate form
    if (!_formKey.currentState!.validate()) return;
 
    // Prevent double-tap
    if (_isLoading) return;
 
    setState(() => _isLoading = true);
 
    final authService = Provider.of<AuthService>(context, listen: false);
    final result = await authService.adminLogin(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
 
    if (!mounted) return;
 
    if (result == null) {
      // Success — navigate to the role picker & clear stack. The admin chooses
      // which of their assigned roles to work as before landing on the dashboard.
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.adminRoleSelect,
        (route) => false,
      );
    } else {
      // Error — show message
      setState(() {
        _isLoading = false;
        _errorMessage = result;
      });
    }
  }
 
  InputDecoration _buildInputDecoration(
    BuildContext _, {
    required String labelText,
    required IconData icon,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: const TextStyle(color: AppColors.textPlaceholder),
      labelStyle: const TextStyle(
        color: AppColors.textLabel,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 10, right: 6),
        child: Icon(
          icon,
          size: 19,
          color: AppColors.primary,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 360;
    const inputTextStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.textDark,
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _headerIndigo,
      body: Stack(
        children: [
          // ── Background: gradient header + rounded white sheet ──────────
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  flex: 34,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _headerIndigo,
                                _referenceIndigo.withValues(alpha: 0.95),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -60,
                        right: -50,
                        child: Container(
                          width: 190,
                          height: 190,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 70,
                        left: -70,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 66,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppSizes.radiusXxl),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  isCompact ? AppSizes.base : AppSizes.screenPaddingH,
                  isCompact ? AppSizes.sm : AppSizes.md,
                  isCompact ? AppSizes.base : AppSizes.screenPaddingH,
                  AppSizes.xxl + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Logo + title (on the indigo header) ───────────
                      Container(
                        width: isCompact ? 96 : 112,
                        height: isCompact ? 96 : 112,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/sherize_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: AppSizes.base),
                      Text(
                        'Admin Login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isCompact ? 22 : 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sign in to access the admin panel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 26),
 
                      // ── Login card ────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  _referenceDeepIndigo.withValues(alpha: 0.14),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Error Banner (Nested) ──────────────
                            if (_errorMessage != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppSizes.md),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.error.withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(AppSizes.radiusLg),
                                  border: Border.all(
                                    color:
                                        AppColors.error.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.alertCircle,
                                      color: AppColors.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSizes.lg),
                            ],
 
                            // ── Login Form ────────────────────────
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Email Field ───────────────
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    style: inputTextStyle,
                                    decoration: _buildInputDecoration(
                                      context,
                                      labelText: 'Email address',
                                      icon: LucideIcons.mail,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.lg),
 
                                  // ── Password Field ────────────
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _handleLogin(),
                                    style: inputTextStyle,
                                    decoration: _buildInputDecoration(
                                      context,
                                      labelText: 'Password',
                                      hintText: '••••••••',
                                      icon: LucideIcons.lock,
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(() =>
                                            _obscurePassword =
                                                !_obscurePassword),
                                        icon: Icon(
                                          _obscurePassword
                                              ? LucideIcons.eyeOff
                                              : LucideIcons.eye,
                                          size: 18,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xxl),
 
                                  // ── Login Button ──────────────
                                  Container(
                                    width: double.infinity,
                                    height: AppSizes.buttonHeightLg,
                                    decoration: BoxDecoration(
                                      gradient: _isLoading
                                          ? LinearGradient(
                                              colors: [
                                                _referenceDeepIndigo
                                                    .withValues(
                                                  alpha: 0.60,
                                                ),
                                                _referenceSoftViolet
                                                    .withValues(
                                                  alpha: 0.60,
                                                ),
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            )
                                          : _blueReferenceGradient,
                                      borderRadius: BorderRadius.circular(
                                        AppSizes.radiusLg,
                                      ),
                                      boxShadow: _isLoading
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: _referenceDeepIndigo
                                                    .withValues(alpha: 0.30),
                                                blurRadius: 18,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(
                                          AppSizes.radiusLg,
                                        ),
                                        onTap:
                                            _isLoading ? null : _handleLogin,
                                        child: Center(
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2.5,
                                                  ),
                                                )
                                              : const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Login as Admin',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        letterSpacing: 0.1,
                                                      ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Icon(
                                                      LucideIcons.arrowRight,
                                                      size: 18,
                                                      color: Colors.white,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSizes.md),
 
                            // ── Back to Worker Login ──────────────
                            TextButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      Navigator.of(context)
                                          .pushReplacementNamed(
                                        AppRoutes.login,
                                      );
                                    },
                              icon: const Icon(
                                LucideIcons.arrowLeft,
                                size: 16,
                                color: AppColors.textMuted,
                              ),
                              label: const Text(
                                'Back to Login',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.lg),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.shieldCheck,
                              size: 14, color: AppColors.textMuted),
                          SizedBox(width: 6),
                          Text(
                            'Authorized personnel only',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}