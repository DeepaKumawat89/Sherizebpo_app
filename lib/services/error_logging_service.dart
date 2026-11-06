import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Global error logging service that captures Flutter framework errors,
/// uncaught async errors, and platform errors, then persists them to
/// a Firestore `error_logs` collection for admin review.
///
/// Inspired by Lovable AI's ErrorBoundary + global error listeners pattern.
///
/// Usage:
/// ```dart
/// void main() async {
///   ErrorLoggingService.runGuarded(() async {
///     WidgetsFlutterBinding.ensureInitialized();
///     // ... Firebase init, etc.
///     runApp(const MyApp());
///   });
/// }
/// ```
class ErrorLoggingService {
  ErrorLoggingService._();

  /// Lazy getter — only accessed after Firebase.initializeApp() completes.
  /// Using a static field caused [core/duplicate-app] because FirebaseFirestore.instance
  /// was evaluated at class-load time, before Firebase was initialized.
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static final Future<String> _appVersion = _loadAppVersion();

  /// Wraps the app in a guarded zone that catches all uncaught errors
  /// and logs them to Firestore. Also hooks into Flutter framework errors.
  static void runGuarded(Future<void> Function() appRunner) {
    // Catch Flutter framework errors (rendering, layout, etc.)
    FlutterError.onError = (FlutterErrorDetails details) {
      // Still print to console for debug
      FlutterError.presentError(details);
      _logError(
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        source: 'flutter_framework',
        metadata: {
          'library': details.library ?? 'unknown',
          'context': details.context?.toString(),
          'informationCollector': details.informationCollector
              ?.call()
              .map((e) => e.toString())
              .take(5)
              .toList(),
        },
      );
    };

    // Catch platform-level errors that Flutter doesn't handle
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        print('[Platform Error Caught] $error');
      }
      _logError(
        message: error.toString(),
        stack: stack.toString(),
        source: 'platform_dispatcher',
      );
      return true; // Prevent crash
    };

    // Catch all uncaught async errors via runZonedGuarded
    runZonedGuarded(
      () async {
        await appRunner();
      },
      (error, stackTrace) {
        _logError(
          message: error.toString(),
          stack: stackTrace.toString(),
          source: 'zone_uncaught',
        );
      },
    );
  }

  /// Manually log an error (for try/catch blocks that want persistent logging).
  static Future<void> logManualError({
    required String message,
    String? stack,
    String source = 'manual',
    Map<String, dynamic>? metadata,
  }) async {
    await _logError(
      message: message,
      stack: stack,
      source: source,
      metadata: metadata,
    );
  }

  /// Internal method that writes the error to Firestore.
  /// Silently fails if write fails (don't throw during error handling).
  static Future<void> _logError({
    required String message,
    String? stack,
    required String source,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final appVersion = await _appVersion;

      await _firestore.collection('error_logs').add({
        'userId': user?.uid,
        'errorMessage': _truncate(message, 2000),
        'errorStack': _truncate(stack, 5000),
        'errorSource': source,
        'metadata': metadata,
        'resolved': false,
        'createdAt': FieldValue.serverTimestamp(),
        'appVersion': appVersion,
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {
      // Silent fail — do NOT throw during error handling
      if (kDebugMode) {
        print('[ErrorLoggingService] Failed to log error to Firestore');
      }
    }
  }

  static Future<String> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.buildNumber.isEmpty
          ? packageInfo.version
          : '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Truncate long strings to avoid Firestore document size limits.
  static String? _truncate(String? input, int maxLength) {
    if (input == null) return null;
    return input.length > maxLength ? input.substring(0, maxLength) : input;
  }
}
