import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:human_bpo/screens/settings/passcode_screen.dart';
import 'package:human_bpo/services/auth_service.dart';
import 'package:human_bpo/services/security_service.dart';
import 'package:human_bpo/routes.dart';

class TestAuth extends AuthService {
  final logoutResult = Completer<void>();
  bool logoutCalled = false;

  @override
  Future<void> logout() {
    logoutCalled = true;
    return logoutResult.future;
  }
}

class TestSecurity extends SecurityService {
  bool locked = true;
  bool cleared = false;

  @override
  bool get isLocked => locked;

  @override
  Future<void> clearPasscode() async {
    cleared = true;
    locked = false;
    notifyListeners();
  }
}

void main() {
  Future<void> mount(WidgetTester tester, TestAuth auth, TestSecurity security) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<SecurityService>.value(value: security),
      ],
      child: Consumer<SecurityService>(builder: (context, security, _) => MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Protected content')),
        routes: {AppRoutes.login: (_) => const Scaffold(body: Text('Login destination'))},
        builder: (context, child) => Stack(children: [
          child!,
          if (security.isLocked)
            HeroControllerScope.none(child: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => PasscodeScreen(mode: PasscodeMode.lock, navigatorKey: navigatorKey),
            ))),
        ]),
      )),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('forgot passcode dialog is visible above lock; cancel preserves lock', (tester) async {
    final auth = TestAuth();
    final security = TestSecurity();
    await mount(tester, auth, security);
    await tester.tap(find.text('Forgot Passcode?'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(auth.logoutCalled, isFalse);
    expect(security.cleared, isFalse);
    expect(find.byType(PasscodeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset keeps lock until logout succeeds and opens login', (tester) async {
    final auth = TestAuth();
    final security = TestSecurity();
    await mount(tester, auth, security);
    await tester.tap(find.text('Forgot Passcode?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(auth.logoutCalled, isTrue);
    expect(security.cleared, isFalse);
    expect(find.byType(PasscodeScreen), findsOneWidget);
    auth.logoutResult.complete();
    await tester.pumpAndSettle();
    expect(security.cleared, isTrue);
    expect(find.text('Login destination'), findsOneWidget);
    expect(find.byType(PasscodeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout failure preserves passcode and shows recoverable error', (tester) async {
    final auth = TestAuth();
    final security = TestSecurity();
    await mount(tester, auth, security);
    await tester.tap(find.text('Forgot Passcode?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    auth.logoutResult.completeError(StateError('Synthetic logout failure'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(security.cleared, isFalse);
    expect(find.text('Unable to reset the passcode. Please try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}