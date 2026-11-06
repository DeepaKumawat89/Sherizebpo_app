import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/services/mail_service.dart';

/// Self-check for the in-app mail (threaded inbox) service — the core of the
/// support team's email feature. Covers worker⇄support threads, the shared
/// support queue, and unread flipping on reply/read.
void main() {
  late FakeFirebaseFirestore fake;
  late MailService mail;

  setUp(() {
    fake = FakeFirebaseFirestore();
    mail = MailService(firestore: fake);
  });

  test('worker support thread is created, queued, and unread flips correctly',
      () async {
    final threadId = await mail.startWorkerSupportThread(
      workerId: 'worker-1',
      workerName: 'Asha',
      subject: 'Payment issue',
      body: 'I did not receive my payment.',
    );

    final data =
        (await fake.collection('mail_threads').doc(threadId).get()).data()!;
    expect(data['type'], 'worker_support');
    expect(data['participants'], ['worker-1']);
    expect(data['subject'], 'Payment issue');
    // The sender's own message is never unread for them.
    expect(MailService.isUnreadFor('worker-1', data), isFalse);

    final msgs = await fake
        .collection('mail_threads')
        .doc(threadId)
        .collection('messages')
        .get();
    expect(msgs.docs.length, 1);

    // Shows up in the shared support queue.
    final queue = await mail.workerSupportQueue().first;
    expect(queue.docs.map((d) => d.id), contains(threadId));

    // Support replies → unread for the worker, not for the support sender.
    await mail.sendMessage(
      threadId: threadId,
      senderId: 'support-1',
      senderName: 'Support',
      senderRole: 'support_admin',
      body: 'We are looking into it.',
    );
    final afterReply =
        (await fake.collection('mail_threads').doc(threadId).get()).data()!;
    expect(MailService.isUnreadFor('worker-1', afterReply), isTrue);
    expect(MailService.isUnreadFor('support-1', afterReply), isFalse);

    // Worker opens → marked read.
    await mail.markRead(threadId, 'worker-1');
    final afterRead =
        (await fake.collection('mail_threads').doc(threadId).get()).data()!;
    expect(MailService.isUnreadFor('worker-1', afterRead), isFalse);
  });
}
