import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/verification_status.dart';

/// Handles reading and writing verification flags in Firestore.
///
/// All writes that touch [emailVerified] go through a Cloud Function
/// so the Admin SDK — not the client — owns that state mutation.
/// [phoneVerified] is written directly from the client after Firebase
/// Auth confirms the phone credential (proof-of-possession is implicit).
class VerificationService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ─── Read ───────────────────────────────────────────────────
  /// Fetches current verification state from Firestore.
  /// Returns [VerificationStatus.newUser()] when no document exists.
  Future<VerificationStatus> getStatus(String uid) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!snap.exists || snap.data() == null) {
        return VerificationStatus.newUser();
      }
      return VerificationStatus.fromMap(snap.data()!);
    } catch (e) {
      debugPrint('VerificationService.getStatus error: $e');
      // Fail-open: treat as new user so they go through the gate
      return VerificationStatus.newUser();
    }
  }

  // ─── Phone ──────────────────────────────────────────────────
  /// Marks phoneVerified=true for the current user.
  /// Safe to call from client: proof-of-possession is the PhoneAuthCredential
  /// already validated by Firebase Auth before this is invoked.
  Future<void> markPhoneVerified(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'phoneVerified': true,
        'phoneVerifiedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('markPhoneVerified error: $e');
    }
  }

  // ─── Email ──────────────────────────────────────────────────
  /// Calls the [verifyEmailOtp] Cloud Function which validates the OTP.
  ///
  /// Returns null on success, or an error string.
  Future<String?> verifyEmailOtp(String otp, String email) async {
    final user = _auth.currentUser;
    if (user == null) return 'Not authenticated.';

    try {
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return 'Session expired. Please log in again.';
      }
      final response = await http.post(
        Uri.parse('https://us-central1-sherize-bpo.cloudfunctions.net/verifyEmailOtp'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
          ...{'Authorization': 'Bearer $idToken'},
        },
        body: jsonEncode({
          'data': {'otp': otp, 'email': email}
        }),
      );

      if (response.statusCode != 200) {
        try {
          final decoded = jsonDecode(response.body);
          return decoded['error']?['message'] ?? 'Verification failed.';
        } catch (_) {
          return 'Verification failed.';
        }
      }
      
      // The Cloud Function has already written emailVerified=true to Firestore
      // via the Admin SDK. DO NOT call user.reload() or getIdToken(true) here:
      // the Admin SDK revokes the existing ID token when it changes the user's
      // email, which causes reload/getIdToken to clear the local Firebase
      // session, making currentUser null and kicking the user back to login.
      // Firebase will naturally refresh the token on the next authenticated
      // API call — no client-side forced refresh is needed.
      return null; // success

      
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'invalid-argument') {
        return 'Incorrect OTP. Please try again.';
      }
      return e.message ?? 'Verification failed.';
    } catch (e) {
      debugPrint('verifyEmailOtp exception: $e');
      return 'Error: ${e.toString()}';
    }
  }

  // ─── Quick check ────────────────────────────────────────────
  /// Reloads Firebase Auth user and returns current emailVerified flag.
  Future<bool> isFirebaseEmailVerified() async {
    try {
      await _auth.currentUser?.reload();
      return _auth.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }
}
