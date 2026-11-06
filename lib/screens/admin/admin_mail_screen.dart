import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/constants/constants.dart';
import '../../services/mail_service.dart';
import '../inbox/mail_thread_screen.dart';

/// Support/admin mail console — the shared queue of worker ⇄ support threads.
class AdminMailScreen extends StatefulWidget {
  const AdminMailScreen({Key? key}) : super(key: key);

  @override
  State<AdminMailScreen> createState() => _AdminMailScreenState();
}

class _AdminMailScreenState extends State<AdminMailScreen> {
  final MailService _mail = MailService();
  final user = FirebaseAuth.instance.currentUser;

  String _name = 'Admin';
  String _role = 'admin';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      final data = doc.data() ?? {};
      _name = (data['name'] ?? data['fullName'] ?? 'Admin').toString();
      _role = (data['role'] ?? 'admin').toString();
    } catch (_) {
      // Keep defaults on error.
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Employee Mail'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _mail.workerSupportQueue(),
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
            return _empty('No employee mail yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSizes.md),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final who = (data['createdByName'] ?? 'Employee').toString();
              return _threadTile(doc.id, data, subtitlePrefix: who);
            },
          );
        },
      ),
    );
  }

  Widget _threadTile(String id, Map<String, dynamic> data,
      {required String subtitlePrefix}) {
    final subject = (data['subject'] ?? 'No subject').toString();
    final last = (data['lastMessage'] ?? '').toString();
    final status = (data['status'] ?? 'open').toString();
    final ts = data['lastMessageAt'];
    final when = ts is Timestamp ? _relative(ts.toDate()) : '';
    final unread = MailService.isUnreadFor(user!.uid, data);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.xs),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: const Icon(LucideIcons.mail, color: AppColors.primary, size: 20),
        ),
        title: Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: unread ? FontWeight.w800 : FontWeight.w700),
        ),
        subtitle: Text(
          '$subtitlePrefix · $last',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(when,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
              currentUserName: _name,
              currentUserRole: _role,
              canClose: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.mail, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSizes.md),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, height: 1.4)),
          ],
        ),
      ),
    );
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
