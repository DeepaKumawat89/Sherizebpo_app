import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../services/mail_service.dart';
import 'mail_thread_screen.dart';

/// Worker-facing inbox: threaded mail to/from the support desk.
class InboxScreen extends StatefulWidget {
  const InboxScreen({Key? key}) : super(key: key);

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final MailService _mail = MailService();
  final user = FirebaseAuth.instance.currentUser;
  String _userName = 'Employee';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      final data = doc.data() ?? {};
      final name = (data['fullName'] ?? data['name'] ?? '').toString();
      if (name.isNotEmpty && mounted) setState(() => _userName = name);
    } catch (_) {
      // Non-fatal — fall back to the default label.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view your inbox.')),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _composeToSupport,
        icon: const Icon(LucideIcons.plusCircle, size: 18),
        label: const Text('New Mail'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _mail.myThreads(user!.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _emptyState(isDark);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.md),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _threadTile(doc.id, doc.data(), isDark);
            },
          );
        },
      ),
    );
  }

  Widget _threadTile(String id, Map<String, dynamic> data, bool isDark) {
    final subject = (data['subject'] ?? 'No subject').toString();
    final last = (data['lastMessage'] ?? '').toString();
    final status = (data['status'] ?? 'open').toString();
    final ts = data['lastMessageAt'];
    final when = ts is Timestamp ? _relative(ts.toDate()) : '';
    final unread = MailService.isUnreadFor(user!.uid, data);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md, vertical: AppSizes.xs),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(LucideIcons.mail, color: AppColors.primary, size: 20),
        ),
        title: Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
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
            const SizedBox(height: 6),
            if (unread)
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
              )
            else if (status == 'closed')
              const Icon(LucideIcons.checkCircle2,
                  size: 14, color: AppColors.success),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MailThreadScreen(
              threadId: id,
              subject: subject,
              currentUserId: user!.uid,
              currentUserName: _userName,
              currentUserRole: 'worker',
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.mail,
                size: 48, color: isDark ? Colors.white24 : AppColors.textMuted),
            const SizedBox(height: AppSizes.lg),
            Text('No mail yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                )),
            const SizedBox(height: AppSizes.sm),
            const Text(
              'Send a message to our support team and their replies will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _composeToSupport() async {
    final result = await showModalBottomSheet<_ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposeSheet(title: 'New mail to Support'),
    );
    if (result == null) return;

    try {
      final threadId = await _mail.startWorkerSupportThread(
        workerId: user!.uid,
        workerName: _userName,
        subject: result.subject,
        body: result.body,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MailThreadScreen(
            threadId: threadId,
            subject: result.subject,
            currentUserId: user!.uid,
            currentUserName: _userName,
            currentUserRole: 'worker',
          ),
        ),
      );
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Could not send: $e');
    }
  }

  static String _relative(DateTime d) {
    final mins = DateTime.now().difference(d).inMinutes;
    if (mins < 1) return 'now';
    if (mins < 60) return '${mins}m';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '${hrs}h';
    final days = hrs ~/ 24;
    if (days < 7) return '${days}d';
    return DateFormat('d MMM').format(d);
  }
}

// ─── Shared compose result + bottom sheet ────────────────────────────────────

class _ComposeResult {
  final String subject;
  final String body;
  const _ComposeResult(this.subject, this.body);
}

/// Reusable subject + body composer used by workers and admins.
class _ComposeSheet extends StatefulWidget {
  final String title;
  const _ComposeSheet({required this.title});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      SnackBarUtils.showError('Please enter a subject and a message.');
      return;
    }
    Navigator.pop(context, _ComposeResult(subject, body));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSizes.radiusXl)),
        ),
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                )),
            const SizedBox(height: AppSizes.lg),
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Subject',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
                ),
                onPressed: _submit,
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Send'),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
  }
}
