import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:human_bpo/services/auth_service.dart';

class _PhoneAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;
  final requests = <({PhoneVerificationCompleted completed,
    PhoneVerificationFailed failed, PhoneCodeSent sent,
    PhoneCodeAutoRetrievalTimeout timeout, int? resendToken})>[];
  int signIns = 0;
  int signOuts = 0;
  String errorCode = 'session-expired';
  Completer<UserCredential>? pending;

  @override
  Future<void> verifyPhoneNumber({String? phoneNumber,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    Duration timeout = const Duration(seconds: 30), int? forceResendingToken,
    String? autoRetrievedSmsCodeForTesting, MultiFactorSession? multiFactorSession,
    PhoneMultiFactorInfo? multiFactorInfo}) async {
    requests.add((completed: verificationCompleted, failed: verificationFailed,
      sent: codeSent, timeout: codeAutoRetrievalTimeout, resendToken: forceResendingToken));
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signIns++;
    if (pending != null) return pending!.future;
    throw FirebaseAuthException(code: errorCode);
  }

  @override
  Future<void> signOut() async { signOuts++; }
}

class _RestoredUser extends Fake implements User {
  @override
  String get uid => 'reviewer';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
}

class _RestoredAuth extends Fake implements FirebaseAuth {
  User? user = _RestoredUser();
  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async { user = null; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reviewer workspace survives restart, validates roles and clears on logout', () async {
    SharedPreferences.setMockInitialValues({});
    final firestore = FakeFirebaseFirestore();
    final auth = _RestoredAuth();
    final profile = firestore.collection('users').doc('reviewer');
    await profile.set({'role': 'super_admin'});
    await AuthService.rememberAdminWorkspace('reviewer', 'task_review_admin');
    final first = AuthService(auth: auth, firestore: firestore);
    await first.init();
    expect(first.isAdmin, isTrue);
    expect(first.activeAdminRole, 'task_review_admin');
    first.dispose();
    final restarted = AuthService(auth: auth, firestore: firestore);
    await restarted.init();
    expect(restarted.activeAdminRole, 'task_review_admin');
    await profile.set({'role': 'support_admin'});
    await restarted.init();
    expect(restarted.activeAdminRole, 'support_admin');
    await profile.set({'role': 'worker', 'roles': ['task_review_admin']});
    await restarted.init();
    expect(restarted.isAdmin, isTrue);
    expect(restarted.activeAdminRole, 'task_review_admin');
    await profile.set({'role': 'worker'});
    await restarted.init();
    expect(restarted.isAdmin, isFalse);
    expect(restarted.activeAdminRole, isNull);
    await profile.delete();
    await restarted.init();
    expect(restarted.sessionRestoreFailed, isTrue);
    await restarted.logout();
    expect(restarted.isAuthenticated, isFalse);
    expect(restarted.activeAdminRole, isNull);
    expect((await SharedPreferences.getInstance()).getString('adminWorkspace:reviewer'), isNull);
    restarted.dispose();
  });

  late _PhoneAuth firebase;
  late AuthService service;
  final codes = <String>[];
  final errors = <String>[];
  Future<void> send() => service.sendOtp('+15555550100',
    onCodeSent: codes.add, onError: errors.add);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firebase = _PhoneAuth();
    service = AuthService(auth: firebase);
    codes.clear();
    errors.clear();
  });

  tearDown(() => service.dispose());

  test('resend and logout ignore obsolete callbacks and clear verification state', () async {
    await send();
    final old = firebase.requests.single;
    old.sent('old-session', 17);
    await send();
    expect(firebase.requests.last.resendToken, 17);
    firebase.requests.last.sent('new-session', 18);
    old.sent('stale-session', 19);
    old.timeout('stale-session');
    old.failed(FirebaseAuthException(code: 'invalid-phone-number'));
    old.completed(PhoneAuthProvider.credential(verificationId: 'old-session', smsCode: '123456'));
    expect(codes, ['old-session', 'new-session']);
    expect(errors, isEmpty);
    expect(firebase.signIns, 0);
    expect(await service.verifyOtp(smsCode: '123456', verificationId: 'old-session'),
      contains('session was replaced'));
    expect(firebase.signIns, 0);
    await service.logout();
    firebase.requests.last.sent('after-logout', 20);
    expect(codes.length, 2);
    expect(await service.verifyOtp(smsCode: '123456'), contains('Session expired'));
    expect(await service.verifyOtp(smsCode: '123456', verificationId: 'new-session'),
      contains('Session expired'));
    await send();
    expect(firebase.requests.last.resendToken, isNull);
  });

  test('manual and automatic verification share one attempt and failures permit retry', () async {
    await send();
    firebase.requests.single.sent('session', 17);
    firebase.pending = Completer<UserCredential>();
    firebase.requests.single.completed(PhoneAuthProvider.credential(
      verificationId: 'session', smsCode: '123456'));
    final manual = service.verifyOtp(smsCode: '123456', verificationId: 'session');
    expect(firebase.signIns, 1);
    firebase.pending!.completeError(FirebaseAuthException(code: 'session-expired'));
    expect(await manual, contains('OTP expired'));
    expect(errors.single, contains('OTP expired'));
    firebase.pending = null;
    firebase.errorCode = 'invalid-verification-code';
    expect(await service.verifyOtp(smsCode: '654321'), contains('Incorrect OTP'));
    expect(firebase.signIns, 2);
  });

  test('logout waits for in-flight sign-in before clearing Firebase authentication', () async {
    await send();
    firebase.requests.single.sent('session', 17);
    firebase.pending = Completer<UserCredential>();
    final manual = service.verifyOtp(smsCode: '123456');
    final logout = service.logout();
    expect(firebase.signOuts, 0);
    firebase.pending!.completeError(FirebaseAuthException(code: 'session-expired'));
    await manual;
    await logout;
    expect(firebase.signOuts, 1);
    expect(service.isLoading, isFalse);
    expect(await service.verifyOtp(smsCode: '123456', verificationId: 'session'),
      contains('Session expired'));
  });

  for (final entry in {
    'invalid-verification-code': 'Incorrect OTP',
    'session-expired': 'OTP expired',
    'invalid-verification-id': 'OTP expired',
    'network-request-failed': 'No internet connection',
    'too-many-requests': 'Too many attempts',
    'user-disabled': 'account has been disabled',
    'invalid-app-credential': 'invalid-app-credential',
  }.entries) {
    test('verification reports ${entry.key} without mislabeling the OTP', () async {
      await send();
      firebase.requests.single.sent('session', 17);
      firebase.errorCode = entry.key;
      expect(await service.verifyOtp(smsCode: '123456'), contains(entry.value));
    });
  }
}