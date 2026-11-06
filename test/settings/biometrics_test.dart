import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:human_bpo/services/security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/local_auth');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late SecurityService security;
  late bool hardware;
  late bool result;
  String? errorCode;
  Completer<bool>? pending;
  late int prompts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'user_passcode': '2468'});
    hardware = true;
    result = true;
    errorCode = null;
    pending = null;
    prompts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableBiometrics') return hardware ? ['fingerprint'] : <String>[];
      if (call.method == 'authenticate') {
        prompts++;
        expect(call.arguments['biometricOnly'], isTrue);
        expect(call.arguments['useErrorDialogs'], isFalse);
        if (errorCode != null) throw PlatformException(code: errorCode!);
        return pending == null ? result : pending!.future;
      }
      throw StateError('Unexpected biometric method: ${call.method}');
    });
    security = SecurityService();
    await security.init();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    security.dispose();
  });

  test('enabling requires successful authentication, then biometric unlock works', () async {
    expect(await security.setBiometricsEnabled(true), isTrue);
    expect(security.isBiometricsEnabled, isTrue);
    expect(security.isLocked, isTrue);
    expect(await security.authenticateWithBiometrics(), isTrue);
    expect(security.isLocked, isFalse);
    expect(prompts, 2);
    expect(await security.setBiometricsEnabled(false), isTrue);
    expect(await security.authenticateWithBiometrics(), isFalse);
    expect(prompts, 2);
  });

  for (final failure in ['unsupported', 'cancel', 'NotEnrolled', 'PasscodeNotSet', 'LockedOut', 'PermanentlyLockedOut', 'other']) {
    test('$failure does not enable or unlock and provides feedback', () async {
      hardware = failure != 'unsupported';
      result = failure != 'cancel';
      errorCode = ['unsupported', 'cancel'].contains(failure) ? null : failure;
      expect(await security.setBiometricsEnabled(true), isFalse);
      expect(security.isBiometricsEnabled, isFalse);
      expect(security.isLocked, isTrue);
      expect(security.biometricError, isNotEmpty);
      expect(security.isAuthenticating, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('biometrics_enabled'), isNot(isTrue));
      expect(await security.verifyPasscode('2468'), isTrue);
    });
  }

  test('failed unlock preserves lock and allows PIN fallback', () async {
    await security.setBiometricsEnabled(true);
    result = false;
    expect(await security.authenticateWithBiometrics(), isFalse);
    expect(security.isLocked, isTrue);
    expect(await security.verifyPasscode('0000'), isFalse);
    expect(security.isLocked, isTrue);
    expect(await security.verifyPasscode('2468'), isTrue);
  });

  test('overlapping requests open only one native prompt', () async {
    await security.setBiometricsEnabled(true);
    pending = Completer<bool>();
    final unlock = security.authenticateWithBiometrics();
    expect(security.isAuthenticating, isTrue);
    expect(await security.authenticateWithBiometrics(), isFalse);
    pending!.complete(true);
    expect(await unlock, isTrue);
    expect(prompts, 2);
  });
}