import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:human_bpo/routes.dart';
import 'package:human_bpo/screens/auth/employee_login_screen.dart';
import 'package:human_bpo/screens/auth/login_screen.dart';
import 'package:human_bpo/screens/auth/otp_screen.dart';
import 'package:human_bpo/services/auth_service.dart';
import 'package:human_bpo/services/credit_config_service.dart';

class _TestAuthService extends AuthService {
  String? email;
  String? employeeId;
  String? password;
  String? phone;
  String? loginError;
  bool throwOnLogin = false;
  int loginCalls = 0;
  int otpCalls = 0;
  Completer<String?>? pendingLogin;
  void Function(String)? codeSent;
  void Function(String)? otpFailed;
  VoidCallback? phoneVerified;
  String? verifiedSession;
  int verificationCalls = 0;

  @override
  Future<String?> verifyOtp({required String smsCode, String? verificationId}) async {
    verifiedSession = verificationId;
    verificationCalls++;
    return 'Test verification response';
  }

  @override
  Future<String?> loginWithEmailPassword(String email, String password) async {
    this.email = email;
    this.password = password;
    loginCalls++;
    if (throwOnLogin) throw StateError('Test failure');
    return pendingLogin == null ? loginError : await pendingLogin!.future;
  }

  @override
  Future<String?> loginWithEmployeeId(
      String employeeId, String password) async {
    this.employeeId = employeeId;
    this.password = password;
    loginCalls++;
    return loginError;
  }

  @override
  Future<void> sendOtp(
    String phoneNumber, {
    required Function(String) onCodeSent,
    required Function(String) onError,
    VoidCallback? onVerified,
  }) async {
    phone = phoneNumber;
    otpCalls++;
    codeSent = onCodeSent;
    otpFailed = onError;
    phoneVerified = onVerified;
  }
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  _TestAuthService? auth,
  Widget home = const LoginScreen(),
  double textScale = 1,
  double keyboardInset = 0,
  Size viewport = const Size(800, 900),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(
            value: auth ?? _TestAuthService()),
        ChangeNotifierProvider(create: (_) => CreditConfigService()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: home,
        routes: {
          AppRoutes.dashboard: (_) =>
              const Scaffold(body: Text('Dashboard destination')),
          AppRoutes.otp: (context) => Scaffold(
              body: Text('OTP: ${ModalRoute.of(context)!.settings.arguments}')),
          AppRoutes.publicJobs: (_) =>
              const Scaffold(body: Text('Jobs destination')),
          AppRoutes.adminLogin: (_) =>
              const Scaffold(body: Text('Admin destination')),
            AppRoutes.verifyGate: (_) =>
              const Scaffold(body: Text('Verification destination')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('automatic phone verification leaves the OTP route', (tester) async {
    final auth = _TestAuthService();
    await _pumpLogin(tester, auth: auth);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-phone')), '9999999999');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    auth.codeSent!('test-session');
    await tester.pumpAndSettle();
    auth.phoneVerified!();
    await tester.pumpAndSettle();
    expect(find.text('Verification destination'), findsOneWidget);
    expect(find.textContaining('OTP:'), findsNothing);
  });

  testWidgets('OTP resend waits for Firebase and verifies the replacement session',
      (tester) async {
    final auth = _TestAuthService();
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: const RouteSettings(arguments: {
          'phone': '+15555550100', 'verificationId': 'original-session',
        }),
        builder: (_) => const OtpScreen(),
      )),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    expect(auth.otpCalls, 1);
    expect(auth.phone, '+15555550100');
    expect(find.text('Sending OTP...'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump();
    expect(auth.verificationCalls, 0);

    auth.otpFailed!('No internet connection. Please try again.');
    await tester.pump();
    expect(find.text('No internet connection. Please try again.'), findsOneWidget);
    expect(find.text('Resend OTP'), findsOneWidget);
    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    auth.codeSent!('replacement-session');
    await tester.pump();
    expect(find.textContaining('Resend code in'), findsOneWidget);
    expect(find.text('No internet connection. Please try again.'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '654321');
    await tester.pumpAndSettle();
    expect(auth.verificationCalls, 1);
    expect(auth.verifiedSession, 'replacement-session');
    expect(find.text('Test verification response'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('defaults to email and password with alternative login methods',
      (tester) async {
    await _pumpLogin(tester);

    expect(find.widgetWithText(TextFormField, 'Email address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.text('Login with mobile number'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Send OTP'), findsNothing);
    expect(tester.getTopLeft(find.text('Login with mobile number')).dy,
        greaterThan(tester.getBottomLeft(find.byType(Form)).dy));
    expect(tester.getSize(find.byKey(const ValueKey('login-logo'))),
        const Size(160, 160));
  });

  testWidgets('switches to mobile and back to email without stale errors',
      (tester) async {
    await _pumpLogin(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your password'), findsOneWidget);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-password')), findsNothing);
    expect(find.text('Enter your password'), findsNothing);
    await tester.tap(find.text('Login with email'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
  });

  testWidgets('rejects invalid email and empty password without authenticating',
      (tester) async {
    final auth = _TestAuthService();
    await _pumpLogin(tester, auth: auth);
    await tester.enterText(
        find.byKey(const ValueKey('login-email')), 'not-an-email');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(auth.loginCalls, 0);
  });

  testWidgets(
      'email sign-in trims email, preserves password and opens dashboard',
      (tester) async {
    final auth = _TestAuthService()..pendingLogin = Completer<String?>();
    await _pumpLogin(tester, auth: auth);
    await tester.enterText(
        find.byKey(const ValueKey('login-email')), ' worker@example.com ');
    await tester.enterText(
        find.byKey(const ValueKey('login-password')), ' test password ');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(auth.email, 'worker@example.com');
    expect(auth.password, ' test password ');
    expect(auth.loginCalls, 1);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .onSelectionChanged,
        isNull);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-email')))
            .enabled,
        isFalse);
    tester
        .widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey('login-password')),
          matching: find.byType(TextField),
        ))
        .onSubmitted!('');
    expect(auth.loginCalls, 1);
    auth.pendingLogin!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Dashboard destination'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('shows login errors and permits retry after exceptions',
      (tester) async {
    final auth = _TestAuthService()
      ..loginError = 'Incorrect email or password.';
    await _pumpLogin(tester, auth: auth);
    await tester.enterText(
        find.byKey(const ValueKey('login-email')), 'worker@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('login-password')), 'test password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    auth.throwOnLogin = true;
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login failed. Please try again.'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
  });

  testWidgets('password visibility resets and password clears on method switch',
      (tester) async {
    await _pumpLogin(tester);
    await tester.enterText(
        find.byKey(const ValueKey('login-password')), 'test password');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.descendant(
              of: find.byKey(const ValueKey('login-password')),
              matching: find.byType(TextField),
            ))
            .obscureText,
        isFalse);
    await tester.tap(find.text('Employee ID'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('login-password')))
            .controller!
            .text,
        isEmpty);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-employee')), findsOneWidget);
  });

  testWidgets('pushed login hides back arrow in all modes and keeps system back',
      (tester) async {
    await _pumpLogin(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
        MaterialPageRoute<void>(builder: (_) => const EmployeeLoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-employee')), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-phone')), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.tap(find.text('Login with email'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(EmployeeLoginScreen), findsNothing);
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
  });

  for (final employeeId in ['SHR-4450', 'shr123456']) {
    testWidgets('employee route validates and resolves $employeeId',
        (tester) async {
      final auth = _TestAuthService();
      await _pumpLogin(tester, auth: auth, home: const EmployeeLoginScreen());
      expect(find.byKey(const ValueKey('login-email')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('login-employee')), 'EMP1234');
      await tester.enterText(
          find.byKey(const ValueKey('login-password')), 'employee password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(auth.loginCalls, 0);
      expect(find.text('Enter a valid Employee ID (e.g. SHR-4450)'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('login-employee')), employeeId);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(auth.employeeId, employeeId);
      expect(auth.email, isNull);
      expect(auth.password, 'employee password');
      expect(find.text('Dashboard destination'), findsOneWidget);
    });
  }

  testWidgets(
      'mobile validates, waits for callback, routes OTP and keeps cooldown',
      (tester) async {
    final auth = _TestAuthService();
    await _pumpLogin(tester, auth: auth);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-phone')), '123');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(auth.otpCalls, 0);
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('login-phone')), '9999999999');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    expect(auth.phone, '+919999999999');
    expect(auth.otpCalls, 1);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    auth.codeSent!('test-verification');
    await tester.pumpAndSettle();
    expect(
        find.text(
            'OTP: {phone: +919999999999, verificationId: test-verification}'),
        findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.tap(find.text('Login with email'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Send OTP'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
  });

  testWidgets('late OTP callback does not interrupt switching to email',
      (tester) async {
    final auth = _TestAuthService();
    await _pumpLogin(tester, auth: auth);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('login-phone')), '9999999999');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login with email'));
    await tester.pumpAndSettle();
    auth.codeSent!('late-verification');
    auth.otpFailed!('Late SMS error');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
    expect(find.textContaining('OTP:'), findsNothing);
    expect(find.text('Late SMS error'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('OTP failure displays inline and releases method switching',
      (tester) async {
    final auth = _TestAuthService();
    await _pumpLogin(tester, auth: auth);
    await tester.tap(find.text('Login with mobile number'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('login-phone')), '9999999999');
    await tester.tap(find.text('Send OTP'));
    await tester.pump();
    auth.otpFailed!('SMS unavailable. Try again later.');
    await tester.pumpAndSettle();
    expect(find.text('SMS unavailable. Try again later.'), findsOneWidget);
    await tester.tap(find.text('Login with email'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
    expect(find.text('SMS unavailable. Try again later.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(1280, 800)
  ]) {
    testWidgets('login controls and job/admin links remain reachable at $size',
        (tester) async {
      await _pumpLogin(tester, viewport: size);
      final viewport = tester.getRect(find.byType(Scaffold));
      expect(viewport.contains(tester.getCenter(find.text('Employee ID'))),
          isTrue);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.ensureVisible(find.text('Login with mobile number'));
      expect(
          find.text('Login with mobile number').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Login with mobile number'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-phone')), findsOneWidget);
      await tester.ensureVisible(find.text('Job Portal'));
      expect(find.text('Job Portal').hitTestable(), findsOneWidget);
      expect(find.text('Admin Login').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Job Portal'));
      await tester.pumpAndSettle();
      expect(find.text('Jobs destination'), findsOneWidget);
    });
  }

  testWidgets('large text and keyboard inset do not overflow the form',
      (tester) async {
    await _pumpLogin(tester,
        textScale: 2, keyboardInset: 240, viewport: const Size(320, 568));
    await tester.ensureVisible(find.text('Sign in'));
    expect(find.text('Sign in').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('Login with mobile number'));
    expect(find.text('Login with mobile number').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
