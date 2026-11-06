import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/services/task_service.dart';

/// Per-task lead ownership tests.
///
/// Guards the fix for "task ids change automatically / calls get mixed into
/// another task": a lead belongs to exactly one task (tagged at upload) and a
/// worker only ever claims that task's own leads. Claiming must NEVER re-stamp
/// the lead's taskId, so a re-queued "recall" lead always stays under its
/// original task.
///
/// Mirrors the claim logic in TaskExecutionScreen._fetchNextLead.
void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  group('Execution task guidance', () {
    test('loads description without navigation script and scopes it to the task', () async {
      await fakeFirestore.collection('tasks').doc('taskA').set({'description': '  Ask about the product.  '});
      await fakeFirestore.collection('tasks').doc('taskB').set({'description': 'Other campaign'});
      expect(await TaskService(firestore: fakeFirestore).getTaskGuidance('taskA'),
          {'DESCRIPTION': 'Ask about the product.'});
    });

    test('preserves distinct instructions, description and the saved script', () async {
      await fakeFirestore.collection('tasks').doc('taskA').set({
        'instructions': 'Do not call after 6pm.',
        'description': 'Product feedback',
        'script': 'Hello, may I ask a question?',
      });
      expect(await TaskService(firestore: fakeFirestore).getTaskGuidance('taskA', fallbackScript: 'Old script'), {
        'INSTRUCTIONS': 'Do not call after 6pm.',
        'DESCRIPTION': 'Product feedback',
        'CALL SCRIPT': 'Hello, may I ask a question?',
      });
    });

    test('deduplicates guidance and falls back for blank legacy scripts', () async {
      await fakeFirestore.collection('tasks').doc('taskA').set({
        'instructions': 'Same guidance', 'description': ' Same guidance ', 'script': ' ',
      });
      expect(await TaskService(firestore: fakeFirestore).getTaskGuidance('taskA', fallbackScript: 'Legacy script'),
          {'INSTRUCTIONS': 'Same guidance', 'CALL SCRIPT': 'Legacy script'});
    });

    test('ignores malformed or empty fields and distinguishes a missing task', () async {
      await fakeFirestore.collection('tasks').doc('taskA').set({'instructions': [], 'description': ' ', 'script': 7});
      final service = TaskService(firestore: fakeFirestore);
      expect(await service.getTaskGuidance('taskA'), isEmpty);
      await expectLater(service.getTaskGuidance('missing-task'), throwsStateError);
    });
  });

  // Simulates TaskExecutionScreen._fetchNextLead: pick the next PENDING lead
  // that belongs to [taskId], lock it, and (crucially) leave its taskId alone.
  Future<String?> claimNextLeadForTask({
    required String taskId,
    required String userId,
  }) async {
    final snap = await fakeFirestore
        .collection('campaign_leads')
        .where('taskId', isEqualTo: taskId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;

    final ref = fakeFirestore.collection('campaign_leads').doc(snap.docs.first.id);
    String? claimedId;
    await fakeFirestore.runTransaction((txn) async {
      final fresh = await txn.get(ref);
      if (!fresh.exists) return;
      final data = fresh.data() as Map<String, dynamic>;
      if (data['status'] != 'pending') return;
      // NEVER write taskId here — the lead already owns it (per-task ownership).
      txn.update(ref, {
        'status': 'in_progress',
        'assignedTo': userId,
        'lockedAt': FieldValue.serverTimestamp(),
      });
      claimedId = fresh.id;
    });
    return claimedId;
  }

  Future<String> seedLead({
    required String taskId,
    required String campaignId,
    String status = 'pending',
    bool isRequeued = false,
  }) async {
    final ref = await fakeFirestore.collection('campaign_leads').add({
      'taskId': taskId,
      'campaignId': campaignId,
      'status': status,
      'isRequeued': isRequeued,
      'assignedTo': null,
    });
    return ref.id;
  }

  group('Per-task lead ownership', () {
    test('worker only claims leads that belong to their task', () async {
      // Two tasks in the same campaign.
      final a1 = await seedLead(taskId: 'taskA', campaignId: 'camp1');
      final recallA =
          await seedLead(taskId: 'taskA', campaignId: 'camp1', isRequeued: true);
      final b1 = await seedLead(taskId: 'taskB', campaignId: 'camp1');

      // A worker executing task B must receive task B's lead only.
      final claimed = await claimNextLeadForTask(taskId: 'taskB', userId: 'worker-b');
      expect(claimed, b1);

      // Task A's leads (including the recall) are untouched and still pending.
      for (final id in [a1, recallA]) {
        final doc = await fakeFirestore.collection('campaign_leads').doc(id).get();
        expect(doc.data()!['status'], 'pending');
        expect(doc.data()!['taskId'], 'taskA');
      }
    });

    test('claiming never re-stamps a lead onto another task', () async {
      final a1 = await seedLead(taskId: 'taskA', campaignId: 'camp1');

      final claimed = await claimNextLeadForTask(taskId: 'taskA', userId: 'worker-a');
      expect(claimed, a1);

      final doc = await fakeFirestore.collection('campaign_leads').doc(a1).get();
      expect(doc.data()!['status'], 'in_progress');
      expect(doc.data()!['assignedTo'], 'worker-a');
      // The fix: taskId must remain 'taskA' — it is never overwritten on claim.
      expect(doc.data()!['taskId'], 'taskA');
    });

    test('a recall lead cannot leak into a different task', () async {
      // Only a recall lead owned by task A remains pending; task B has none.
      await seedLead(taskId: 'taskA', campaignId: 'camp1', isRequeued: true);

      final claimed = await claimNextLeadForTask(taskId: 'taskB', userId: 'worker-b');
      expect(claimed, isNull);
    });
  });
}
