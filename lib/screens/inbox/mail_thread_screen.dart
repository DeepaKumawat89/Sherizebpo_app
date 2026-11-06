import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../services/mail_service.dart';

/// A single mail thread (subject + back-and-forth messages) with a reply box.
///
/// Shared by workers and support/admins — the caller passes its own identity so
/// replies are attributed correctly, and [canClose] enables the resolve action
/// on the support side.
class MailThreadScreen extends StatefulWidget {
  final String threadId;
  final String subject;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final bool canClose;

  const MailThreadScreen({
    Key? key,
    required this.threadId,
    required this.subject,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.canClose = false,
  }) : super(key: key);

  @override
  State<MailThreadScreen> createState() => _MailThreadScreenState();
}

class _MailThreadScreenState extends State<MailThreadScreen> {
  final MailService _mail = MailService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Mark this thread read for the current user as soon as they open it.
    _mail.markRead(widget.threadId, widget.currentUserId);
  }

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
      await _mail.sendMessage(
        threadId: widget.threadId,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        senderRole: widget.currentUserRole,
        body: text,
      );
    } catch (e) {
      if (mounted) {
        _controller.text = text;
        SnackBarUtils.showError('Could not send: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markResolved() async {
    try {
      await _mail.setStatus(widget.threadId, 'closed');
      if (mounted) SnackBarUtils.showSuccess('Marked as resolved');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.subject.isEmpty ? 'Conversation' : widget.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.canClose)
            IconButton(
              icon: const Icon(LucideIcons.checkCircle2),
              tooltip: 'Mark resolved',
              onPressed: _markResolved,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mail.messages(widget.threadId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet.',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSizes.md),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final mine = data['senderId'] == widget.currentUserId;
                    return _bubble(data, mine, isDark);
                  },
                );
              },
            ),
          ),
          _composer(isDark),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> data, bool mine, bool isDark) {
    final body = (data['body'] ?? '').toString();
    final senderName = (data['senderName'] ?? '').toString();
    final ts = data['createdAt'];
    final when = ts is Timestamp ? DateFormat('d MMM, h:mm a').format(ts.toDate()) : '';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSizes.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md, vertical: AppSizes.sm),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.primary
              : (isDark ? Colors.white10 : Colors.white),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: mine
              ? null
              : Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine && senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : AppColors.primary,
                  ),
                ),
              ),
            Text(
              body,
              style: TextStyle(
                color: mine
                    ? Colors.white
                    : (isDark ? Colors.white : AppColors.textDark),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              when,
              style: TextStyle(
                fontSize: 10,
                color: mine ? Colors.white70 : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Write a reply…',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : AppColors.surfaceVariant,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: AppSizes.sm),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(LucideIcons.send,
                          color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
