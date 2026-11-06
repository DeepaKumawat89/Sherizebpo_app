import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../routes.dart';
import '../../services/verification_service.dart';

/// Central post-login checkpoint.
///
/// Shown immediately after OTP success (and after Google Sign-In for
/// first-time users). Reads Firestore verification flags and routes:
///
///   ┌──────────────────────────────────────────────────────────┐
///   │  emailVerified == true  →  /dashboard  (returning user)  │
///   │  emailVerified == false →  /email      (new user flow)   │
///   └──────────────────────────────────────────────────────────┘
class VerifyGateScreen extends StatefulWidget {
  const VerifyGateScreen({Key? key}) : super(key: key);

  @override
  State<VerifyGateScreen> createState() => _VerifyGateScreenState();
}

class _VerifyGateScreenState extends State<VerifyGateScreen> {
  final _verificationService = VerificationService();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Run gate check in next frame so context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  Future<void> _runGate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Not authenticated at all — go back to login
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (_) => false,
      );
      return;
    }

    try {
      final status = await _verificationService.getStatus(user.uid);

      if (!mounted) return;

      if (status.emailVerified) {
        // ── Returning verified user ───────────────────────────
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.dashboard,
          (_) => false,
        );
      } else {
        // ── New user or incomplete registration ───────────────
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.email,
          (_) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not verify account status. Tap retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: _error != null
              ? _buildError()
              : _buildLoading(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSizes.lg),
        Text(
          'Checking your account…',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.screenPaddingH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle, color: AppColors.error, size: 48),
          const SizedBox(height: AppSizes.lg),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSizes.xl),
          ElevatedButton(
            onPressed: () {
              setState(() => _error = null);
              _runGate();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
