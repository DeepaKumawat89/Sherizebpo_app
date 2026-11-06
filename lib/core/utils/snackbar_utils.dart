import 'package:flutter/material.dart';
import '../constants/constants.dart';
import '../../main.dart'; // To access scaffoldMessengerKey

class SnackBarUtils {
  /// Shows a success snackbar at the footer of the current screen.
  static void showSuccess(String message) {
    _showSnackBar(
      message: message,
      backgroundColor: AppColors.success,
      icon: Icons.check_circle_outline,
    );
  }

  /// Shows an error snackbar at the footer of the current screen.
  static void showError(String message) {
    _showSnackBar(
      message: message,
      backgroundColor: AppColors.error,
      icon: Icons.error_outline,
    );
  }

  /// Shows an info/warning snackbar at the footer of the current screen.
  static void showInfo(String message) {
    _showSnackBar(
      message: message,
      backgroundColor: AppColors.info,
      icon: Icons.info_outline,
    );
  }

  static void _showSnackBar({
    required String message,
    required Color backgroundColor,
    required IconData icon,
  }) {
    final state = scaffoldMessengerKey.currentState;
    if (state == null) return;

    // Clear existing snackbars to prevent overlapping
    state.clearSnackBars();

    state.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
