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
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No chat conversations yet.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 16),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.md),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['clientName'] ?? 'Client').toString();
              final last = (data['lastMessage'] ?? 'No messages yet').toString();
              final status = (data['status'] ?? 'open').toString();
              final ts = data['updatedAt'];
              final when = ts is Timestamp ? _relative(ts.toDate()) : '';

              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.lg, vertical: AppSizes.xs),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: const Icon(LucideIcons.messageSquare,
                        color: AppColors.primary, size: 20),
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(when,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'resolved'
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.warning.withValues(alpha: 0.12),
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminChatThreadScreen(chatId: doc.id, clientName: name),
                    ),
                  ),
                ),
              );
            },
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
                style: TextStyle(color: AppColors.error)),
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
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Type a reply…',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.send, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEndedBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.md),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.lock, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text('This chat has ended.',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: _reopenChat,
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
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesRef.orderBy('createdAt', descending: false).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No messages in this conversation yet.',
                        style: TextStyle(color: AppColors.textMuted)),
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
                        ? TimeOfDay.fromDateTime(ts.toDate()).format(context)
                        : '';
                    return Align(
                      alignment: isAgent
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: AppSizes.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md, vertical: AppSizes.sm),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isAgent ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isAgent ? 12 : 0),
                            bottomRight: Radius.circular(isAgent ? 0 : 12),
                          ),
                          border: isAgent
                              ? null
                              : Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: isAgent
                                    ? Colors.white
                                    : AppColors.textDark,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
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
    );
  }
}
