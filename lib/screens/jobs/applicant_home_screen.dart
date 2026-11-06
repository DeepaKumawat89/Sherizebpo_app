import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';

/// Home screen for NEW workers who have not been hired yet
/// (users.onboardingStatus == 'applicant'). They can only browse job openings
/// and apply. Once the super admin hires them (issues email + password and sets
/// onboardingStatus = 'active'), they log in with those credentials and the
/// task marketplace unlocks.
class ApplicantHomeScreen extends StatefulWidget {
  const ApplicantHomeScreen({Key? key}) : super(key: key);

  @override
  State<ApplicantHomeScreen> createState() => _ApplicantHomeScreenState();
}

class _ApplicantHomeScreenState extends State<ApplicantHomeScreen> {
  String _name = '';
  String _email = '';
  String _phone = '';
  final Set<String> _applying = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _phone = user.phoneNumber ?? '';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? {};
      if (!mounted) return;
      setState(() {
        _name = (data['fullName'] ?? data['name'] ?? '').toString();
        _email = (data['email'] ?? user.email ?? '').toString();
        _phone = (data['phone'] ?? user.phoneNumber ?? '').toString();
      });
    } catch (_) {/* ignore */}
  }

  Future<void> _apply(String jobId, String jobTitle) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _applying.add(jobId));
    try {
      await FirebaseFirestore.instance.collection('job_applications').add({
        'jobId': jobId,
        'jobTitle': jobTitle,
        'applicantUid': user.uid,
        'applicantName': _name,
        'applicantPhone': _phone,
        'applicantEmail': _email,
        'status': 'applied',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) SnackBarUtils.showSuccess('Applied to "$jobTitle". We\'ll review your application.');
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Could not apply: $e');
    } finally {
      if (mounted) setState(() => _applying.remove(jobId));
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Job Openings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(LucideIcons.logOut, size: 20),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        // Track this applicant's own applications to show per-job status.
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('job_applications')
              .where('applicantUid', isEqualTo: uid)
              .snapshots(),
          builder: (context, appSnap) {
            final Map<String, String> appliedStatus = {};
            for (final d in (appSnap.data?.docs ?? [])) {
              final m = d.data() as Map<String, dynamic>;
              appliedStatus[m['jobId']?.toString() ?? ''] =
                  (m['status'] ?? 'applied').toString();
            }
            final hasApplied = appliedStatus.isNotEmpty;

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _welcomeCard(isDark, hasApplied),
                      const SizedBox(height: AppSizes.lg),
                      Text('Open Positions',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSizes.sm),
                    ]),
                  ),
                ),
                _jobsList(appliedStatus),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _welcomeCard(bool isDark, bool hasApplied) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(hasApplied ? LucideIcons.clock : LucideIcons.briefcase,
              color: AppColors.primary, size: 22),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasApplied ? 'Application under review' : 'Welcome${_name.isNotEmpty ? ', ${_name.split(' ').first}' : ''}!',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  hasApplied
                      ? 'Our team will review your application and contact you for an interview. Once hired, you\'ll receive login details to start tasks.'
                      : 'Apply to an opening below to get started. After a short interview, we\'ll issue your login and unlock tasks.',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobsList(Map<String, String> appliedStatus) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('job_postings')
          .where('status', isEqualTo: 'open')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(LucideIcons.briefcase,
                      size: 40, color: AppColors.textLight),
                  SizedBox(height: 12),
                  Text('No openings right now. Please check back soon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final d = docs[i];
                final m = d.data() as Map<String, dynamic>;
                return _jobCard(d.id, m, appliedStatus[d.id]);
              },
              childCount: docs.length,
            ),
          ),
        );
      },
    );
  }

  Widget _jobCard(String jobId, Map<String, dynamic> m, String? appliedState) {
    final title = (m['title'] ?? 'Opening').toString();
    final location = (m['location'] ?? '').toString();
    final payNote = (m['payNote'] ?? '').toString();
    final description = (m['description'] ?? '').toString();
    final applying = _applying.contains(jobId);
    final applied = appliedState != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            if (location.isNotEmpty)
              _meta(LucideIcons.mapPin, location),
            if (payNote.isNotEmpty) _meta(LucideIcons.wallet, payNote),
          ]),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(description,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: applied
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    child: Text(
                      'Applied · ${_statusLabel(appliedState)}',
                      style: const TextStyle(
                          color: AppColors.success, fontWeight: FontWeight.w600),
                    ),
                  )
                : ElevatedButton(
                    onPressed: applying ? null : () => _apply(jobId, title),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd)),
                    ),
                    child: applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Apply',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ],
      );

  String _statusLabel(String? s) {
    switch (s) {
      case 'interviewing':
        return 'Interviewing';
      case 'hired':
        return 'Hired';
      case 'rejected':
        return 'Not selected';
      default:
        return 'Under review';
    }
  }
}
