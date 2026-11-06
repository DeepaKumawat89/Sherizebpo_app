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

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputFillColor = isDark ? Colors.white.withValues(alpha: 0.07) : AppColors.background.withValues(alpha: 0.5);
    final inputTextStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: isDark ? Colors.white : AppColors.textDark,
    );
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH,
              vertical: AppSizes.xxl,
            ),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Logo ──────────────────────────────
                      Transform.translate(
                        offset: const Offset(20, 0), // Nudge right for visual centering
                        child: Image.asset(
                          'assets/images/sherize_logo.png',
                          width: 240,
                          height: 240,
                          fit: BoxFit.contain,
                        ),
                      ),

                      Transform.translate(
                        offset: const Offset(0, -60), // Reduced offset to prevent overlap with logo text
                        child: Column(
                          children: [
                            // ── Title ─────────────────────────────
                            const Text(
                              'Admin Login',
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: AppSizes.xs),
                            const Text(
                              'Sign in to access the admin panel',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: AppSizes.md), // Precise gap before card

                            // ── Error Banner (Nested) ──────────────
                            if (_errorMessage != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppSizes.md),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(AppSizes.radiusMd),
                                  border: Border.all(
                                    color: AppColors.error.withValues(alpha: 0.3),
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

                            // ── Login Form Card (Nested) ──────────
                            Container(
                              padding: const EdgeInsets.all(AppSizes.xl),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius:
                                    BorderRadius.circular(AppSizes.radiusLg),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Email Field ───────────────
                                    const Text(
                                      'Email Address',
                                      style: TextStyle(
                                        color: AppColors.textBody,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.sm),
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      style: inputTextStyle,
                                      decoration: InputDecoration(
                                        hintText: 'admin@human_bpo.com',
                                        hintStyle: TextStyle(
                                          color: isDark ? Colors.white38 : AppColors.textPlaceholder,
                                        ),
                                        prefixIcon: Icon(
                                          LucideIcons.mail,
                                          size: 18,
                                          color: isDark ? Colors.white38 : null,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 16,
                                        ),
                                        filled: true,
                                        fillColor: inputFillColor,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: const BorderSide(
                                            color: AppColors.primary,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.xl),

                                    // ── Password Field ────────────
                                    const Text(
                                      'Password',
                                      style: TextStyle(
                                        color: AppColors.textBody,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.sm),
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _handleLogin(),
                                      style: inputTextStyle,
                                      decoration: InputDecoration(
                                        hintText: '••••••••',
                                        hintStyle: TextStyle(
                                          color: isDark ? Colors.white38 : AppColors.textPlaceholder,
                                        ),
                                        prefixIcon: Icon(
                                          LucideIcons.lock,
                                          size: 18,
                                          color: isDark ? Colors.white38 : null,
                                        ),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(() =>
                                              _obscurePassword =
                                                  !_obscurePassword),
                                          icon: Icon(
                                            _obscurePassword
                                                ? LucideIcons.eyeOff
                                                : LucideIcons.eye,
                                            size: 18,
                                            color: isDark ? Colors.white54 : null,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          vertical: 16,
                                          horizontal: 16,
                                        ),
                                        filled: true,
                                        fillColor: inputFillColor,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: BorderSide.none,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd),
                                          borderSide: const BorderSide(
                                            color: AppColors.primary,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppSizes.xxl),

                                    // ── Login Button ──────────────
                                    SizedBox(
                                      width: double.infinity,
                                      height: AppSizes.buttonHeight,
                                      child: ElevatedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              AppColors.primary
                                                  .withValues(alpha: 0.6),
                                          disabledForegroundColor: Colors.white
                                              .withValues(alpha: 0.8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppSizes.radiusMd,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
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
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(LucideIcons.logIn,
                                                      size: 20),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Login as Admin',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSizes.md),

                            // ── Back to Worker Login ──────────────
                            TextButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      Navigator.of(context).pushReplacementNamed(
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
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

