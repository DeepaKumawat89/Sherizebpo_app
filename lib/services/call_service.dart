import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/constants/constants.dart';
import '../models/call_model.dart';

/// Service for managing VOIP calls via the backend API.
///
/// Flutter app NEVER talks to Exotel directly — all calls go through
/// the backend which holds credentials securely.
///
/// Flow:
///   Flutter → POST /start-call → Backend → Exotel Voice API → Call
///   Exotel → Webhook → Backend → Firestore update
///   Flutter listens to Firestore for real-time call status.
class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Backend base URL — should be your Cloud Function or Node.js server.
  /// Update this to your deployed backend URL.
  static const String _backendUrl = AppConstants.baseUrl;

  // ─── Start a Call ─────────────────────────────────────────────
  /// Initiates a call through the backend.
  /// Returns the Firestore call document ID on success, null on failure.
  Future<String?> startCall({
    required String taskId,
    required String assignmentId,
    required String leadId,
    required String customerPhone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      // 1. Create initial call record in Firestore
      final callRef = _firestore.collection('calls').doc();
      final callData = {
        'callId': callRef.id,
        'taskId': taskId,
        'assignmentId': assignmentId,
        'userId': user.uid,
        'leadId': leadId,
        'customerPhone': customerPhone,
        'status': 'initiated',
        'recordingUrl': null,
        'exotelCallSid': null,
        'duration': 0,
        'startedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
      };

      await callRef.set(callData);

      // 2. Call backend to initiate Exotel call
      final idToken = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('$_backendUrl/start-call'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'callId': callRef.id,
              'userId': user.uid,
              'taskId': taskId,
              'assignmentId': assignmentId,
              'leadId': leadId,
              'customerPhone': customerPhone,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return callRef.id;
      } else {
        // Backend returned error — mark call as failed
        await callRef.update({
          'status': 'failed',
          'endedAt': FieldValue.serverTimestamp(),
        });
        throw Exception(
            'Backend error: ${response.statusCode} — ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // ─── End a Call ───────────────────────────────────────────────
  /// Requests the backend to end an active call.
  Future<void> endCall(String callId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final idToken = await user.getIdToken();
      await http
          .post(
            Uri.parse('$_backendUrl/end-call'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'callId': callId,
              'userId': user.uid,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // If end-call API fails, update Firestore directly as fallback
      await _firestore.collection('calls').doc(callId).update({
        'status': 'completed',
        'endedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ─── Listen to Call Status ────────────────────────────────────
  /// Returns a real-time stream of the call document.
  Stream<CallModel?> watchCall(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data()!;
      data['callId'] = snap.id;

      // Handle Firestore Timestamps
      if (data['startedAt'] is Timestamp) {
        data['startedAt'] =
            (data['startedAt'] as Timestamp).toDate().toIso8601String();
      }
      if (data['endedAt'] is Timestamp) {
        data['endedAt'] =
            (data['endedAt'] as Timestamp).toDate().toIso8601String();
      }

      return CallModel.fromJson(data);
    });
  }

  // ─── Get Call by ID ──────────────────────────────────────────
  Future<CallModel?> getCall(String callId) async {
    final snap = await _firestore.collection('calls').doc(callId).get();
    if (!snap.exists) return null;

    final data = snap.data()!;
    data['callId'] = snap.id;

    if (data['startedAt'] is Timestamp) {
      data['startedAt'] =
          (data['startedAt'] as Timestamp).toDate().toIso8601String();
    }
    if (data['endedAt'] is Timestamp) {
      data['endedAt'] =
          (data['endedAt'] as Timestamp).toDate().toIso8601String();
    }

    return CallModel.fromJson(data);
  }

  // ─── Get calls for a lead ────────────────────────────────────
  Future<List<CallModel>> getCallsForLead(String leadId) async {
    final snapshot = await _firestore
        .collection('calls')
        .where('leadId', isEqualTo: leadId)
        .orderBy('startedAt', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['callId'] = doc.id;
      if (data['startedAt'] is Timestamp) {
        data['startedAt'] =
            (data['startedAt'] as Timestamp).toDate().toIso8601String();
      }
      if (data['endedAt'] is Timestamp) {
        data['endedAt'] =
            (data['endedAt'] as Timestamp).toDate().toIso8601String();
      }
      return CallModel.fromJson(data);
    }).toList();
  }

  // ─── Update lead with call data ──────────────────────────────
  /// After a call completes, updates the lead document with call metadata.
  Future<void> updateLeadWithCallData({
    required String taskId,
    required String leadId,
    required String callId,
    required int callDuration,
    String? recordingUrl,
  }) async {
    await _firestore
        .collection('tasks')
        .doc(taskId)
        .collection('leads')
        .doc(leadId)
        .update({
      'callId': callId,
      'callDuration': callDuration,
      'recordingUrl': recordingUrl,
    });
  }
}
