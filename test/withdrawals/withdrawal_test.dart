import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7 + 8 — Withdrawal Request + Processing Tests.
///
/// Tests withdrawal request validation, balance locking,
/// KYC checks, and admin approval/rejection flow.
void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  // ─── Helpers ─────────────────────────────────────────────────
  Future<void> seedWorker({
    String userId = 'worker-1',
    double earnings = 500.0,
    double lockedBalance = 0.0,
    String kycStatus = 'approved',
  }) async {
    await fakeFirestore.collection('users').doc(userId).set({
      'uid': userId,
      'name': 'Test Worker',
      'role': 'worker',
      'earnings': earnings,
      'lockedBalance': lockedBalance,
      'kycStatus': kycStatus,
    });
  }

  /// Simulates requestWithdrawal logic
  Future<String> requestWithdrawal({
    required String userId,
    required double amount,
  }) async {
    // Get user data
    final userDoc = await fakeFirestore.collection('users').doc(userId).get();
    if (!userDoc.exists) throw Exception('User not found');

    final userData = userDoc.data()!;
    final kycStatus = userData['kycStatus'] ?? 'pending';
    final earnings = (userData['earnings'] as num).toDouble();

    // KYC check
    if (kycStatus != 'approved') {
      throw Exception('KYC verification required before withdrawal.');
    }

    // Amount validation
    if (amount <= 0) throw Exception('Amount must be positive.');
    if (amount > earnings) {
      throw Exception('Insufficient balance. Available: ₹$earnings');
    }

    // Create withdrawal request
    final withdrawRef =
        await fakeFirestore.collection('withdraw_requests').add({
      'userId': userId,
      'amount': amount,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Lock funds: decrease earnings, increase lockedBalance
    await fakeFirestore.collection('users').doc(userId).update({
      'earnings': FieldValue.increment(-amount),
      'lockedBalance': FieldValue.increment(amount),
    });

    return withdrawRef.id;
  }

  /// Simulates processWithdrawal logic
  Future<void> processWithdrawal({
    required String withdrawRequestId,
    required String adminId,
    required String status, // 'approved' or 'rejected'
  }) async {
    final reqDoc = await fakeFirestore
        .collection('withdraw_requests')
        .doc(withdrawRequestId)
        .get();
    if (!reqDoc.exists) throw Exception('Withdrawal request not found');

    final data = reqDoc.data()!;
    if (data['status'] != 'pending') {
      throw Exception('Request already processed.');
    }

    final userId = data['userId'] as String;
    final amount = (data['amount'] as num).toDouble();

    if (status == 'approved') {
      // Update request status
      await fakeFirestore
          .collection('withdraw_requests')
          .doc(withdrawRequestId)
          .update({
        'status': 'approved',
        'processedBy': adminId,
        'processedAt': FieldValue.serverTimestamp(),
      });

      // Decrease lockedBalance (funds paid out)
      await fakeFirestore.collection('users').doc(userId).update({
        'lockedBalance': FieldValue.increment(-amount),
      });

      // Create payout_history
      await fakeFirestore.collection('payout_history').add({
        'userId': userId,
        'amount': amount,
        'withdrawRequestId': withdrawRequestId,
        'processedBy': adminId,
        'processedAt': FieldValue.serverTimestamp(),
      });
    } else if (status == 'rejected') {
      // Update request status
      await fakeFirestore
          .collection('withdraw_requests')
          .doc(withdrawRequestId)
          .update({
        'status': 'rejected',
        'processedBy': adminId,
        'processedAt': FieldValue.serverTimestamp(),
      });

      // Return funds: increase earnings, decrease lockedBalance
      await fakeFirestore.collection('users').doc(userId).update({
        'earnings': FieldValue.increment(amount),
        'lockedBalance': FieldValue.increment(-amount),
      });
    } else {
      throw Exception('Invalid status. Must be "approved" or "rejected".');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Phase 7 — Withdrawal Request Tests
  // ═══════════════════════════════════════════════════════════════
  group('Withdrawal Request', () {
    test('Worker requests withdrawal with sufficient balance', () async {
      await seedWorker(earnings: 500.0);

      final requestId = await requestWithdrawal(
        userId: 'worker-1',
        amount: 200.0,
      );

      // Verify request created
      final req = await fakeFirestore
          .collection('withdraw_requests')
          .doc(requestId)
          .get();
      expect(req.data()!['amount'], 200.0);
      expect(req.data()!['status'], 'pending');

      // Verify balance locked (500 → 300 earnings, 200 locked)
      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      expect(user.data()!['earnings'], 300.0);
      expect(user.data()!['lockedBalance'], 200.0);
    });

    test('Worker cannot request withdrawal exceeding balance', () async {
      await seedWorker(earnings: 100.0);

      expect(
        () => requestWithdrawal(userId: 'worker-1', amount: 500.0),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('Insufficient balance'))),
      );

      // Balance should be unchanged
      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      expect(user.data()!['earnings'], 100.0);
    });

    test('Worker cannot request withdrawal with pending KYC', () async {
      await seedWorker(kycStatus: 'pending');

      expect(
        () => requestWithdrawal(userId: 'worker-1', amount: 50.0),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('KYC verification'))),
      );
    });

    test('Worker cannot request zero or negative amount', () async {
      await seedWorker();

      expect(
        () => requestWithdrawal(userId: 'worker-1', amount: 0),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('must be positive'))),
      );
      expect(
        () => requestWithdrawal(userId: 'worker-1', amount: -100),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('must be positive'))),
      );
    });

    test('Worker can request exact full balance', () async {
      await seedWorker(earnings: 250.0);

      final requestId = await requestWithdrawal(
        userId: 'worker-1',
        amount: 250.0,
      );

      expect(requestId, isNotEmpty);

      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      expect(user.data()!['earnings'], 0.0);
      expect(user.data()!['lockedBalance'], 250.0);
    });

    test('Multiple withdrawal requests lock funds independently', () async {
      await seedWorker(earnings: 1000.0);

      await requestWithdrawal(userId: 'worker-1', amount: 300.0);
      await requestWithdrawal(userId: 'worker-1', amount: 200.0);

      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      // 1000 - 300 - 200 = 500 earnings, 500 locked
      expect(user.data()!['earnings'], 500.0);
      expect(user.data()!['lockedBalance'], 500.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Phase 8 — Withdrawal Processing Tests
  // ═══════════════════════════════════════════════════════════════
  group('Withdrawal Processing', () {
    test('Admin approves withdrawal → balance deducted', () async {
      await seedWorker(earnings: 500.0);
      final requestId =
          await requestWithdrawal(userId: 'worker-1', amount: 200.0);

      await processWithdrawal(
        withdrawRequestId: requestId,
        adminId: 'admin-1',
        status: 'approved',
      );

      // Verify request status
      final req = await fakeFirestore
          .collection('withdraw_requests')
          .doc(requestId)
          .get();
      expect(req.data()!['status'], 'approved');
      expect(req.data()!['processedBy'], 'admin-1');

      // Verify balance: earnings 300, locked 0
      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      expect(user.data()!['earnings'], 300.0);
      expect(user.data()!['lockedBalance'], 0.0);

      // Verify payout_history
      final payout = await fakeFirestore
          .collection('payout_history')
          .where('userId', isEqualTo: 'worker-1')
          .get();
      expect(payout.docs, hasLength(1));
      expect(payout.docs.first.data()['amount'], 200.0);
    });

    test('Admin rejects withdrawal → funds returned', () async {
      await seedWorker(earnings: 500.0);
      final requestId =
          await requestWithdrawal(userId: 'worker-1', amount: 150.0);

      // After request: earnings=350, locked=150
      await processWithdrawal(
        withdrawRequestId: requestId,
        adminId: 'admin-1',
        status: 'rejected',
      );

      // After rejection: earnings=500 (returned), locked=0
      final user =
          await fakeFirestore.collection('users').doc('worker-1').get();
      expect(user.data()!['earnings'], 500.0);
      expect(user.data()!['lockedBalance'], 0.0);

      // No payout_history for rejected
      final payout = await fakeFirestore
          .collection('payout_history')
          .where('userId', isEqualTo: 'worker-1')
          .get();
      expect(payout.docs, isEmpty);
    });

    test('Invalid withdrawal request throws error', () async {
      expect(
        () => processWithdrawal(
          withdrawRequestId: 'nonexistent-id',
          adminId: 'admin-1',
          status: 'approved',
        ),
        throwsA(predicate(
            (e) => e is Exception && e.toString().contains('not found'))),
      );
    });

    test('Duplicate processing attempt throws error', () async {
      await seedWorker(earnings: 500.0);
      final requestId =
          await requestWithdrawal(userId: 'worker-1', amount: 100.0);

      // First processing succeeds
      await processWithdrawal(
        withdrawRequestId: requestId,
        adminId: 'admin-1',
        status: 'approved',
      );

      // Second processing should fail
      expect(
        () => processWithdrawal(
          withdrawRequestId: requestId,
          adminId: 'admin-2',
          status: 'approved',
        ),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('already processed'))),
      );
    });

    test('Invalid status value throws error', () async {
      await seedWorker(earnings: 500.0);
      final requestId =
          await requestWithdrawal(userId: 'worker-1', amount: 100.0);

      expect(
        () => processWithdrawal(
          withdrawRequestId: requestId,
          adminId: 'admin-1',
          status: 'maybe',
        ),
        throwsA(predicate(
            (e) => e is Exception && e.toString().contains('Invalid status'))),
      );
    });
  });
}
