import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 4 + 5 — Task Submission + Call Recording Validation Tests.
///
/// Tests the submission flow including call recording validation,
/// minimum call duration, duplicate prevention, and data integrity.
void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  // ─── Helpers ─────────────────────────────────────────────────
  Future<String> seedLead(String taskId) async {
    final ref = await fakeFirestore
        .collection('tasks')
        .doc(taskId)
        .collection('leads')
        .add({
      'name': 'John Doe',
      'phone': '+919876543210',
      'status': 'not_called',
    });
    return ref.id;
  }

  /// Simulates the submission logic from TaskExecutionScreen._submitLead
  Future<String> submitLead({
    required String taskId,
    required String assignmentId,
    required String leadId,
    required String userId,
    required String result,
    required int callDuration,
    required int minCallDuration,
    required bool callWasMade,
    String? callId,
    String? recordingUrl,
    String notes = '',
    double payout = 15.0,
  }) async {
    // Validation: must have made a call
    if (!callWasMade) {
      throw Exception('You must start a call before submitting.');
    }

    // Validation: minimum call duration
    if (callDuration < minCallDuration) {
      throw Exception('Minimum call duration is $minCallDuration seconds. '
          'Your call was only $callDuration seconds.');
    }

    // Validation: must select outcome
    if (result.isEmpty) {
      throw Exception('Please select a call outcome before submitting.');
    }

    // Prevent duplicate submission
    final existing = await fakeFirestore
        .collection('task_submissions')
        .where('leadId', isEqualTo: leadId)
        .where('userId', isEqualTo: userId)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('This lead was already submitted.');
    }

    // Update lead status
    await fakeFirestore
        .collection('tasks')
        .doc(taskId)
        .collection('leads')
        .doc(leadId)
        .update({
      'status': 'called',
      'calledBy': userId,
      'callResult': result,
      if (callId != null) 'callId': callId,
      if (recordingUrl != null) 'recordingUrl': recordingUrl,
      'callDuration': callDuration,
    });

    // Create submission
    final submissionRef =
        await fakeFirestore.collection('task_submissions').add({
      'assignmentId': assignmentId,
      'userId': userId,
      'workerName': 'Test Worker',
      'taskId': taskId,
      'leadId': leadId,
      'customerPhone': '+919876543210',
      'payout': payout,
      'result': result,
      'notes': notes,
      'callDuration': callDuration,
      'callId': callId,
      'recordingUrl': recordingUrl,
      'callType': callId != null ? 'voip' : 'manual',
      'status': 'pending_admin_review',
      'submittedAt': FieldValue.serverTimestamp(),
    });

    return submissionRef.id;
  }

  // ═══════════════════════════════════════════════════════════════
  // Phase 4 — Task Submission Tests
  // ═══════════════════════════════════════════════════════════════
  group('Task Submission', () {
    test('Worker submits call result successfully', () async {
      const taskId = 'task-001';
      final leadId = await seedLead(taskId);

      final submissionId = await submitLead(
        taskId: taskId,
        assignmentId: 'asn-001',
        leadId: leadId,
        userId: 'worker-1',
        result: 'Interested',
        callDuration: 45,
        minCallDuration: 10,
        callWasMade: true,
        callId: 'call-v1',
        recordingUrl: 'https://api.twilio.com/rec.mp3',
        notes: 'Customer wants info',
      );

      // Verify submission created
      final doc = await fakeFirestore
          .collection('task_submissions')
          .doc(submissionId)
          .get();
      expect(doc.exists, isTrue);

      final data = doc.data()!;
      expect(data['result'], 'Interested');
      expect(data['callDuration'], 45);
      expect(data['callId'], 'call-v1');
      expect(data['recordingUrl'], 'https://api.twilio.com/rec.mp3');
      expect(data['status'], 'pending_admin_review');
      expect(data['payout'], 15.0);
      expect(data['workerName'], 'Test Worker');
      expect(data['customerPhone'], '+919876543210');
      expect(data['callType'], 'voip');
    });

    test('Worker submits without recording (manual call)', () async {
      const taskId = 'task-002';
      final leadId = await seedLead(taskId);

      final submissionId = await submitLead(
        taskId: taskId,
        assignmentId: 'asn-002',
        leadId: leadId,
        userId: 'worker-2',
        result: 'Not Interested',
        callDuration: 30,
        minCallDuration: 10,
        callWasMade: true,
        // No callId or recordingUrl → manual call
      );

      final doc = await fakeFirestore
          .collection('task_submissions')
          .doc(submissionId)
          .get();
      expect(doc.data()!['callType'], 'manual');
      expect(doc.data()!['callId'], isNull);
      expect(doc.data()!['recordingUrl'], isNull);
    });

    test('Worker cannot submit without selecting result', () async {
      expect(
        () => submitLead(
          taskId: 'task-003',
          assignmentId: 'asn-003',
          leadId: 'lead-003',
          userId: 'worker-3',
          result: '', // empty result
          callDuration: 20,
          minCallDuration: 10,
          callWasMade: true,
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('select a call outcome'))),
      );
    });

    test('Worker cannot submit without making a call', () async {
      expect(
        () => submitLead(
          taskId: 'task-004',
          assignmentId: 'asn-004',
          leadId: 'lead-004',
          userId: 'worker-4',
          result: 'Interested',
          callDuration: 0,
          minCallDuration: 10,
          callWasMade: false, // no call made
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('must start a call'))),
      );
    });

    test('Worker cannot submit duplicate for same lead', () async {
      const taskId = 'task-005';
      final leadId = await seedLead(taskId);

      // First submission succeeds
      await submitLead(
        taskId: taskId,
        assignmentId: 'asn-005',
        leadId: leadId,
        userId: 'worker-5',
        result: 'Interested',
        callDuration: 20,
        minCallDuration: 10,
        callWasMade: true,
      );

      // Second submission for same lead should fail
      expect(
        () => submitLead(
          taskId: taskId,
          assignmentId: 'asn-005',
          leadId: leadId,
          userId: 'worker-5',
          result: 'Not Interested',
          callDuration: 15,
          minCallDuration: 10,
          callWasMade: true,
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('already submitted'))),
      );

      // Only one submission should exist
      final submissions = await fakeFirestore
          .collection('task_submissions')
          .where('leadId', isEqualTo: leadId)
          .get();
      expect(submissions.docs, hasLength(1));
    });

    test('Submission updates lead with call metadata', () async {
      const taskId = 'task-006';
      final leadId = await seedLead(taskId);

      await submitLead(
        taskId: taskId,
        assignmentId: 'asn-006',
        leadId: leadId,
        userId: 'worker-6',
        result: 'No Answer',
        callDuration: 12,
        minCallDuration: 10,
        callWasMade: true,
        callId: 'call-006',
        recordingUrl: 'https://rec.example.com/006.mp3',
      );

      // Verify lead updated
      final lead = await fakeFirestore
          .collection('tasks')
          .doc(taskId)
          .collection('leads')
          .doc(leadId)
          .get();
      final leadData = lead.data()!;

      expect(leadData['status'], 'called');
      expect(leadData['calledBy'], 'worker-6');
      expect(leadData['callResult'], 'No Answer');
      expect(leadData['callId'], 'call-006');
      expect(leadData['recordingUrl'], 'https://rec.example.com/006.mp3');
      expect(leadData['callDuration'], 12);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Phase 5 — Call Recording Validation Tests
  // ═══════════════════════════════════════════════════════════════
  group('Call Recording Validation', () {
    test('Call duration below minimum threshold rejects submission', () {
      expect(
        () => submitLead(
          taskId: 'task-rec-1',
          assignmentId: 'asn-rec-1',
          leadId: 'lead-rec-1',
          userId: 'worker-rec-1',
          result: 'Interested',
          callDuration: 5, // below 10 second minimum
          minCallDuration: 10,
          callWasMade: true,
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('Minimum call duration'))),
      );
    });

    test('Call duration exactly at minimum threshold is accepted', () async {
      const taskId = 'task-rec-2';
      final leadId = await seedLead(taskId);

      // Should succeed — exactly at threshold
      final submissionId = await submitLead(
        taskId: taskId,
        assignmentId: 'asn-rec-2',
        leadId: leadId,
        userId: 'worker-rec-2',
        result: 'Not Interested',
        callDuration: 10, // exactly 10 seconds
        minCallDuration: 10,
        callWasMade: true,
      );

      expect(submissionId, isNotEmpty);
    });

    test('Valid recording submission stores URL correctly', () async {
      const taskId = 'task-rec-3';
      final leadId = await seedLead(taskId);

      final submissionId = await submitLead(
        taskId: taskId,
        assignmentId: 'asn-rec-3',
        leadId: leadId,
        userId: 'worker-rec-3',
        result: 'Interested',
        callDuration: 120,
        minCallDuration: 10,
        callWasMade: true,
        callId: 'call-rec-3',
        recordingUrl:
            'https://api.twilio.com/2010-04-01/Accounts/AC/Recordings/RE.mp3',
      );

      final doc = await fakeFirestore
          .collection('task_submissions')
          .doc(submissionId)
          .get();
      expect(doc.data()!['recordingUrl'],
          'https://api.twilio.com/2010-04-01/Accounts/AC/Recordings/RE.mp3');
    });
  });
}
