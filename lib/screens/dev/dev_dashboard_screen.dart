import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../services/credit_config_service.dart';

/// Developer Console — the single control surface for developer mode.
///
/// Capabilities:
///  • Credit control (toggle / edit / lock the Novantix attribution)
///  • Role management (promote / demote any user)
///  • Maintenance mode toggle
///  • Quick access to every dashboard (super_admin / admin / worker)
///  • Platform earnings overview
///
/// Guarded by [AuthService.isDeveloper] — any non-developer is bounced out.
class DevDashboardScreen extends StatefulWidget {
  const DevDashboardScreen({Key? key}) : super(key: key);

  @override
  State<DevDashboardScreen> createState() => _DevDashboardScreenState();
}

class _DevDashboardScreenState extends State<DevDashboardScreen> {
  final _creditCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _websiteUrlCtrl = TextEditingController();
  final _roleEmailCtrl = TextEditingController();

  String _selectedRole = 'worker';
  bool _savingCredit = false;
  bool _savingRole = false;
  bool _seededCreditFields = false;

  static const List<String> _roles = [
    'worker',
    'admin',
    'super_admin',
    'task_review_admin',
    'kyc_admin',
    'support_admin',
    'payment_admin',
    'developer',
  ];

  @override
  void dispose() {
    _creditCtrl.dispose();
    _companyCtrl.dispose();
    _websiteCtrl.dispose();
    _websiteUrlCtrl.dispose();
    _roleEmailCtrl.dispose();
    super.dispose();
  }

  void _seedCreditFields(CreditConfigService config) {
    if (_seededCreditFields) return;
    _creditCtrl.text = config.credit;
    _companyCtrl.text = config.company;
    _websiteCtrl.text = config.website;
    _websiteUrlCtrl.text = config.websiteUrl;
    _seededCreditFields = true;
  }

  Future<void> _saveCredit(CreditConfigService config) async {
    setState(() => _savingCredit = true);
    final err = await config.updateConfig(
      credit: _creditCtrl.text.trim(),
      company: _companyCtrl.text.trim(),
      website: _websiteCtrl.text.trim(),
      websiteUrl: _websiteUrlCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingCredit = false);
    if (err == null) {
      SnackBarUtils.showSuccess('Credit updated');
    } else {
      SnackBarUtils.showError(err);
    }
  }

  Future<void> _applyRole() async {
    final email = _roleEmailCtrl.text.trim();
    if (email.isEmpty) {
      SnackBarUtils.showError('Enter the user\'s email');
      return;
    }
    setState(() => _savingRole = true);
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        SnackBarUtils.showError('No user found with that email');
      } else {
        await query.docs.first.reference.update({
          'role': _selectedRole,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        SnackBarUtils.showSuccess(
          'Role set to ${_selectedRole == 'worker' ? 'employee' : _selectedRole}',
        );
        _roleEmailCtrl.clear();
      }
    } catch (e) {
      SnackBarUtils.showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _savingRole = false);
    }
  }

  Future<void> _setMaintenance(bool value) async {
    try {
      await FirebaseFirestore.instance
          .collection('platform_settings')
          .doc('main')
          .set({'maintenanceMode': value}, SetOptions(merge: true));
      SnackBarUtils.showSuccess(
          value ? 'Maintenance mode ON' : 'Maintenance mode OFF');
    } catch (e) {
      SnackBarUtils.showError('Failed: $e');
    }
  }

  Future<void> _logout() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.onboarding, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // Defense in depth: only the developer may ever see this screen.
    if (!auth.isDeveloper) {
      return const Scaffold(
        body: Center(child: Text('Access denied')),
      );
    }

    final config = context.watch<CreditConfigService>();
    _seedCreditFields(config);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Row(
          children: [
            Icon(LucideIcons.terminal, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Developer Console',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(LucideIcons.logOut, color: Colors.white70),
            onPressed: _logout,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.base),
        children: [
          _creditCard(config),
          _rolesCard(),
          _maintenanceCard(),
          _dashboardsCard(),
          _earningsCard(),
          const SizedBox(height: AppSizes.xl),
        ],
      ),
    );
  }

  // ── Credit control ────────────────────────────────────────────
  Widget _creditCard(CreditConfigService config) {
    return _card(
      icon: LucideIcons.copyright,
      title: 'Credit / Branding',
      children: [
        _switchRow(
          'Show credit in apps',
          config.enabled,
          (v) async {
            final err = await config.updateConfig(enabled: v);
            if (err != null) SnackBarUtils.showError(err);
          },
        ),
        _switchRow(
          'Lock (block other roles)',
          config.locked,
          (v) async {
            final err = await config.updateConfig(locked: v);
            if (err != null) SnackBarUtils.showError(err);
          },
        ),
        const SizedBox(height: AppSizes.sm),
        _field('Line 1 (credit)', _creditCtrl),
        _field('Line 2 (company)', _companyCtrl),
        _field('Website label', _websiteCtrl),
        _field('Website URL', _websiteUrlCtrl),
        const SizedBox(height: AppSizes.sm),
        _primaryButton(
          _savingCredit ? 'Saving…' : 'Save credit',
          _savingCredit ? null : () => _saveCredit(config),
        ),
      ],
    );
  }

  // ── Role management ───────────────────────────────────────────
  Widget _rolesCard() {
    return _card(
      icon: LucideIcons.userCog,
      title: 'Role Management',
      children: [
        _field('User email', _roleEmailCtrl),
        const SizedBox(height: AppSizes.sm),
        DropdownButtonFormField<String>(
          initialValue: _selectedRole,
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration('Role'),
          items: _roles
              .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(r == 'worker' ? 'employee' : r),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedRole = v ?? 'worker'),
        ),
        const SizedBox(height: AppSizes.sm),
        _primaryButton(
          _savingRole ? 'Applying…' : 'Apply role',
          _savingRole ? null : _applyRole,
        ),
      ],
    );
  }

  // ── Maintenance ───────────────────────────────────────────────
  Widget _maintenanceCard() {
    return _card(
      icon: LucideIcons.wrench,
      title: 'Maintenance Mode',
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('platform_settings')
              .doc('main')
              .snapshots(),
          builder: (context, snap) {
            final on = snap.data?.data()?['maintenanceMode'] == true;
            return _switchRow(
              'App under maintenance (blocks non-developers)',
              on,
              _setMaintenance,
            );
          },
        ),
      ],
    );
  }

  // ── Dashboards ────────────────────────────────────────────────
  Widget _dashboardsCard() {
    return _card(
      icon: LucideIcons.layoutDashboard,
      title: 'Dashboards',
      children: [
        _linkRow('Admin / Super Admin dashboard', AppRoutes.adminDashboard),
        _linkRow('Employee dashboard', AppRoutes.dashboard),
        _linkRow('All users', AppRoutes.adminUsers),
        _linkRow('Withdrawals', AppRoutes.adminWithdrawals),
        _linkRow('Tasks', AppRoutes.adminTasks),
      ],
    );
  }

  // ── Earnings ──────────────────────────────────────────────────
  Widget _earningsCard() {
    return _card(
      icon: LucideIcons.wallet,
      title: 'Platform Earnings',
      children: [
        Row(
          children: [
            Expanded(
              child: _countTile(
                'Earnings records',
                FirebaseFirestore.instance.collection('platform_earnings'),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: _countTile(
                'Pending withdrawals',
                FirebaseFirestore.instance
                    .collection('withdraw_requests')
                    .where('status', isEqualTo: 'pending'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        _linkRow('Open full analytics', AppRoutes.adminDashboard),
      ],
    );
  }

  Widget _countTile(String label, Query<Map<String, dynamic>> query) {
    return FutureBuilder<AggregateQuerySnapshot>(
      future: query.count().get(),
      builder: (context, snap) {
        final count = snap.data?.count;
        return Container(
          padding: const EdgeInsets.all(AppSizes.base),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count?.toString() ?? '…',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  // ── Reusable UI ───────────────────────────────────────────────
  Widget _card({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.base),
      padding: const EdgeInsets.all(AppSizes.base),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSizes.base),
          ...children,
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration(label),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _linkRow(String label, String route) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            const Icon(LucideIcons.chevronRight,
                color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
        child: Text(label,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
