/// Maps Firebase Auth error codes and generic exceptions to
/// user-friendly messages in one place.
class AuthErrors {
  AuthErrors._();

  // ─── Firebase Auth codes ────────────────────────────────────
  static String fromCode(String code) {
    switch (code) {
      // OTP
      case 'invalid-verification-code':
      case 'invalid-verification-id':
        return 'Invalid OTP. Please check and try again.';
      case 'session-expired':
        return 'OTP has expired. Please request a new one.';
      case 'missing-verification-code':
        return 'Please enter the OTP sent to your phone.';
      // Phone
      case 'invalid-phone-number':
        return 'Invalid phone number. Please check and retry.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes.';
      case 'app-not-authorized':
        return 'App verification failed. Please contact support.';
      // Email
      case 'email-already-in-use':
      case 'auth/email-already-exists':
        return 'This email is already registered to another account.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-not-found':
        return 'No account found. Please register first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect credentials. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      // Network
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      // reCAPTCHA
      case 'invalid-app-credential':
        return 'Verification failed or expired. Please click "Send OTP" to try again.';
      default:
        return 'Something went wrong ($code). Please try again.';
    }
  }

  /// Extracts a friendly message from any thrown exception.
  static String fromException(Object e) {
    if (e is Exception) {
      final msg = e.toString();
      // Extract Firebase code from "FirebaseAuthException: [code] message"
      final match = RegExp(r'\[([a-z-]+)\]').firstMatch(msg);
      if (match != null) return fromCode(match.group(1)!);
      // Cloud Functions error
      if (msg.contains('FirebaseFunctionsException')) {
        return msg.replaceAll(RegExp(r'FirebaseFunctionsException.*?:'), '').trim();
      }
    }
    return 'An unexpected error occurred. Please try again.';
  }
}
