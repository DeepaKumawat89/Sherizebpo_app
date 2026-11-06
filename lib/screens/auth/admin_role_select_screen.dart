import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../services/auth_service.dart';
import '../dashboard/admin_dashboard_screen.dart';

/// Shown right after an admin signs in. An admin may hold several roles; here
/// they pick which one to work as. Roles they hold open the dashboard scoped to
/// that role; roles they do not hold remain disabled.
///
/// ponytail: this gates the UI only. Firestore rules + Cloud Functions still
/// enforce the admin's PRIMARY role claim, so a non-super admin switching into a
/// secondary role sees that role's screen but data-layer writes for it are still
/// governed by their primary claim. Making secondary roles fully privileged at
/// the data layer would require expanding custom claims + security rules.
class AdminRoleSelectScreen extends StatelessWidget {
  const AdminRoleSelectScreen({super.key, this.auth, this.firestore});

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  static const List<_RoleCard> _roles = [
    _RoleCard(
      role: 'super_admin',
      label: 'Super Admin',
      description: 'Full platform access',
      icon: LucideIcons.shieldCheck,
      color: AppColors.primary,
    ),
    _RoleCard(
      role: 'task_review_admin',
      label: 'Task Reviewer',
      description: 'Approve or reject task submissions',
      icon: LucideIcons.checkSquare,
      color: AppColors.success,
    ),
    _RoleCard(
      role: 'kyc_admin',
      label: 'KYC & Withdrawals Admin',
      description: 'Review KYC and process payouts',
      icon: LucideIcons.fileCheck,
      color: AppColors.warning,
    ),
    _RoleCard(
      role: 'support_admin',
      label: 'Support Admin',
      description: 'Resolve tickets and live chats',
      icon: LucideIcons.helpCircle,
      color: AppColors.info,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Admin access',
            style: TextStyle(fontSize: 18, letterSpacing: 0)),
        automaticallyImplyLeading: false,
      ),
      body: user == null
          ? _message(context, 'Not signed in.')
          : FutureBuilder<DocumentSnapshot>(
              future: (firestore ?? FirebaseFirestore.instance)
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    !snapshot.data!.exists) {
                  return _message(context,
                      'Failed to load your profile. Please try again.');
                }

                final data =
                    snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final myRoles = _rolesOf(data);
                // Super admin / admin can operate as any role.
                final isSuper = myRoles.contains('super_admin') ||
                    myRoles.contains('admin');

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSizes.sm),
                          Row(
                            children: [
                              ClipRect(
                                child: Align(
                                  widthFactor: 0.5,
                                  heightFactor: 0.5,
                                  alignment: const Alignment(-0.1, -0.4),
                                  child: Image.asset(
                                      'assets/images/sherize_logo.png',
                                      width: 120,
                                      height: 120,
                                      excludeFromSemantics: true),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text('Sherize',
                                    style: TextStyle(
                                        color: colors.onSurface,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Text('Select workspace',
                              style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0)),
                          const SizedBox(height: 16),
                          ..._roles.map((r) {
                            final hasAccess =
                                isSuper || myRoles.contains(r.role);
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSizes.md),
                              child: _roleTile(context, r, hasAccess),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  List<String> _rolesOf(Map<String, dynamic> data) {
    final raw = data['roles'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    final single = data['role']?.toString();
    return single == null ? <String>[] : [single];
  }

  Widget _roleTile(BuildContext context, _RoleCard r, bool hasAccess) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: !hasAccess
            ? null
            : () async {
                final user = (auth ?? FirebaseAuth.instance).currentUser;
                if (user == null) return;
                try {
                  await AuthService.rememberAdminWorkspace(user.uid, r.role);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not save workspace. Please try again.')));
                  }
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminDashboardScreen(
                        activeRole: r.role, auth: auth, firestore: firestore),
                  ),
                );
              },
        child: Semantics(
          button: true,
          enabled: hasAccess,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(r.icon, size: 22, color: r.color),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.description,
                        style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                            letterSpacing: 0),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasAccess ? LucideIcons.chevronRight : LucideIcons.lock,
                  size: 18,
                  color: colors.onSurfaceVariant,
                  semanticLabel: hasAccess ? null : 'No access',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

class _RoleCard {
  final String role;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const _RoleCard({
    required this.role,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}
