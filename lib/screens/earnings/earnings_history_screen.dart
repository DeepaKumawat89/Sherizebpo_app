import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';

/// Full earnings history screen with filters, pagination and summary.
class EarningsHistoryScreen extends StatefulWidget {
  const EarningsHistoryScreen({Key? key}) : super(key: key);

  @override
  State<EarningsHistoryScreen> createState() => _EarningsHistoryScreenState();
}

class _EarningsHistoryScreenState extends State<EarningsHistoryScreen> {
  static const int _pageSize = 20;

  final _user = FirebaseAuth.instance.currentUser;
  final _db = FirebaseFirestore.instance;
  final _scrollController = ScrollController();

  String _filter = 'all'; // 'all' | 'credit' | 'debit'
  List<DocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // Wallet summary
  double _totalEarned = 0;
  double _balance = 0;

  StreamSubscription<DocumentSnapshot>? _walletSub;

  @override
  void initState() {
    super.initState();
    _listenToWallet();
    _fetchTransactions(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _walletSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _fetchTransactions(reset: false);
    }
  }

  void _listenToWallet() {
    if (_user == null) return;
    _walletSub = _db.collection('worker_wallets').doc(_user!.uid).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() as Map<String, dynamic>;
        setState(() {
          _totalEarned = (data['balance'] ?? 0.0).toDouble();
          _balance = (data['balance'] ?? 0.0).toDouble();
        });
        debugPrint('Wallet balance: $_balance');
      }
    });
  }

  Future<void> _fetchTransactions({required bool reset}) async {
    if (_user == null) return;
    if (!reset && _isLoadingMore) return;

    setState(() {
      if (reset) {
        _isLoading = true;
        _docs = [];
        _lastDoc = null;
        _hasMore = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      Query q = _db
          .collection('transactions')
          .where('userId', isEqualTo: _user!.uid);

      if (_filter != 'all') {
        q = q.where('type', isEqualTo: _filter);
      }

      q = q.orderBy('createdAt', descending: true).limit(_pageSize);

      if (!reset && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snap = await q.get();
      debugPrint('Transactions count: ${snap.docs.length}');

      setState(() {
        _docs.addAll(snap.docs);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == _pageSize;
      });
    } catch (e) {
      debugPrint('Failed to fetch transactions: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onFilterChanged(String newFilter) {
    if (newFilter == _filter) return;
    setState(() => _filter = newFilter);
    _fetchTransactions(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Earnings History'),
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: Column(
        children: [
          // ─── Summary Header ───────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPaddingH,
              AppSizes.sm,
              AppSizes.screenPaddingH,
              AppSizes.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    icon: LucideIcons.trendingUp,
                    iconColor: AppColors.success,
                    label: 'Total Earned',
                    value: '₹${_totalEarned.toStringAsFixed(2)}',
                    valueColor: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: _SummaryCard(
                    icon: LucideIcons.wallet,
                    iconColor: AppColors.primary,
                    label: 'Balance',
                    value: '₹${_balance.toStringAsFixed(2)}',
                    valueColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          // ─── Filter Chips ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPaddingH,
            ),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _filter == 'all',
                  onTap: () => _onFilterChanged('all'),
                ),
                const SizedBox(width: AppSizes.sm),
                _FilterChip(
                  label: 'Credits',
                  isSelected: _filter == 'credit',
                  onTap: () => _onFilterChanged('credit'),
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSizes.sm),
                _FilterChip(
                  label: 'Debits',
                  isSelected: _filter == 'debit',
                  onTap: () => _onFilterChanged('debit'),
                  color: AppColors.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),

          // ─── Transaction List ─────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  )
                : _docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.inbox,
                              size: 48,
                              color: AppColors.border,
                            ),
                            const SizedBox(height: AppSizes.md),
                            const Text(
                              'No transactions found',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: AppSizes.xs),
                            Text(
                              _filter != 'all'
                                  ? 'Try changing the filter.'
                                  : 'Complete tasks to start earning.',
                              style: const TextStyle(
                                color: AppColors.textPlaceholder,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(
                          left: AppSizes.screenPaddingH,
                          right: AppSizes.screenPaddingH,
                          bottom: AppSizes.xxxl,
                        ),
                        itemCount: _docs.length + (_isLoadingMore ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSizes.sm),
                        itemBuilder: (context, index) {
                          if (index == _docs.length) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSizes.lg),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }

                          final data =
                              _docs[index].data() as Map<String, dynamic>;

                          DateTime dt = DateTime.now();
                          if (data['createdAt'] is Timestamp) {
                            dt = (data['createdAt'] as Timestamp).toDate();
                          } else if (data['createdAt'] is String) {
                            dt = DateTime.tryParse(data['createdAt']) ?? dt;
                          }

                          final type = data['type'] ?? 'credit';
                          final isCredit = (type == 'credit');
                          final amount = (data['amount'] ?? 0.0).toDouble();
                          final status = data['status'] ?? 'success';
                          final source = data['source'] ?? '';
                          final description = data['description'] ?? '';

                          String title = description;
                          if (title.isEmpty) {
                            switch (source) {
                              case 'task':
                              case 'task_reward':
                                title = 'Task Earnings';
                                break;
                              case 'payout':
                              case 'withdrawal':
                                title = 'Withdrawal';
                                break;
                              default:
                                title = 'Transaction';
                            }
                          }

                          return _TransactionCard(
                            title: title,
                            description: description,
                            date: DateFormat('dd MMM yyyy, hh:mm a').format(dt),
                            amount: amount,
                            isCredit: isCredit,
                            status: status,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Card Widget ──────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: AppDecorations.cardElevated,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: AppDecorations.iconBox(color: iconColor),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter Chip Widget ───────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusRound),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
          ),
          boxShadow: isSelected ? AppDecorations.shadowSm : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Transaction Card Widget ──────────────────────────────────
class _TransactionCard extends StatelessWidget {
  final String title;
  final String description;
  final String date;
  final double amount;
  final bool isCredit;
  final String status;

  const _TransactionCard({
    required this.title,
    required this.description,
    required this.date,
    required this.amount,
    required this.isCredit,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isFailed = status == 'failed';
    final amountColor = isFailed
        ? AppColors.textMuted
        : (isCredit ? AppColors.success : AppColors.error);

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: AppDecorations.cardElevated,
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCredit
                  ? AppColors.success.withValues(alpha: 0.08)
                  : AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(
              isCredit ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
              color: isCredit ? AppColors.success : AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSizes.md),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _statusBadge(),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textPlaceholder,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Amount
          const SizedBox(width: AppSizes.sm),
          Text(
            '${isCredit ? '+' : '-'}₹${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              decoration: isFailed ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (status) {
      case 'pending':
        bgColor = AppColors.warningBg;
        textColor = AppColors.warning;
        label = 'Pending';
        icon = LucideIcons.clock;
        break;
      case 'failed':
        bgColor = AppColors.errorBg;
        textColor = AppColors.error;
        label = 'Failed';
        icon = LucideIcons.xCircle;
        break;
      default:
        bgColor = AppColors.successBg;
        textColor = AppColors.success;
        label = 'Success';
        icon = LucideIcons.checkCircle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
