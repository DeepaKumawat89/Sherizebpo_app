import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/constants.dart';
import '../core/utils/snackbar_utils.dart';
import '../services/credit_config_service.dart';

/// Small "Designed & Developed by Novantix" credit shown on the splash,
/// login, and settings screens. The website line is tappable and opens
/// [AppConstants.developerWebsiteUrl] in an external browser.
class DeveloperCredit extends StatelessWidget {
  /// Colour of the credit line. Defaults to [AppColors.textMuted].
  final Color? color;

  /// Colour of the tappable website line. Defaults to [AppColors.primary].
  final Color? linkColor;

  const DeveloperCredit({
    Key? key,
    this.color,
    this.linkColor,
  }) : super(key: key);

  Future<void> _openWebsite(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      SnackBarUtils.showError('Could not open the website');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<CreditConfigService>();
    // The developer can hide the credit entirely from the remote config.
    if (!config.enabled) return const SizedBox.shrink();

    final Color textColor = color ?? AppColors.textMuted;
    final Color linkClr = linkColor ?? AppColors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          config.credit,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textColor,
            height: 1.4,
          ),
        ),
        Text(
          config.company,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => _openWebsite(config.websiteUrl),
          child: Text(
            config.website,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: linkClr,
              decoration: TextDecoration.underline,
              decorationColor: linkClr,
            ),
          ),
        ),
      ],
    );
  }
}
