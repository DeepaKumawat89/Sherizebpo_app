import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({Key? key}) : super(key: key);

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String _audience = 'all';
  String _specificWorkerId = '';
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;
    if (_audience == 'specific' && _specificWorkerId.isEmpty) {
      SnackBarUtils.showInfo('Please provide a specific Employee ID or phone');
      return;
    }

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'audience': _audience,
        'targetId': _audience == 'specific' ? _specificWorkerId : null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
        'isRead': false, // Base status
      });

      if (!mounted) return;
      SnackBarUtils.showSuccess('Notification broadcast sent!');

      _titleController.clear();
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Send Notifications'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Broadcast Message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Notification Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.bell),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Message Body',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.messageSquare),
                ),
                maxLines: 4,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSizes.lg),
              const Text(
                'Target Audience',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
              RadioGroup<String>(
                groupValue: _audience,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _audience = value);
                  }
                },
                child: const Row(
                  children: [
                    Radio<String>(value: 'all'),
                    Text('All Employees', style: TextStyle(color: AppColors.textDark)),
                    SizedBox(width: AppSizes.xl),
                    Radio<String>(value: 'specific'),
                    Text('Specific Employee', style: TextStyle(color: AppColors.textDark)),
                  ],
                ),
              ),
              if (_audience == 'specific') ...[
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  onChanged: (v) => _specificWorkerId = v,
                  style: const TextStyle(color: AppColors.textDark),
                  decoration: const InputDecoration(
                    labelText: 'Employee ID (from Users list)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(LucideIcons.user),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.xxl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendNotification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
                  ),
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(LucideIcons.send),
                  label: const Text('Send Broadcast',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              const Divider(),
              const SizedBox(height: AppSizes.md),
              const Text(
                'Recent Broadcasts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              const SizedBox(height: AppSizes.md),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .orderBy('createdAt', descending: true)
                    .limit(10)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) return const Text('No recent broadcasts');

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(LucideIcons.bellRing,
                            color: AppColors.primary),
                        title: Text(data['title'] ?? 'No Title', style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600)),
                        subtitle: Text(data['message'] ?? '', style: const TextStyle(color: AppColors.textMuted)),
                        trailing: Text(
                            data['audience'] == 'all' ? 'Everyone' : 'Direct',
                            style: const TextStyle(color: AppColors.textMuted)),
                      );
                    },
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }
}
