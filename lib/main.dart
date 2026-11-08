import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';

import 'core/constants/constants.dart';
import 'core/theme/theme.dart';
import 'routes.dart';
import 'services/services.dart';
import 'services/security_service.dart';
import 'screens/settings/passcode_screen.dart';
import 'widgets/maintenance_overlay.dart';
import 'widgets/app_update_gate.dart';
import 'widgets/developer_credit.dart';

/// Application entry point.
///
/// Initialises Firebase, local storage, sets up the Provider tree, and
/// launches [MaterialApp] with the named-route system.
///
/// Wrapped in [ErrorLoggingService.runGuarded] to catch all uncaught errors
/// globally and persist them to Firestore for admin review.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  ErrorLoggingService.runGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    const useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
    await Firebase.initializeApp(
      options: useEmulators
          ? const FirebaseOptions(
              apiKey: 'demo-only',
              appId: '1:123456789:web:demo',
              messagingSenderId: '123456789',
              projectId: 'demo-sherize-workflow',
              authDomain: 'demo-sherize-workflow.firebaseapp.com',
              storageBucket: 'demo-sherize-workflow.appspot.com',
            )
          : DefaultFirebaseOptions.currentPlatform,
    );

    if (useEmulators) {
      await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
      FirebaseFunctions.instance.useFunctionsEmulator('127.0.0.1', 5001);
      await FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
    }

    // Lock to portrait orientation (mobile only)
    if (!kIsWeb) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Set system UI style
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          ChangeNotifierProvider(create: (_) => SecurityService()),
          ChangeNotifierProvider(create: (_) => PlatformSettingsService()),
          ChangeNotifierProvider(create: (_) => CreditConfigService()),
          Provider(
            create: (_) => ApiService(),
            dispose: (_, api) => api.dispose(),
          ),
          Provider(create: (_) => TaskService()),
        ],
        child: const SherizeApp(),
      ),
    );

    await WidgetsBinding.instance.endOfFrame;
    if (!useEmulators) {
      unawaited(_initializeNotifications());
    }
  });
}

Future<void> _initializeNotifications() async {
  try {
    await NotificationService().initialize(navigatorKey: navigatorKey);
  } catch (e) {
    debugPrint('NotificationService init skipped: $e');
  }
}

class SherizeApp extends StatefulWidget {
  const SherizeApp({Key? key}) : super(key: key);

  @override
  State<SherizeApp> createState() => _SherizeAppState();
}

class _SherizeAppState extends State<SherizeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Restore session/security first; remote configuration can wait one more
    // frame so it does not compete with initial rendering.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<AuthService>().init());
      unawaited(context.read<SecurityService>().init());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<PlatformSettingsService>().init();
        context.read<CreditConfigService>().init();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock app when it goes into background or is minimized.
    // Excluding AppLifecycleState.inactive prevents locking on system notifications/drawers.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      context.read<SecurityService>().lockApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authInitialized =
        context.select<AuthService, bool>((service) => service.isInitialized);
    final routingState = context.select<
        AuthService,
        ({
          bool developer,
          bool authenticated,
          bool restoreFailed,
          bool admin,
          String? adminRole,
          String role,
        })>((service) => (
          developer: service.isDeveloper,
          authenticated: service.isAuthenticated,
          restoreFailed: service.sessionRestoreFailed,
          admin: service.isAdmin,
          adminRole: service.activeAdminRole,
          role: service.role,
        ));
    final isLocked =
        context.select<SecurityService, bool>((service) => service.isLocked);
    final maintenanceMode = context.select<PlatformSettingsService, bool>(
        (service) => service.maintenanceMode);
    final auth = context.read<AuthService>();

    return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          themeMode: ThemeMode.light,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          // Show Splash until AuthService has completed its initial check.
          home: authInitialized
              ? _buildInitialScreen(auth, routingState)
              : const _SplashScreen(),
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          navigatorObservers: [AppRoutes.routeObserver],
          builder: (context, child) {
            // Only block if maintenance is ON, user is authenticated, and NOT a super_admin.
            final bool shouldBlock = maintenanceMode &&
                routingState.authenticated &&
                routingState.role != 'super_admin' &&
                !routingState.developer;

            return AppUpdateGate(child: Stack(
              children: [
                if (child != null) (shouldBlock ? const MaintenanceOverlay() : child),
                if (isLocked)
                  HeroControllerScope.none(
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => PasscodeScreen(mode: PasscodeMode.lock, navigatorKey: navigatorKey),
                      ),
                    ),
                  ),
              ],
            ));
          },
        );
  }


  /// Returns the correct initial screen based on auth state.
  ///
  /// Priority:
  ///  1. Authenticated user  → /verify-gate (skips onboarding & login entirely)
  ///  2. Unauthenticated, onboarding not done → /onboarding
  ///  3. Unauthenticated, onboarding done     → /login
  Widget _buildInitialScreen(
    AuthService auth,
    ({
      bool developer,
      bool authenticated,
      bool restoreFailed,
      bool admin,
      String? adminRole,
      String role,
    }) routingState,
  ) {
    // Authenticated users are never sent back to onboarding or login.
    // Firebase Auth persists the session on device; if currentUser is non-null
    // the user is still signed in and should go directly to their dashboard.
    //
    // IMPORTANT: Do NOT route to /verify-gate on app restart. That screen is
    // only meant for fresh logins (post-OTP). Sending restoring sessions there
    // causes users with emailVerified=false in Firestore to be dumped to the
    // email entry screen on every restart instead of their dashboard.
    if (routingState.developer) {
      return const _RouteRedirect(route: AppRoutes.devDashboard);
    }
    if (routingState.authenticated) {
      if (routingState.restoreFailed) {
        return Scaffold(body: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Unable to restore your workspace.'),
            TextButton(onPressed: auth.init, child: const Text('Retry')),
          ],
        )));
      }
      if (routingState.admin) {
        return _RouteRedirect(route: AppRoutes.adminDashboard,
            arguments: routingState.adminRole);
      }
      return const _RouteRedirect(route: '/dashboard');
    }
    // Unauthenticated visitors see the onboarding intro first, then land on the
    // public job openings page (no OTP / phone / email). Hired workers log in
    // from there with their Employee ID + password, or "Login with mobile number".
    return const _RouteRedirect(route: AppRoutes.onboarding);
  }
}

/// Immediately navigates to the given named route after the first frame.
/// This avoids the MaterialApp home/initialRoute toggle issue.
class _RouteRedirect extends StatefulWidget {
  final String route;
  final Object? arguments;
  const _RouteRedirect({required this.route, this.arguments});

  @override
  State<_RouteRedirect> createState() => _RouteRedirectState();
}

class _RouteRedirectState extends State<_RouteRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(widget.route, arguments: widget.arguments);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _SplashScreen();
  }
}

/// Minimal splash screen shown while the Firebase auth session is being restored.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 32),
                  child: DeveloperCredit(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
