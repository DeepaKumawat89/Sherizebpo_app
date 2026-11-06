import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../core/constants/constants.dart';
import '../services/auth_service.dart';

class MaintenanceOverlay extends StatelessWidget {
  const MaintenanceOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.construction, size: 80, color: AppColors.error),
              const SizedBox(height: AppSizes.xl),
              Text(
                'System under Maintenance',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                'We are currently performing scheduled maintenance to improve your experience. Please check back later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : AppColors.textBody,
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              
              // Optional: Provide a logout button in case they need to switch account
              TextButton.icon(
                onPressed: () => context.read<AuthService>().logout(),
                icon: const Icon(LucideIcons.logOut, size: 18),
                label: const Text('Logout'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
