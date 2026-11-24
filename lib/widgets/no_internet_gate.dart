import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/constants.dart';
import '../services/network_connectivity_service.dart';

/// Keeps the current navigator mounted and covers it only while internet
/// access is unavailable. This preserves auth state, routes, and cached data.
class NoInternetGate extends StatelessWidget {
  const NoInternetGate({
    super.key,
    required this.child,
    this.startupChild,
  });

  final Widget child;
  final Widget? startupChild;

  @override
  Widget build(BuildContext context) {
    final network = context.watch<NetworkConnectivityService>();
    final blocked = network.status != InternetStatus.online;
    final initialCheck = network.status == InternetStatus.checking;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: ExcludeSemantics(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: child),
          ),
        ),
        if (initialCheck)
          startupChild ?? child
        else if (network.isOffline)
          _NoInternetScreen(
            checking: network.isChecking,
            onRetry: network.checkNow,
          ),
      ],
    );
  }
}

class _NoInternetScreen extends StatelessWidget {
  const _NoInternetScreen({
    required this.checking,
    required this.onRetry,
  });

  final bool checking;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryMuted),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.wifiOff,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'No Internet Connection',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sherize will reconnect automatically. Check your Wi-Fi or mobile data, then try again.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textMuted,
                              height: 1.55,
                            ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: checking ? null : onRetry,
                          icon: checking
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.refreshCw, size: 19),
                          label: Text(checking ? 'Checking...' : 'Retry'),
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
