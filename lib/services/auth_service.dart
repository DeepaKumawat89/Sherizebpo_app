import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/constants/constants.dart';
import '../core/utils/string_utils.dart';
import 'notification_service.dart';

/// Manages authentication state, token persistence, and user session.
///
/// Integrated with Firebase Authentication (Phone Auth, Google Auth) and local SharedPreferences.
class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _authOverride = auth,
        _firestoreOverride = firestore;

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  String? _token;
  bool _isLoading = false;
  bool _onboardingComplete = false;
  String? _verificationId;
  int _otpRequest = 0;
  int? _resendToken;
  String? _otpPhone;
  Future<String?>? _phoneSignIn;
  ConfirmationResult? _webConfirmationResult; // Store for Web
  bool _isInitialized = false;
  String? _workerId;
  String? _role;
  Set<String> _roles = {};
  String? _activeAdminRole;
  bool _sessionRestoreFailed = false;
  static const adminRoles = [
    'admin',
    'super_admin',
    'task_review_admin',
    'kyc_admin',
    'payment_admin',
    'support_admin'
  ];

  bool get isAdmin => adminRoles.any(_roles.contains);
  String? get activeAdminRole => _activeAdminRole;
  bool get sessionRestoreFailed => _sessionRestoreFailed;

  static Future<void> rememberAdminWorkspace(String userId, String role) async {
    if (!adminRoles.contains(role)) throw ArgumentError.value(role, 'role');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminWorkspace:$userId', role);
  }

  void _restoreProfile(
      Map<String, dynamic> data, SharedPreferences prefs, String userId) {
    _workerId = data['workerId']?.toString();
    _role = data['role']?.toString().trim().toLowerCase() ?? 'worker';
    _roles = {
      role,
      if (data['roles'] is List)
        ...(data['roles'] as List)
            .map((value) => value.toString().trim().toLowerCase())
    };
    final saved = prefs.getString('adminWorkspace:$userId');
    final canRestore = adminRoles.contains(saved) &&
        (_roles.contains(saved) ||
            _roles.contains('admin') ||
            _roles.contains('super_admin'));
    _activeAdminRole = canRestore
        ? saved
        : adminRoles.contains(role)
            ? role
            : adminRoles.where(_roles.contains).firstOrNull;
  }

  String? get token => _token;
  String? get workerId => _workerId;
  String get role => _role ?? 'worker';
  // Trust the live Firebase Auth session status.
  bool get isAuthenticated => _auth.currentUser != null;

  /// True only when the signed-in user holds the developer role AND their
  /// email matches the hardcoded developer anchor. Requiring both means that
  /// merely flipping a Firestore role to 'developer' is not enough to unlock
  /// developer mode.
  bool get isDeveloper {
    final email = _auth.currentUser?.email?.toLowerCase();
    return _role == AppConstants.developerRole &&
        email == AppConstants.developerEmail.toLowerCase();
  }

  bool get isLoading => _isLoading;
  bool get onboardingComplete => _onboardingComplete;
  bool get isInitialized => _isInitialized;

  // ─── Initialise from local storage & Firebase ──────────────────
  Future<void> init() async {
    _isInitialized = false;
    _sessionRestoreFailed = false;
    _role = null;
    _roles = {};
    _activeAdminRole = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(AppConstants.tokenKey);
    _onboardingComplete = prefs.getBool(AppConstants.onboardingKey) ?? false;

    // Check Firebase Auth state directly
    try {
      final user = _auth.currentUser;
      if (user != null) {
        _token = await user.getIdToken().timeout(const Duration(seconds: 10));
        if (_token != null) {
          await prefs.setString(AppConstants.tokenKey, _token!);
        }
        // User is authenticated → they have already completed onboarding.
        // Persist this flag so the app never sends them back to onboarding.
        if (!_onboardingComplete) {
          _onboardingComplete = true;
          await prefs.setBool(AppConstants.onboardingKey, true);
        }

        // Fetch workerId and role from Firestore
        final docSnap = await _firestore
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 10));
        if (!docSnap.exists) throw StateError('User profile unavailable');
        _restoreProfile(docSnap.data()!, prefs, user.uid);
      } else {
        // Session is null, clear the cached token to ensure isAuthenticated is false
        _token = null;
        await prefs.remove(AppConstants.tokenKey);
      }
    } catch (_) {
      _token = null;
      _sessionRestoreFailed = _auth.currentUser != null;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Worker/employee email + password sign-in. Hired workers receive an email
  /// and password from the super admin and sign in with them. Returns null on
  /// success, or a human-readable error message.
  Future<String?> loginWithEmailPassword(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    User? signedInUser;
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      signedInUser = user;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'Authentication failed. Please try again.';
      }
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      _workerId = data?['workerId'];
      _role = data?['role']?.toString().toLowerCase() ?? 'worker';

      final token = await user.getIdToken(true);
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        await prefs.setBool(AppConstants.onboardingKey, true);
        _token = token;
        _onboardingComplete = true;
      }
      await NotificationService().updateToken();
      _isLoading = false;
      notifyListeners();
      return null; // success
    } on FirebaseAuthException catch (e) {
      if (signedInUser != null) await _auth.signOut();
      _isLoading = false;
      notifyListeners();
      switch (e.code) {
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'user-disabled':
          return 'This account has been disabled. Contact support.';
        default:
          return 'Login failed: ${e.message ?? e.code}';
      }
    } catch (_) {
      if (signedInUser != null) await _auth.signOut();
      _isLoading = false;
      notifyListeners();
      return 'Login failed. Please try again.';
    }
  }

  Future<String?> loginWithEmployeeId(
      String employeeId, String password) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('resolveEmployeeLogin')
          .call({'employeeId': employeeId.trim()});
      final loginEmail = result.data?['loginEmail']?.toString() ?? '';
      if (!loginEmail.endsWith('@${AppConstants.employeeLoginDomain}')) {
        return 'Employee ID or password is incorrect.';
      }

      final error = await loginWithEmailPassword(loginEmail, password);
      if (error == 'Incorrect email or password.' ||
          error == 'No account found with this email.') {
        return 'Employee ID or password is incorrect.';
      }
      return error;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'invalid-argument') {
        return 'Enter a valid Employee ID (for example, SHR-4450).';
      }
      return 'Employee ID or password is incorrect.';
    } catch (_) {
      return 'Login failed. Please try again.';
    }
  }

  // ─── OTP Request ─────────────────────────────────────────────
  //
  // On Flutter Web, Firebase Phone Auth requires a reCAPTCHA verifier.
  // The verifier token expires after ~2 minutes, so we must:
  //   1. Create a fresh verifier each time (clear any stale one)
  //   2. Handle `invalid-app-credential` by resetting and retrying
  //
  RecaptchaVerifier? _webRecaptchaVerifier;

  Future<void> sendOtp(
    String phoneNumber, {
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    VoidCallback? onVerified,
  }) async {
    final normalizedPhone = phoneNumber.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      onError('Invalid phone number format.');
      return;
    }
    if (_isLoading) {
      onError('An OTP request is already in progress. Please wait.');
      return;
    }

    final request = ++_otpRequest;
    final resendToken = _otpPhone == normalizedPhone ? _resendToken : null;
    _otpPhone = normalizedPhone;
    _resendToken = null;
    _verificationId = null;
    _webConfirmationResult = null;
    _phoneSignIn = null;
    _isLoading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        // Initialize or reuse the Web invisible reCAPTCHA verifier.
        // When no 'container' is provided, Firebase automatically uses
        // an invisible reCAPTCHA (shown as a modal overlay).
        _webRecaptchaVerifier ??= RecaptchaVerifier(
            auth: FirebaseAuthPlatform.instance,
          );

        try {
          final result = await _auth.signInWithPhoneNumber(
            normalizedPhone,
            _webRecaptchaVerifier,
          );
          if (request != _otpRequest) return;
          _verificationId = result.verificationId;
          _webConfirmationResult = result;
          _isLoading = false;
          notifyListeners();
          onCodeSent(result.verificationId);
        } catch (e) {
          if (request != _otpRequest) return;
          _isLoading = false;
          notifyListeners();

          if (e is FirebaseAuthException) {
            if (e.code == 'invalid-app-credential') {
              // The reCAPTCHA token expired or failed verification.
              // Clear the DOM widget so the next click creates a fresh one.
              _webRecaptchaVerifier?.clear();
              _webRecaptchaVerifier = null;

              onError(
                'Verification failed or expired. Please click "Send OTP" to try again.',
              );
            } else if (e.code == 'too-many-requests') {
              onError(
                  'Too many attempts. Please wait a few minutes and try again.');
            } else if (e.code == 'invalid-phone-number') {
              onError('Invalid phone number format.');
            } else if (e.code == 'network-request-failed') {
              onError('No internet connection. Please try again.');
            } else {
              onError(
                  '[${e.code}] ${e.message ?? "Phone verification failed."}');
            }
          } else {
            onError(e.toString());
          }
        }
        return;
      }

      // ── Native (Android / iOS) flow ──────────────────────────
      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (request != _otpRequest) return;
          final error = await _signInWithCredential(credential);
          if (request != _otpRequest) return;
          if (error == null) {
            onVerified?.call();
          } else {
            onError(error);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (request != _otpRequest) return;
          _isLoading = false;
          notifyListeners();
          debugPrint('Phone Auth Failed: ${e.code}');

          if (e.code == 'network-request-failed') {
            onError('No internet connection. Please try again.');
          } else if (e.code == 'too-many-requests') {
            onError('Too many attempts. Please wait and try again.');
          } else if (e.code == 'invalid-phone-number') {
            onError('Invalid phone number format.');
          } else if (e.code == 'app-not-authorized') {
            onError('App not authorized. Check Firebase config.');
          } else {
            onError('[${e.code}] ${e.message ?? "Verification failed"}');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (request != _otpRequest) return;
          _verificationId = verificationId;
          _resendToken = resendToken;
          _isLoading = false;
          notifyListeners();
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (request == _otpRequest) _verificationId ??= verificationId;
        },
      );
    } catch (e) {
      if (request != _otpRequest) return;
      _isLoading = false;
      notifyListeners();
      debugPrint(
          'OTP Request Exception: ${e is FirebaseAuthException ? e.code : e.runtimeType}');

      if (e is FirebaseAuthException && e.code == 'network-request-failed') {
        onError('No internet connection. Please try again.');
      } else {
        onError('Could not send OTP. Please try again.');
      }
    }
  }

  // ─── OTP Verification ────────────────────────────────────────
  Future<String?> verifyOtp(
      {required String smsCode, String? verificationId}) async {
    final normalizedCode = smsCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) {
      return 'Please enter the 6-digit OTP sent to your phone.';
    }

    final vId = verificationId ?? _verificationId;
    if (vId == null || _verificationId == null) {
      return 'Session expired. Please request OTP again.';
    }
    if (vId != _verificationId) {
      return 'This OTP session was replaced. Please use the latest code.';
    }
    _isLoading = true;
    notifyListeners();

    try {
      if (kIsWeb && _webConfirmationResult != null) {
        final result = await _webConfirmationResult!.confirm(normalizedCode);
        return await _handleSuccessfulSignIn(result.user, phoneVerified: true);
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: normalizedCode,
      );
      return await _signInWithCredential(credential);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return _otpVerificationError(e);
    }
  }

  String _otpVerificationError(Object error) {
    if (error is! FirebaseAuthException) {
      return 'Could not complete sign-in. Please try again.';
    }
    debugPrint('OTP Verification Failed: ${error.code}');
    switch (error.code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Enter the latest code from your SMS.';
      case 'session-expired':
      case 'code-expired':
      case 'invalid-verification-id':
      case 'missing-verification-id':
        return 'OTP expired. Tap Resend OTP to get a new code.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      default:
        return 'Phone sign-in failed (${error.code}). Please try again.';
    }
  }

  // ─── Post-Sign In Logic ──────────────────────────────────────
  Future<String?> _handleSuccessfulSignIn(User? user,
      {bool phoneVerified = false}) async {
    try {
      final token = await user?.getIdToken();

      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        _token = token;
      }

      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'Authentication failed. Please try again.';
      } else {
        try {
          final docRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);

          final docSnap = await docRef.get();

          Map<String, dynamic> updateData = {
            'uid': user.uid,
            'phoneNumber': user.phoneNumber ?? '',
            'role': docSnap.data()?['role'] ?? 'worker',
            if (phoneVerified) 'phoneVerified': true,
            if (phoneVerified) 'phoneVerifiedAt': FieldValue.serverTimestamp(),
          };

          if (!docSnap.exists || docSnap.data()?['workerId'] == null) {
            updateData['workerId'] = StringUtils.generateWorkerId();
          }

          if (!docSnap.exists || docSnap.data()?['createdAt'] == null) {
            updateData['createdAt'] = FieldValue.serverTimestamp();
          }

          await docRef.set(updateData, SetOptions(merge: true));

          // Set local workerId and role
          _workerId = updateData['workerId'] ?? docSnap.data()?['workerId'];
          _role = updateData['role'] ?? docSnap.data()?['role'] ?? 'worker';
        } catch (firestoreError) {
          debugPrint('Firestore User Creation Error: $firestoreError');
        }
      }

      await NotificationService().updateToken();
      _isLoading = false;
      notifyListeners();
      return null; // success
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString();
    }
  }

  // ─── Google Sign-In ──────────────────────────────────────────
  Future<String?> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return 'Google Sign-In cancelled by user.';
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      return await _handleSuccessfulSignIn(userCredential.user);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Google Sign-In Exception: $e');
      if (e is FirebaseAuthException) {
        return e.message ?? 'Google Sign-In failed.';
      }
      return 'Google Sign-In failed: ${e.toString()}';
    }
  }

  // ─── Shared Sign-In Logic ────────────────────────────────────
  Future<String?> _signInWithCredential(PhoneAuthCredential credential) async {
    final request = _otpRequest;
    final pending =
        _phoneSignIn ??= _auth.signInWithCredential(credential).then((result) {
      if (request != _otpRequest) {
        return 'Session expired. Please request OTP again.';
      }
      return _handleSuccessfulSignIn(result.user, phoneVerified: true);
    });
    try {
      final error = await pending;
      if (error != null && identical(_phoneSignIn, pending)) {
        _phoneSignIn = null;
      }
      return error;
    } catch (e) {
      if (identical(_phoneSignIn, pending)) _phoneSignIn = null;
      return _otpVerificationError(e);
    } finally {
      if (request == _otpRequest) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ─── TEST BYPASS LOGIN ──────────────────────────────────────
  // ─── Legacy Login Wrapper (Optional Bypass) ──────────────────
  Future<void> login(String token) async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
    _token = token;

    _isLoading = false;
    notifyListeners();
  }

  // ─── Admin Email/Password Login ─────────────────────────────
  /// Authenticates an admin using email and password.
  /// Returns null on success, or an error message string on failure.
  /// Validates that the Firestore user document has role == 'admin'.
  Future<String?> adminLogin({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Firebase Auth — Email/Password sign-in
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'Authentication failed. Please try again.';
      }

      // 2. Fetch Firestore user doc and validate role
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();
        _isLoading = false;
        notifyListeners();
        return 'No user profile found. Contact support.';
      }

      final data = userDoc.data()!;
      final role = (data['role'] ?? '').toString().toLowerCase();

      final validAdminRoles = [
        'admin',
        'super_admin',
        'task_review_admin',
        'kyc_admin',
        'payment_admin',
        'support_admin'
      ];
      if (!validAdminRoles.contains(role)) {
        await _auth.signOut();
        _isLoading = false;
        notifyListeners();
        return 'Access denied. Not an admin.';
      }

      _restoreProfile(data, await SharedPreferences.getInstance(), user.uid);
      _sessionRestoreFailed = false;

      // 3. Admin verified — force a token refresh so the LATEST custom-claim
      // roles (synced from Firestore by syncUserClaims) are in the token that
      // security rules check. Without force:true a stale token can deny
      // queries for a role that was added after the admin last signed in.
      final token = await user.getIdToken(true);
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        _token = token;
      }

      await NotificationService().updateToken();
      _isLoading = false;
      notifyListeners();
      return null; // success
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();

      switch (e.code) {
        case 'user-not-found':
          return 'No admin account found with this email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect password. Please try again.';
        case 'invalid-email':
          return 'Invalid email format.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts. Please try later.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        default:
          return e.message ?? 'Authentication failed.';
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // ─── Developer Login ────────────────────────────────────────
  /// Authenticates the developer via email + password. Requires BOTH the
  /// Firestore role == 'developer' AND the email to match the hardcoded
  /// developer anchor ([AppConstants.developerEmail]).
  ///
  /// Returns null on success, or a generic error message on failure. Errors
  /// are intentionally vague so the hidden developer entry point does not
  /// reveal which check failed.
  Future<String?> developerLogin({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    // Anchor check before hitting Firebase Auth.
    if (email.trim().toLowerCase() !=
        AppConstants.developerEmail.toLowerCase()) {
      _isLoading = false;
      notifyListeners();
      return 'Access denied.';
    }

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = userCredential.user;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'Authentication failed. Please try again.';
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final role = (userDoc.data()?['role'] ?? '').toString().toLowerCase();
      if (role != AppConstants.developerRole) {
        await _auth.signOut();
        _isLoading = false;
        notifyListeners();
        return 'Access denied.';
      }

      _role = role;
      _workerId = userDoc.data()?['workerId'];

      final token = await user.getIdToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.tokenKey, token);
        _token = token;
      }

      _isLoading = false;
      notifyListeners();
      return null; // success
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      switch (e.code) {
        case 'too-many-requests':
          return 'Too many attempts. Please try later.';
        case 'network-request-failed':
          return 'No internet connection. Please try again.';
        default:
          return 'Invalid credentials.';
      }
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return 'An unexpected error occurred.';
    }
  }

  // ─── Email Verification ───────────────────────────────────────
  Future<String?> sendEmailVerification(String email) async {
    _isLoading = true;
    notifyListeners();
    try {
      var user = _auth.currentUser;
      if (user == null) {
        await Future.delayed(const Duration(milliseconds: 800));
        user = _auth.currentUser;
        if (user == null) {
          debugPrint(
              'sendEmailVerification error: no authenticated Firebase user');
          return 'Session expired. Please log in again.';
        }
      }

      await FirebaseFunctions.instance
          .httpsCallable('sendEmailOtp')
          .call({'email': email});

      await user.reload();

      _isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'sendEmailVerification FirebaseFunctionsException: '
        'code=${e.code}, message=${e.message}, details=${e.details}',
      );
      _isLoading = false;
      notifyListeners();
      return e.message ?? 'Failed to send verification email.';
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'sendEmailVerification FirebaseAuthException: '
        'code=${e.code}, message=${e.message}',
      );
      _isLoading = false;
      notifyListeners();
      return e.message ?? 'Auth error occurred.';
    } catch (e) {
      debugPrint('sendEmailVerification exception: $e');
      _isLoading = false;
      notifyListeners();
      return 'Error: $e';
    }
  }

  Future<bool> checkEmailVerified() async {
    try {
      await _auth.currentUser?.reload();
      final freshUser = _auth.currentUser;
      return freshUser?.emailVerified ?? false;
    } catch (e) {
      debugPrint('Error checking email verification: $e');
      return false;
    }
  }

  // ─── Logout ─────────────────────────────────────────────────
  Future<void> logout() async {
    final pending = _phoneSignIn;
    _otpRequest++;
    _verificationId = null;
    _webConfirmationResult = null;
    _webRecaptchaVerifier?.clear();
    _webRecaptchaVerifier = null;
    _resendToken = null;
    _otpPhone = null;
    _phoneSignIn = null;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final userId = _auth.currentUser?.uid;
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) await prefs.remove('adminWorkspace:$userId');
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
    _token = null;
    _workerId = null;
    _role = null;
    _roles = {};
    _activeAdminRole = null;
    _sessionRestoreFailed = false;
    _isLoading = false;
    notifyListeners();
  }

  // ─── Onboarding ─────────────────────────────────────────────
  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingKey, true);
    _onboardingComplete = true;
    notifyListeners();
  }
}
