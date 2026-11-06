import 'package:flutter/material.dart';
import '../core/constants/constants.dart';
import 'custom_button.dart';

/// Standard Dialog overlay layout nodes with consistent SaaS design grids.
class CustomDialog extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  const CustomDialog({
    Key? key,
    required this.title,
    required this.message,
    this.icon,
    this.iconColor = AppColors.primary,
    this.primaryLabel = 'Confirm',
    this.onPrimaryPressed,
    this.secondaryLabel = 'Cancel',
    this.onSecondaryPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSizes.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.1),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color:
                        (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: iconColor ?? AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.md),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textBody,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            Row(
              children: [
                if (secondaryLabel != null)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                      ),
                      onPressed:
                          onSecondaryPressed ?? () => Navigator.pop(context),
                      child: Text(secondaryLabel!),
                    ),
                  ),
                if (secondaryLabel != null && primaryLabel != null)
                  const SizedBox(width: AppSizes.base),
                if (primaryLabel != null)
                  Expanded(
                    child: CustomButton(
                      label: primaryLabel!,
                      onPressed: onPrimaryPressed,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
