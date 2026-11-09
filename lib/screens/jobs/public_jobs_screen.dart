import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
 
/// PUBLIC landing screen — the first thing every visitor sees.
///
/// No OTP, no phone number, no email verification. Anyone can browse open job
/// openings and apply. Hired workers tap "Login" and sign in with the email +
/// password issued by the super admin.
class PublicJobsScreen extends StatefulWidget {
  const PublicJobsScreen({super.key, this.firestore});
 
  final FirebaseFirestore? firestore;
 
  @override
  State<PublicJobsScreen> createState() => _PublicJobsScreenState();
}
 
class _PublicJobsScreenState extends State<PublicJobsScreen> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _openings;
 
  @override
  void initState() {
    super.initState();
    _openings = _watchOpenings();
  }
 
  Stream<QuerySnapshot<Map<String, dynamic>>> _watchOpenings() =>
      (widget.firestore ?? FirebaseFirestore.instance)
          .collection('job_postings')
          .where('status', isEqualTo: 'open')
          .snapshots();
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                border:
                    Border(bottom: BorderSide(color: colors.outlineVariant)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Row(
                    children: [
                      ClipRect(
                        child: Align(
                          widthFactor: 0.5,
                          heightFactor: 0.5,
                          alignment: const Alignment(-0.1, -0.4),
                          child: Image.asset(
                            'assets/images/sherize_logo.png',
                            width: 104,
                            height: 104,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Sherize',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0)),
                            ),
                            const SizedBox(height: 2),
                            Text('Job Portal',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    letterSpacing: 0)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRoutes.login),
                        icon: const Icon(LucideIcons.logIn, size: 18),
                        label: const Text('Login'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          foregroundColor: colors.onSurface,
                          side: BorderSide(color: colors.outlineVariant),
                          textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
 
            // ── Content ─────────────────────────────────────────────
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _openings,
                    builder: (context, snapshot) {
                      final waiting =
                          snapshot.connectionState == ConnectionState.waiting;
                      final docs = snapshot.data?.docs ?? [];
                      final showJobs =
                          !waiting && !snapshot.hasError && docs.isNotEmpty;
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                        itemCount: showJobs ? docs.length + 1 : 2,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Open positions',
                                            style: theme
                                                .textTheme.headlineSmall
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0)),
                                        const SizedBox(height: 6),
                                        Text(
                                          waiting || snapshot.hasError
                                              ? 'Careers at Sherize'
                                              : '${docs.length} ${docs.length == 1 ? 'role' : 'roles'} available',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                  letterSpacing: 0),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (showJobs) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: colors.primaryContainer,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${docs.length}',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    colors.onPrimaryContainer,
                                                letterSpacing: 0),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }
                          if (showJobs) {
                            return _JobCard(
                                jobId: docs[index - 1].id,
                                data: docs[index - 1].data());
                          }
                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 40),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Column(
                              children: [
                                if (waiting)
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                else
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                        snapshot.hasError
                                            ? LucideIcons.wifiOff
                                            : LucideIcons.briefcase,
                                        size: 28,
                                        color: colors.onPrimaryContainer),
                                  ),
                                const SizedBox(height: 20),
                                Text(
                                  waiting
                                      ? 'Loading openings...'
                                      : snapshot.hasError
                                          ? 'Unable to load openings'
                                          : 'No open positions right now',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0),
                                ),
                                if (!waiting) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    snapshot.hasError
                                        ? 'Check your connection and try again.'
                                        : 'Please check back for new opportunities.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        height: 1.4,
                                        letterSpacing: 0),
                                  ),
                                  if (snapshot.hasError) ...[
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: () => setState(
                                          () => _openings = _watchOpenings()),
                                      icon: const Icon(LucideIcons.refreshCw,
                                          size: 18),
                                      label: const Text('Retry'),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _JobCard extends StatelessWidget {
  final String jobId;
  final Map<String, dynamic> data;
  const _JobCard({required this.jobId, required this.data});
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = (data['title'] ?? 'Opening').toString();
    final location = (data['location'] ?? '').toString();
    final payNote = (data['payNote'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
 
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md + 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(LucideIcons.briefcase,
                    size: 22, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        letterSpacing: 0)),
              ),
            ],
          ),
          if (location.isNotEmpty || payNote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (location.isNotEmpty)
                  _meta(context, LucideIcons.mapPin, location),
                if (payNote.isNotEmpty)
                  _meta(context, LucideIcons.wallet, payNote),
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(description,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.55,
                    letterSpacing: 0)),
          ],
          const SizedBox(height: 18),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openApplySheet(context, jobId, title),
              icon: const Icon(LucideIcons.arrowUpRight, size: 18),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                backgroundColor: theme.brightness == Brightness.light
                    ? AppColors.primaryDark
                    : colors.primary,
                foregroundColor: colors.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              label: const Text('Apply now'),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _meta(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    letterSpacing: 0)),
          ),
        ],
      ),
    );
  }
 
  void _openApplySheet(BuildContext context, String jobId, String jobTitle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ApplySheet(jobId: jobId, jobTitle: jobTitle),
    );
  }
}
 
class _ApplySheet extends StatefulWidget {
  final String jobId;
  final String jobTitle;
  const _ApplySheet({required this.jobId, required this.jobTitle});
 
  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}
 
class _ApplySheetState extends State<_ApplySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _submitting = false;
 
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }
 
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('submitPublicApplication')
          .call({
        'jobId': widget.jobId,
        'jobTitle': widget.jobTitle,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      SnackBarUtils.showSuccess(
          'Application submitted! Our team will contact you for an interview.');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        SnackBarUtils.showError(e.message ?? 'Could not apply. Try again.');
      }
    } catch (e) {
      if (mounted) SnackBarUtils.showError('Could not apply. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
 
  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
      );
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(LucideIcons.send,
                          size: 20, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Apply',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  letterSpacing: 0)),
                          const SizedBox(height: 2),
                          Text(widget.jobTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec('Full name', LucideIcons.user),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('10-digit mobile number', LucideIcons.phone)
                      .copyWith(counterText: ''),
                  validator: (v) =>
                      (v == null || !RegExp(r'^[6-9]\d{9}$').hasMatch(v.trim()))
                          ? 'Enter a valid 10-digit number'
                          : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('Email (optional)', LucideIcons.mail),
                  validator: (v) =>
                      (v != null && v.trim().isNotEmpty && !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    elevation: 0,
                    backgroundColor: theme.brightness == Brightness.light
                        ? AppColors.primaryDark
                        : colors.primary,
                    foregroundColor: colors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Application',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}