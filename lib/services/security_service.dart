import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityService extends ChangeNotifier {
  static const String _passcodeKey = 'user_passcode';
  static const String _biometricsEnabledKey = 'biometrics_enabled';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _isPasscodeEnabled = false;
  bool _isBiometricsEnabled = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  String? _biometricError;
  
  bool get isPasscodeEnabled => _isPasscodeEnabled;
  bool get isBiometricsEnabled => _isBiometricsEnabled;
  bool get isLocked => _isLocked;
  bool get isAuthenticating => _isAuthenticating;
  String? get biometricError => _biometricError;

  Future<void> init() async {
    // Check if passcode exists in secure storage
    final passcode = await _secureStorage.read(key: _passcodeKey);
    _isPasscodeEnabled = passcode != null && passcode.isNotEmpty;

    // Check SharedPreferences for biometrics toggle (non-sensitive)
    final prefs = await SharedPreferences.getInstance();
    _isBiometricsEnabled = prefs.getBool(_biometricsEnabledKey) ?? false;

    // If passcode is enabled, the app should start locked
    if (_isPasscodeEnabled) {
      _isLocked = true;
    }

    notifyListeners();
  }

  Future<void> setPasscode(String pin) async {
    await _secureStorage.write(key: _passcodeKey, value: pin);
    _isPasscodeEnabled = true;
    notifyListeners();
  }

  Future<bool> verifyPasscode(String pin) async {
    final storedPin = await _secureStorage.read(key: _passcodeKey);
    if (storedPin == pin) {
      _isLocked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> clearPasscode() async {
    await _secureStorage.delete(key: _passcodeKey);
    _isPasscodeEnabled = false;
    _isLocked = false;
    
    // Also disable biometrics
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricsEnabledKey, false);
    _isBiometricsEnabled = false;
    
    notifyListeners();
  }

  Future<bool> setBiometricsEnabled(bool enabled) async {
    if (_isAuthenticating) return false;
    if (enabled && (!_isPasscodeEnabled || !await _authenticateBiometrics())) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricsEnabledKey, enabled);
    _isBiometricsEnabled = enabled;
    notifyListeners();
    return true;
  }

  Future<bool> authenticateWithBiometrics() async {
    if (!_isBiometricsEnabled || !_isPasscodeEnabled) return false;
    final authenticated = await _authenticateBiometrics();
    if (authenticated && _isBiometricsEnabled && _isPasscodeEnabled) {
      _isLocked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> _authenticateBiometrics() async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    _biometricError = null;
    notifyListeners();
    try {
      if (!await _localAuth.canCheckBiometrics) {
        _biometricError = 'Biometrics are unavailable on this device. Use your passcode.';
        return false;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Verify your identity for Sherize',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: false,
        ),
      );

      if (!didAuthenticate) {
        _biometricError = 'Biometric verification was not completed. Try again or use your passcode.';
      }
      return didAuthenticate;
    } on PlatformException catch (error) {
      if (error.code == auth_error.notEnrolled || error.code == auth_error.passcodeNotSet) {
        _biometricError = 'Set up fingerprint or face unlock in your device settings first.';
      } else if (error.code == auth_error.lockedOut || error.code == auth_error.permanentlyLockedOut) {
        _biometricError = 'Biometrics are temporarily locked. Use your passcode.';
      } else {
        _biometricError = 'Biometrics are unavailable. Use your passcode and try again later.';
      }
    } catch (_) {
      _biometricError = 'Biometrics are unavailable. Use your passcode and try again later.';
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
    return false;
  }

  void lockApp() {
    if (_isPasscodeEnabled && !_isLocked) {
      _isLocked = true;
      notifyListeners();
    }
  }
}
