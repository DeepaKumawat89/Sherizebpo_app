import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _minWithdrawalCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _maxTaskPayoutCtrl = TextEditingController();
  final _announcementCtrl = TextEditingController();
  bool _notificationsEnabled = true;
  bool _maintenanceMode = false;

  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _minWithdrawalCtrl.dispose();
    _commissionCtrl.dispose();
    _maxTaskPayoutCtrl.dispose();
    _announcementCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('platform_settings')
          .doc('main')
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _minWithdrawalCtrl.text =
            (data['minWithdrawalAmount']?.toString() ?? '500');
        _commissionCtrl.text =
            (data['platformCommission']?.toString() ?? '10');
        _maxTaskPayoutCtrl.text =
            (data['maxTaskPayout']?.toString() ?? '1000');
        _announcementCtrl.text = data['announcement'] ?? '';
        _notificationsEnabled = data['notificationsEnabled'] ?? true;
        _maintenanceMode = data['maintenanceMode'] ?? false;
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('platform_settings')
          .doc('main')
          .set({
        'minWithdrawalAmount':
            double.parse(_minWithdrawalCtrl.text.trim()),
        'platformCommission': double.parse(_commissionCtrl.text.trim()),
        'maxTaskPayout': double.parse(_maxTaskPayoutCtrl.text.trim()),
        'notificationsEnabled': _notificationsEnabled,
        'maintenanceMode': _maintenanceMode,
        'announcement': _announcementCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'admin',
      }, SetOptions(merge: true));

      if (!mounted) return;
      SnackBarUtils.showSuccess('Settings saved successfully');
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError('Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Settings'),
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
              const Divider(),
              const SizedBox(height: AppSizes.md),

              // ── Financial Settings ──────────────────────────────────
              const Text('Financial Settings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _minWithdrawalCtrl,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Minimum Withdrawal Amount (₹)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.indianRupee),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.isEmpty || double.tryParse(v) == null)
                        ? 'Valid amount required'
                        : null,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _maxTaskPayoutCtrl,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Max Task Payout Limit (₹)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.indianRupee),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.isEmpty || double.tryParse(v) == null)
                        ? 'Valid amount required'
                        : null,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _commissionCtrl,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Platform Commission (%)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.percent),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.isEmpty || double.tryParse(v) == null)
                        ? 'Valid percentage required'
                        : null,
              ),
              const SizedBox(height: AppSizes.xl),
              const Divider(),
              const SizedBox(height: AppSizes.md),

              // ── System Settings ─────────────────────────────────────
              const Text('System Settings',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: AppSizes.md),
              SwitchListTile(
                title: const Text('Global Notifications Enabled',
                    style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Allow system to send push notifications to users',
                    style: TextStyle(color: AppColors.textMuted)),
                value: _notificationsEnabled,
                onChanged: (val) =>
                    setState(() => _notificationsEnabled = val),
                secondary: const Icon(LucideIcons.bell),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.primary,
              ),
              const SizedBox(height: AppSizes.md),
              SwitchListTile(
                title: const Text('Maintenance Mode',
                    style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Block employee access and show maintenance message',
                    style: TextStyle(color: AppColors.textMuted)),
                value: _maintenanceMode,
                onChanged: (val) => setState(() => _maintenanceMode = val),
                secondary: const Icon(LucideIcons.construction, color: AppColors.error),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.error,
              ),
              const SizedBox(height: AppSizes.md),
              TextFormField(
                controller: _announcementCtrl,
                style: const TextStyle(color: AppColors.textDark),
                decoration: const InputDecoration(
                  labelText: 'Global Announcement Message',
                  hintText: 'e.g. Server upgrade tonight at 10 PM',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(LucideIcons.megaphone),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppSizes.xxl),
              const SizedBox(height: AppSizes.xxl),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSizes.md),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(LucideIcons.save),
                  label: const Text('Save Settings',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: AppSizes.xxl),
              const SizedBox(height: AppSizes.xl),
              const SizedBox(height: AppSizes.xl),
            ],
          ),
        ),
      ),
    );
  }
}
