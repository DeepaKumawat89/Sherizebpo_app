import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/core/constants/app_constants.dart';
import 'package:human_bpo/main.dart' show scaffoldMessengerKey;
import 'package:human_bpo/screens/settings/settings_screen.dart';
import 'package:human_bpo/services/auth_service.dart';
import 'package:human_bpo/services/credit_config_service.dart';
import 'package:human_bpo/services/security_service.dart';
import 'package:provider/provider.dart';

void main() {
  for (final outcome in ['success', 'unavailable', 'platform-error']) {
    testWidgets('account deletion email handles $outcome', (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? launchedUrl;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'launch');
        launchedUrl = (call.arguments as Map)['url'] as String;
        if (outcome == 'platform-error') {
          throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
        }
        return outcome == 'success';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthService()),
            ChangeNotifierProvider(create: (_) => CreditConfigService()),
            ChangeNotifierProvider(create: (_) => SecurityService()),
          ],
          child: MaterialApp(
            scaffoldMessengerKey: scaffoldMessengerKey,
            home: const SettingsScreen(),
          ),
        ),
      );
      final deletionAction = find.text('Request Account Deletion');
      await tester.ensureVisible(deletionAction);
      await tester.tap(deletionAction);
      await tester.pumpAndSettle();

      expect(launchedUrl, isNotNull);
      final email = Uri.parse(launchedUrl!);
      expect(email.scheme, 'mailto');
      expect(email.path, AppConstants.supportEmail);
      expect(email.query, isNot(contains('+')));
      expect(email.queryParameters['subject'], 'Sherize account deletion request');
      expect(
        email.queryParameters['body'],
        'Please delete my Sherize account and associated personal data.\n\nRegistered email or Employee ID: ',
      );
      expect(
        find.text('Could not open email. Contact ${AppConstants.supportEmail}.'),
        outcome == 'success' ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}