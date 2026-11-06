import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app mail (threaded inbox) service.
///
/// Worker ⇄ support-desk conversations live in the `mail_threads` collection.
/// Any support admin can see/answer these (a shared queue), so support agents
/// are *not* listed individually in `participants` (only the worker is).
///
/// Each thread carries the `subject`; the back-and-forth lives in the
/// `messages` sub-collection. `readBy` holds the uids that have seen the latest
/// message (reset to just the sender whenever a new message is posted), which
/// drives the unread badges.
class MailService {
  MailService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String workerSupport = 'worker_support';

  CollectionReference<Map<String, dynamic>> get _threads =>
      _db.collection('mail_threads');

  // ─── Streams ──────────────────────────────────────────────────────────────

  /// Threads the given user participates in, newest activity first.
  Stream<QuerySnapshot<Map<String, dynamic>>> myThreads(String uid) => _threads
      .where('participants', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .snapshots();

  /// The shared worker ⇄ support queue (all support conversations).
  Stream<QuerySnapshot<Map<String, dynamic>>> workerSupportQueue() => _threads
      .where('type', isEqualTo: workerSupport)
      .orderBy('lastMessageAt', descending: true)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String threadId) =>
      _threads
          .doc(threadId)
          .collection('messages')
          .orderBy('createdAt', descending: false)
          .snapshots();

  // ─── Thread creation ──────────────────────────────────────────────────────

  /// Worker starts a new mail to the support desk.
  Future<String> startWorkerSupportThread({
    required String workerId,
    required String workerName,
    required String subject,
    required String body,
  }) {
    return _createThread(
      type: workerSupport,
      subject: subject,
      body: body,
      participants: [workerId],
      senderId: workerId,
      senderName: workerName,
      senderRole: 'worker',
    );
  }

  Future<String> _createThread({
    required String type,
    required String subject,
    required String body,
    required List<String> participants,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final threadRef = _threads.doc();
    final now = FieldValue.serverTimestamp();

    await threadRef.set({
      'subject': subject.trim(),
      'type': type,
      'participants': participants,
      'createdBy': senderId,
      'createdByName': senderName,
      'createdByRole': senderRole,
      'lastMessage': body.trim(),
      'lastMessageAt': now,
      'lastSenderId': senderId,
      'status': 'open',
      'readBy': [senderId],
      'createdAt': now,
    });

    await threadRef.collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'body': body.trim(),
      'createdAt': now,
    });

    return threadRef.id;
  }

  // ─── Replies / status ─────────────────────────────────────────────────────

  Future<void> sendMessage({
    required String threadId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String body,
  }) async {
    final threadRef = _threads.doc(threadId);
    final now = FieldValue.serverTimestamp();

    await threadRef.collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'body': body.trim(),
      'createdAt': now,
    });

    // A new message is unread for everyone except its sender.
    await threadRef.set({
      'lastMessage': body.trim(),
      'lastMessageAt': now,
      'lastSenderId': senderId,
      'status': 'open',
      'readBy': [senderId],
    }, SetOptions(merge: true));
  }

  /// Marks the latest message as read by [uid].
  Future<void> markRead(String threadId, String uid) {
    return _threads.doc(threadId).set({
      'readBy': FieldValue.arrayUnion([uid]),
    }, SetOptions(merge: true));
  }

  Future<void> setStatus(String threadId, String status) {
    return _threads.doc(threadId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// True when [uid] has NOT yet read the latest message on [threadData].
  static bool isUnreadFor(String uid, Map<String, dynamic> threadData) {
    final readBy = (threadData['readBy'] as List?)?.cast<String>() ?? const [];
    final lastSender = threadData['lastSenderId'] as String?;
    // Never show your own last message as unread.
    if (lastSender == uid) return false;
    return !readBy.contains(uid);
  }
}
