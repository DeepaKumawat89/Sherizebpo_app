import 'dart:math' as math;
 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
 
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
 
/// Support-desk console listing live-chat threads opened from the client portal.
/// Support admins (and admins / super admins) can open a thread and reply.
class AdminSupportChatsScreen extends StatelessWidget {
  const AdminSupportChatsScreen({Key? key}) : super(key: key);
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Live Chats'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('support_chats')
            .orderBy('updatedAt', descending: true)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.alertCircle,
                          size: 30, color: AppColors.error),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
 
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(LucideIcons.messageSquare,
                        size: 38, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No chat conversations yet.',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }
 
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSizes.md),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSizes.sm),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['clientName'] ?? 'Client').toString();
                  final last =
                      (data['lastMessage'] ?? 'No messages yet').toString();
                  final status = (data['status'] ?? 'open').toString();
                  final ts = data['updatedAt'];
                  final when = ts is Timestamp ? _relative(ts.toDate()) : '';
 
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminChatThreadScreen(
                              chatId: doc.id, clientName: name),
                        ),
                      ),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(LucideIcons.messageSquare,
                                  color: AppColors.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(
                                    last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(when,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: status == 'resolved'
                                        ? AppColors.success
                                            .withValues(alpha: 0.12)
                                        : AppColors.warning
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: status == 'resolved'
                                          ? AppColors.success
                                          : AppColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
 
  static String _relative(DateTime d) {
    final mins = DateTime.now().difference(d).inMinutes;
    if (mins < 1) return 'now';
    if (mins < 60) return '${mins}m';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '${hrs}h';
    return '${hrs ~/ 24}d';
  }
}
 
/// A single chat thread with the client, with an agent reply box.
class AdminChatThreadScreen extends StatefulWidget {
  final String chatId;
  final String clientName;
 
  const AdminChatThreadScreen({
    Key? key,
    required this.chatId,
    required this.clientName,
  }) : super(key: key);
 
  @override
  State<AdminChatThreadScreen> createState() => _AdminChatThreadScreenState();
}
 
class _AdminChatThreadScreenState extends State<AdminChatThreadScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
 
  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('support_chats').doc(widget.chatId);
 
  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _chatRef.collection('messages');
 
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
 
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await _messagesRef.add({
        'sender': 'agent',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _chatRef.set({
        'lastMessage': text,
        'status': 'open',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        _controller.text = text;
        SnackBarUtils.showError('Could not send: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
 
  Future<void> _endChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End chat?'),
        content: const Text(
            'This closes the conversation and posts a closing message to the '
            'client. You can reopen it later if needed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Chat',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _messagesRef.add({
        'sender': 'agent',
        'text': 'This chat has been closed by support.',
        'system': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _chatRef.set({
        'status': 'resolved',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) SnackBarUtils.showSuccess('Chat ended');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Error: $e');
    }
  }
 
  Future<void> _reopenChat() async {
    try {
      await _chatRef.set({
        'status': 'open',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) SnackBarUtils.showSuccess('Chat reopened');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Error: $e');
    }
  }
 
  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Type a reply…',
                filled: true,
                fillColor: AppColors.background,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          IconButton(
            onPressed: _sending ? null : _send,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: AppColors.primary,
              disabledBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.6),
              shape: const CircleBorder(),
            ),
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.send, size: 20, color: Colors.white),
          ),
        ],
      ),
    );
  }
 
  Widget _buildEndedBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(LucideIcons.lock,
                size: 16, color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSizes.sm + 2),
          const Expanded(
            child: Text('This chat has ended.',
                style: TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ),
          OutlinedButton(
            onPressed: _reopenChat,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.clientName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _endChat,
            icon: const Icon(LucideIcons.xCircle,
                color: Colors.white, size: 18),
            label: const Text('End Chat',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _messagesRef
                      .orderBy('createdAt', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(LucideIcons.messageSquare,
                                  size: 32, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 14),
                            const Text('No messages in this conversation yet.',
                                style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent);
                      }
                    });
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSizes.md),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final m = docs[index].data() as Map<String, dynamic>;
                        final isAgent = (m['sender'] ?? '') == 'agent';
                        final text = (m['text'] ?? '').toString();
                        final ts = m['createdAt'];
                        final time = ts is Timestamp
                            ? TimeOfDay.fromDateTime(ts.toDate())
                                .format(context)
                            : '';
                        return Align(
                          alignment: isAgent
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppSizes.sm),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: math.min(
                                  MediaQuery.of(context).size.width * 0.75,
                                  520),
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isAgent ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isAgent ? 16 : 4),
                                bottomRight: Radius.circular(isAgent ? 4 : 16),
                              ),
                              border: isAgent
                                  ? null
                                  : Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: isAgent
                                          ? Colors.white
                                          : AppColors.textDark,
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isAgent
                                        ? Colors.white70
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _chatRef.snapshots(),
                  builder: (context, snap) {
                    final ended =
                        (snap.data?.data()?['status'] ?? 'open') == 'resolved';
                    if (ended) return _buildEndedBar();
                    return _buildComposer();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}