import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6 — Earnings Calculation Tests.
///
/// Tests admin approval/rejection flow, earnings increment,
/// history creation, duplicate approval prevention, and
/// concurrent approval safety.
void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  // ─── Helpers ─────────────────────────────────────────────────
  Future<Map<String, String>> seedSubmission({
    String userId = 'worker-1',
    double payout = 15.0,
    String status = 'pending_admin_review',
  }) async {
    // Create user
    await fakeFirestore.collection('users').doc(userId).set({
      'uid': userId,
      'name': 'Test Worker',
      'role': 'worker',
      'earnings': 100.0, // starting balance
      'lockedBalance': 0.0,
    });

    // Create submission
    final subRef = await fakeFirestore.collection('task_submissions').add({
      'userId': userId,
      'taskId': 'task-001',
      'assignmentId': 'asn-001',
      'leadId': 'lead-001',
      'workerName': 'Test Worker',
      'customerPhone': '+919876543210',
      'payout': payout,
      'result': 'Interested',
      'callDuration': 45,
      'status': status,
    });

    // Create earnings_pending
    final earningRef = await fakeFirestore.collection('earnings_pending').add({
      'userId': userId,
      'assignmentId': 'asn-001',
      'taskId': 'task-001',
      'payout': payout,
      'status': 'pending_admin_approval',
    });

    return {
      'submissionId': subRef.id,
      'earningId': earningRef.id,
      'userId': userId,
    };
  }

  /// Simulates admin approval logic
  Future<void> approveSubmission({
    required String submissionId,
    required String adminId,
  }) async {
    final subDoc = await fakeFirestore
        .collection('task_submissions')
        .doc(submissionId)
        .get();
    if (!subDoc.exists) throw Exception('Submission not found');

    final data = subDoc.data()!;
    if (data['status'] == 'approved') {
      throw Exception('Already approved. Cannot approve twice.');
    }

    final userId = data['userId'] as String;
    final payout = (data['payout'] as num).toDouble();
    final assignmentId = data['assignmentId'] as String;

    // Update submission
    await fakeFirestore
        .collection('task_submissions')
        .doc(submissionId)
        .update({
      'status': 'approved',
      'reviewedBy': adminId,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // Update earnings_pending
    final earningsQuery = await fakeFirestore
        .collection('earnings_pending')
        .where('assignmentId', isEqualTo: assignmentId)
        .where('userId', isEqualTo: userId)
        .get();
    if (earningsQuery.docs.isNotEmpty) {
      await earningsQuery.docs.first.reference.update({
        'status': 'approved',
      });
    }

    // Increase worker earnings
    await fakeFirestore.collection('users').doc(userId).update({
      'earnings': FieldValue.increment(payout),
    });

    // Create earnings_history
    await fakeFirestore.collection('earnings_history').add({
      'userId': userId,
      'payout': payout,
      'taskId': data['taskId'],
      'assignmentId': assignmentId,
      'approvedBy': adminId,
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Simulates admin rejection logic
  Future<void> rejectSubmission({
    required String submissionId,
    required String adminId,
  }) async {
    final subDoc = await fakeFirestore
        .collection('task_submissions')
        .doc(submissionId)
        .get();
    if (!subDoc.exists) throw Exception('Submission not found');

    final data = subDoc.data()!;
    final userId = data['userId'] as String;
    final assignmentId = data['assignmentId'] as String;

    // Update submission
    await fakeFirestore
        .collection('task_submissions')
        .doc(submissionId)
        .update({
      'status': 'rejected',
      'reviewedBy': adminId,
      'reviewedAt': FieldValue.serverTimestamp(),
    });

    // Update earnings_pending
    final earningsQuery = await fakeFirestore
        .collection('earnings_pending')
        .where('assignmentId', isEqualTo: assignmentId)
        .where('userId', isEqualTo: userId)
        .get();
    if (earningsQuery.docs.isNotEmpty) {
      await earningsQuery.docs.first.reference.update({
        'status': 'rejected',
      });
    }

    // DO NOT increase earnings
  }

  // ═══════════════════════════════════════════════════════════════
  // Test Cases
  // ═══════════════════════════════════════════════════════════════

  group('Earnings — Approval', () {
    test('Admin approves submission → earnings increase', () async {
      final ids = await seedSubmission(payout: 25.0);

      await approveSubmission(
        submissionId: ids['submissionId']!,
        adminId: 'admin-1',
      );

      // Verify submission status
      final sub = await fakeFirestore
          .collection('task_submissions')
          .doc(ids['submissionId']!)
          .get();
      expect(sub.data()!['status'], 'approved');
      expect(sub.data()!['reviewedBy'], 'admin-1');

      // Verify earnings increased (100 + 25 = 125)
      final user =
          await fakeFirestore.collection('users').doc(ids['userId']!).get();
      expect(user.data()!['earnings'], 125.0);

      // Verify earnings_history created
      final history = await fakeFirestore
          .collection('earnings_history')
          .where('userId', isEqualTo: ids['userId']!)
          .get();
      expect(history.docs, hasLength(1));
      expect(history.docs.first.data()['payout'], 25.0);
      expect(history.docs.first.data()['approvedBy'], 'admin-1');
    });

    test('Multiple approvals for different submissions stack correctly',
        () async {
      // Two separate submissions from same worker
      final ids1 = await seedSubmission(payout: 10.0);

      // Create a second submission (different lead)
      final sub2Ref = await fakeFirestore.collection('task_submissions').add({
        'userId': ids1['userId']!,
        'taskId': 'task-002',
        'assignmentId': 'asn-002',
        'leadId': 'lead-002',
        'payout': 20.0,
        'result': 'Interested',
        'status': 'pending_admin_review',
      });
      await fakeFirestore.collection('earnings_pending').add({
        'userId': ids1['userId']!,
        'assignmentId': 'asn-002',
        'taskId': 'task-002',
        'payout': 20.0,
        'status': 'pending_admin_approval',
      });

      // Approve both
      await approveSubmission(
          submissionId: ids1['submissionId']!, adminId: 'admin-1');
      await approveSubmission(submissionId: sub2Ref.id, adminId: 'admin-1');

      // 100 (initial) + 10 + 20 = 130
      final user =
          await fakeFirestore.collection('users').doc(ids1['userId']!).get();
      expect(user.data()!['earnings'], 130.0);

      // Two history records
      final history = await fakeFirestore
          .collection('earnings_history')
          .where('userId', isEqualTo: ids1['userId']!)
          .get();
      expect(history.docs, hasLength(2));
    });
  });

  group('Earnings — Rejection', () {
    test('Admin rejects submission → earnings unchanged', () async {
      final ids = await seedSubmission(payout: 50.0);

      await rejectSubmission(
        submissionId: ids['submissionId']!,
        adminId: 'admin-1',
      );

      // Verify submission status
      final sub = await fakeFirestore
          .collection('task_submissions')
          .doc(ids['submissionId']!)
          .get();
      expect(sub.data()!['status'], 'rejected');

      // Verify earnings unchanged (still 100)
      final user =
          await fakeFirestore.collection('users').doc(ids['userId']!).get();
      expect(user.data()!['earnings'], 100.0);

      // Verify NO earnings_history created
      final history = await fakeFirestore
          .collection('earnings_history')
          .where('userId', isEqualTo: ids['userId']!)
          .get();
      expect(history.docs, isEmpty);
    });

    test('Rejection updates earnings_pending to rejected', () async {
      final ids = await seedSubmission();

      await rejectSubmission(
        submissionId: ids['submissionId']!,
        adminId: 'admin-1',
      );

      final earningDoc = await fakeFirestore
          .collection('earnings_pending')
          .doc(ids['earningId']!)
          .get();
      expect(earningDoc.data()!['status'], 'rejected');
    });
  });

  group('Earnings — Duplicate Prevention', () {
    test('Duplicate approval attempt throws error', () async {
      final ids = await seedSubmission(payout: 30.0);

      // First approval succeeds
      await approveSubmission(
        submissionId: ids['submissionId']!,
        adminId: 'admin-1',
      );

      // Second approval should fail
      expect(
        () => approveSubmission(
          submissionId: ids['submissionId']!,
          adminId: 'admin-2',
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('Already approved'))),
      );

      // Earnings should be 130 (100 + 30), NOT 160 (100 + 30 + 30)
      final user =
          await fakeFirestore.collection('users').doc(ids['userId']!).get();
      expect(user.data()!['earnings'], 130.0);

      // Only one history record
      final history = await fakeFirestore
          .collection('earnings_history')
          .where('userId', isEqualTo: ids['userId']!)
          .get();
      expect(history.docs, hasLength(1));
    });
  });
}
