import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';

class SelectedJob {
  const SelectedJob({required this.id, required this.title});

  final String id;
  final String title;
}

Future<SelectedJob?> showJobBannerPopup(BuildContext context) {
  return showDialog<SelectedJob>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _JobBannerPopup(),
  );
}

class _JobBannerPopup extends StatefulWidget {
  const _JobBannerPopup();

  @override
  State<_JobBannerPopup> createState() => _JobBannerPopupState();
}

class _JobBannerPopupState extends State<_JobBannerPopup> {
  static const _autoScrollInterval = Duration(seconds: 5);

  final PageController _pageController = PageController();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _openings;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  int _jobCount = 0;
  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    _openings = _watchOpenings();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchOpenings() =>
      FirebaseFirestore.instance
          .collection('job_postings')
          .where('status', isEqualTo: 'open')
          .snapshots();

  void _syncAutoScroll(int jobCount) {
    _jobCount = jobCount;
    if (jobCount <= 1 || _userInteracting) {
      _autoScrollTimer?.cancel();
      return;
    }
    if (_autoScrollTimer?.isActive == true) return;
    _autoScrollTimer = Timer.periodic(_autoScrollInterval, (_) {
      if (!mounted || _userInteracting || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % _jobCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseAutoScroll() {
    _userInteracting = true;
    _autoScrollTimer?.cancel();
  }

  void _resumeAutoScroll() {
    _userInteracting = false;
    _syncAutoScroll(_jobCount);
  }

  void _retry() {
    _autoScrollTimer?.cancel();
    _jobCount = 0;
    _currentPage = 0;
    setState(() => _openings = _watchOpenings());
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: media.size.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryDark,
                    colors.primary,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.briefcase,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Join the Sherize team',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Explore our latest openings',
                          style: TextStyle(
                            color: Color(0xD9FFFFFF),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close job openings',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _openings,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    _syncAutoScroll(0);
                    return const _StatusContent(
                      icon: LucideIcons.loader,
                      title: 'Finding open positions...',
                      showProgress: true,
                    );
                  }
                  if (snapshot.hasError) {
                    _syncAutoScroll(0);
                    return _StatusContent(
                      icon: LucideIcons.wifiOff,
                      title: 'Unable to load openings',
                      message: 'You can continue to login or try again.',
                      actionLabel: 'Retry',
                      onAction: _retry,
                    );
                  }

                  final jobs = snapshot.data?.docs ?? [];
                  if (jobs.isEmpty) {
                    _syncAutoScroll(0);
                    return const _StatusContent(
                      icon: LucideIcons.briefcase,
                      title: 'No open positions right now',
                      message: 'Please check back again soon.',
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _syncAutoScroll(jobs.length);
                  });

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Listener(
                            onPointerDown: (_) => _pauseAutoScroll(),
                            onPointerUp: (_) => _resumeAutoScroll(),
                            onPointerCancel: (_) => _resumeAutoScroll(),
                            child: SizedBox(
                              height: 310,
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: jobs.length,
                                onPageChanged: (page) =>
                                    setState(() => _currentPage = page),
                                itemBuilder: (context, index) {
                                  final job = jobs[index];
                                  return _JobBannerCard(
                                    data: job.data(),
                                    onApply: () {
                                      final title =
                                          (job.data()['title'] ?? 'Opening')
                                              .toString();
                                      Navigator.of(context).pop(SelectedJob(
                                        id: job.id,
                                        title: title,
                                      ));
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        if (jobs.length > 1) ...[
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(jobs.length, (index) {
                                final selected = index == _currentPage;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  width: selected ? 20 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? colors.primary
                                        : colors.outlineVariant,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobBannerCard extends StatelessWidget {
  const _JobBannerCard({required this.data, required this.onApply});

  final Map<String, dynamic> data;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = (data['title'] ?? 'Opening').toString();
    final location = (data['location'] ?? '').toString();
    final payNote = (data['payNote'] ?? '').toString();
    final description = (data['description'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (location.isNotEmpty || payNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (location.isNotEmpty)
                  _JobMeta(icon: LucideIcons.mapPin, text: location),
                if (payNote.isNotEmpty)
                  _JobMeta(icon: LucideIcons.wallet, text: payNote),
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(LucideIcons.arrowUpRight, size: 18),
              label: const Text('Apply now'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                backgroundColor: theme.brightness == Brightness.light
                    ? AppColors.primaryDark
                    : colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobMeta extends StatelessWidget {
  const _JobMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.primary),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.icon,
    required this.title,
    this.message,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showProgress)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, size: 34, color: colors.primary),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 7),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.refreshCw, size: 17),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
