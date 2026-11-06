import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/profile_completion.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../routes.dart';
import '../../services/platform_settings_service.dart';
import '../../widgets/custom_button.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({Key? key}) : super(key: key);

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final user = FirebaseAuth.instance.currentUser;

  // Pagination & Filtering
  String _selectedFilter = 'All'; // All, Credits, Debits
  List<DocumentSnapshot> _transactions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastVisible;
  final int _limit = 20;

  final ScrollController _scrollController = ScrollController();

  // Summary Data
  double _totalEarnings = 0;
  double _todayEarnings = 0;
  double _pendingEarnings = 0;
  double _walletBalance = 0;
  String _kycStatus = 'unverified';
  bool _profileComplete = false;
  List<String> _profileMissing = const [];
  bool _isWithdrawing = false;

  StreamSubscription? _walletSub;
  StreamSubscription? _userSub;

  @override
  void initState() {
    super.initState();
    if (user != null) {
      _listenToData();
      _fetchTodayAndPending();
      _fetchTransactions();
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _walletSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _fetchTransactions(fetchMore: true);
    }
  }

  void _listenToData() {
    _walletSub = FirebaseFirestore.instance
        .collection('worker_wallets')
        .doc(user!.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _walletBalance = (doc.data()?['balance'] ?? 0.0).toDouble();
          _totalEarnings = (doc.data()?['totalEarned'] ?? 0.0).toDouble();
        });
        debugPrint('Wallet balance: $_walletBalance');
      }
    });

    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data() ?? {};
        setState(() {
          _kycStatus =
              data['kyc_status'] ?? data['kycStatus'] ?? 'unverified';
          _profileComplete = ProfileCompletion.isComplete(data);
          _profileMissing = ProfileCompletion.missing(data);
        });
      }
    });
  }

  Future<void> _fetchTodayAndPending() async {
    if (user == null) return;
    
    // 1. Fetch Pending Earnings
    try {
      final pendingSnap = await FirebaseFirestore.instance
          .collection('task_submissions')
          .where('userId', isEqualTo: user!.uid)
          .where('status', whereIn: ['pending_admin_review', 'pending_payment'])
          .get();

      double pending = 0;
      for (var d in pendingSnap.docs) {
        pending += (d.data()['payout'] ?? 0.0).toDouble();
      }
      
      if (mounted) {
        setState(() {
          _pendingEarnings = pending;
        });
      }
    } catch (e) {
      debugPrint('Error fetching pending: $e');
    }

    // 2. Fetch Today Earnings
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final todaySnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user!.uid)
          .where('type', isEqualTo: 'credit')
          .orderBy('createdAt', descending: true) // Match existing index
          .where('createdAt', isGreaterThanOrEqualTo: startOfToday)
          .get();

      double today = 0;
      for (var d in todaySnap.docs) {
        if (d.data()['status'] != 'failed') {
          today += (d.data()['amount'] ?? 0.0).toDouble();
        }
      }

      if (mounted) {
        setState(() {
          _todayEarnings = today;
        });
      }
    } catch (e) {
      debugPrint('Error fetching today: $e');
    }
  }

  Future<void> _fetchTransactions({bool fetchMore = false}) async {
    if (_isLoading || (!_hasMore && fetchMore) || user == null) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user!.uid)
          .orderBy('createdAt', descending: true);

      if (_selectedFilter == 'Credits') {
        query = query.where('type', isEqualTo: 'credit');
      } else if (_selectedFilter == 'Debits') {
        query = query.where('type', isEqualTo: 'debit');
      }

      query = query.limit(_limit);

      if (fetchMore && _lastVisible != null) {
        query = query.startAfterDocument(_lastVisible!);
      }

      final snapshot = await query.get();
      debugPrint('Transactions count: ${snapshot.docs.length}');

      if (mounted) {
        setState(() {
          if (fetchMore) {
            _transactions.addAll(snapshot.docs);
          } else {
            _transactions = snapshot.docs;
          }

          _hasMore = snapshot.docs.length == _limit;
          if (snapshot.docs.isNotEmpty) {
            _lastVisible = snapshot.docs.last;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setFilter(String filter) {
    if (_selectedFilter == filter) return;
    setState(() {
      _selectedFilter = filter;
      _lastVisible = null;
      _hasMore = true;
      _transactions.clear();
    });
    _fetchTransactions();
  }

  void _showWithdrawalSheet() {
    if (user == null) return;
    if (!_profileComplete) {
      _showProfileIncompleteDialog();
      return;
    }
    final minWithdrawal = context.read<PlatformSettingsService>().minWithdrawalAmount;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WithdrawalSheet(
        maxAmount: _walletBalance,
        minAmount: minWithdrawal,
        onSubmit: (amount, method, details) {
          Navigator.pop(context);
          _processWithdrawal(amount, method, details);
        },
      ),
    );
  }

  void _showProfileIncompleteDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.userCog,
                      size: 30, color: AppColors.warning),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                'Complete Your Profile',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Withdrawals require a 100% complete profile. Please add the missing details below.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white54 : AppColors.textMuted,
                      height: 1.5,
                    ),
              ),
              if (_profileMissing.isNotEmpty) ...[
                const SizedBox(height: AppSizes.lg),
                Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _profileMissing
                        .map((m) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.circle,
                                      size: 8, color: AppColors.warning),
                                  const SizedBox(width: AppSizes.sm),
                                  Text(
                                    m,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.textBody,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                      ),
                      child: const Text('Later',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.pushNamed(context, AppRoutes.editProfile);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusMd),
                        ),
                      ),
                      child: const Text('Complete',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processWithdrawal(double amount, String method, String details) async {
    setState(() => _isWithdrawing = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('requestWithdrawal');
      final result = await callable.call<Map<String, dynamic>>({
        'amount': amount,
        'paymentMethod': method,
        'paymentDetails': details,
      });

      if (!mounted) return;
      final message = (result.data as Map<String, dynamic>?)?['message'] ?? 'Withdrawal requested';
      SnackBarUtils.showSuccess(message);
      // Refresh transactions to show the pending one
      _lastVisible = null;
      _hasMore = true;
      _fetchTransactions();
      _fetchTodayAndPending(); // Also update balances

    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(e.message ?? 'Withdrawal failed');
    } catch (e) {
      if (!mounted) return;
      // Provide a more user-friendly error if unauthenticated or network fails
      SnackBarUtils.showError('Failed to initiate withdrawal. Please log in again or check your connection.');
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  Widget _buildEarningsDisabledScaffold(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.wallet,
                  size: 48,
                  color: isDark ? Colors.white38 : AppColors.textMuted),
              const SizedBox(height: AppSizes.lg),
              Text(
                'Not available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'This section is currently disabled. Please check back later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white54 : AppColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'User not logged in.',
            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
          ),
        ),
      );
    }

    final platformSettings = context.watch<PlatformSettingsService>();
    // Defense in depth: even if this screen is reached via a deep link while
    // the earnings system is disabled, never render balances or amounts.
    if (!platformSettings.earningsSystemEnabled) {
      return _buildEarningsDisabledScaffold(context);
    }

    final double minWithdrawal = platformSettings.minWithdrawalAmount;
    final bool canWithdraw = _walletBalance >= minWithdrawal &&
        _kycStatus.toLowerCase() == 'approved';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Payment Dashboard'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : AppColors.textDark,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textDark),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _fetchTodayAndPending();
          _lastVisible = null;
          _hasMore = true;
          await _fetchTransactions();
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Phase 1: Dashboard Header ──
              Padding(
                padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                child: Column(
                  children: [
                    // Highlight Zero Platform Fee
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSizes.md),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.sm, vertical: AppSizes.xs),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: isDark ? 0.5 : 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.checkCircle,
                              color: isDark ? Colors.greenAccent : AppColors.success, size: 14),
                          const SizedBox(width: AppSizes.xs),
                          Flexible(
                            child: Text(
                              '0% Platform Fee - Keep 100% of your earnings!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.greenAccent : AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Top 2 Big Cards
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Withdrawable Balance',
                            amount: _walletBalance,
                            icon: LucideIcons.wallet,
                            isPrimary: true,
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Total Earnings',
                            amount: _totalEarnings,
                            icon: LucideIcons.barChart2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    // Bottom 2 Small Cards
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            title: 'Today Earnings',
                            amount: _todayEarnings,
                            icon: LucideIcons.calendar,
                            isSmall: true,
                          ),
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: _SummaryCard(
                            title: 'Pending Earnings',
                            amount: _pendingEarnings,
                            icon: LucideIcons.clock,
                            isSmall: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.xl),
                    
                    // ── KYC Gate Banner ──
                    if (_kycStatus.toLowerCase() != 'approved') ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: AppSizes.md),
                        padding: const EdgeInsets.all(AppSizes.md),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.error.withValues(alpha: 0.2) : AppColors.errorBg,
                          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(LucideIcons.shieldAlert,
                                color: isDark ? Colors.redAccent : AppColors.error, size: 20),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'KYC Verification Required',
                                    style: TextStyle(
                                      color: isDark ? Colors.redAccent : AppColors.error,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Please complete KYC to enable withdrawals',
                                    style: TextStyle(
                                      color: isDark ? Colors.redAccent : AppColors.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.sm),
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, '/profile/kyc'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppSizes.md,
                                          vertical: AppSizes.xs),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.redAccent.shade400 : AppColors.error,
                                        borderRadius: BorderRadius.circular(
                                            AppSizes.radiusSm),
                                      ),
                                      child: const Text(
                                        'Complete KYC →',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Withdraw Button ──
                    CustomButton(
                      label: _isWithdrawing ? 'Processing...' : 'Withdraw Earnings',
                      icon: LucideIcons.banknote,
                      height: 56,
                      isLoading: _isWithdrawing,
                      isDisabled: !canWithdraw || _isWithdrawing,
                      onPressed: canWithdraw ? _showWithdrawalSheet : null,
                    ),
                    if (canWithdraw || _kycStatus.toLowerCase() == 'approved')
                      if (_walletBalance < minWithdrawal)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSizes.sm),
                          child: Text(
                            'Minimum withdrawal amount is ₹${minWithdrawal.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSizes.md),

              // ── Phase 6: Filters ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
                child: Row(
                  children: [
                    Text(
                      'Transaction History',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.border.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: ['All', 'Credits', 'Debits'].map((filter) {
                          final isSelected = _selectedFilter == filter;
                          return GestureDetector(
                            onTap: () => _setFilter(filter),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? (isDark ? AppColors.secondaryLight : Colors.white) 
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: isSelected && !isDark
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                filter,
                                style: TextStyle(
                                  color: isSelected
                                      ? (isDark ? Colors.white : AppColors.textDark)
                                      : (isDark ? Colors.white54 : AppColors.textMuted),
                                  fontSize: 13,
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.md),

              // ── Phase 4 & 8: Transaction List UI (Paginated) ──
              if (_transactions.isEmpty && !_isLoading)
                // ── Phase 7: Empty State ──
                Padding(
                  padding: const EdgeInsets.all(AppSizes.xxxl),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(LucideIcons.history,
                            size: 48, color: AppColors.border),
                        const SizedBox(height: AppSizes.md),
                        Text(
                          'No transactions found',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : AppColors.textMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSizes.xs),
                        Text(
                          'Start completing tasks to earn money',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : AppColors.textPlaceholder,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(
                    left: AppSizes.screenPaddingH,
                    right: AppSizes.screenPaddingH,
                    bottom: AppSizes.xxxl,
                  ),
                  itemCount: _transactions.length + (_isLoading ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSizes.sm),
                  itemBuilder: (context, index) {
                    if (index == _transactions.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSizes.lg),
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2.5,
                          ),
                        ),
                      );
                    }

                    final data =
                        _transactions[index].data() as Map<String, dynamic>;

                    DateTime dt = DateTime.now();
                    if (data['createdAt'] is Timestamp) {
                      dt = (data['createdAt'] as Timestamp).toDate();
                    } else if (data['createdAt'] is String) {
                      dt = DateTime.tryParse(data['createdAt']) ?? dt;
                    }

                    final amount = (data['amount'] ?? 0.0).toDouble();
                    final type = data['type'] ?? 'credit';
                    final description = data['description'] ?? '';
                    final status = data['status'] ?? 'success';

                    String title = description;
                    if (title.isEmpty) {
                      if (data['source'] == 'task') title = 'Task Approved';
                      if (data['source'] == 'payout' || data['source'] == 'withdrawal') title = 'Withdrawal';
                      if (title.isEmpty) title = 'Transaction';
                    }

                    return _TransactionTile(
                      title: title,
                      date: DateFormat('MMM dd, yyyy • hh:mm a').format(dt),
                      amount: amount,
                      isCredit: type == 'credit',
                      status: status,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final bool isPrimary;
  final bool isSmall;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    this.isPrimary = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isPrimary) {
      return Container(
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: AppDecorations.primaryGradientCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.white70),
                const SizedBox(width: AppSizes.xs),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(isSmall ? AppSizes.md : AppSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: isDark ? Colors.white12 : AppColors.border.withValues(alpha: 0.5),
        ),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark 
                      ? AppColors.primary.withValues(alpha: 0.2) 
                      : AppColors.primaryLight.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: isDark ? AppColors.primaryLight : AppColors.primary),
              ),
              const SizedBox(width: AppSizes.xs),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: isSmall ? AppSizes.sm : AppSizes.md),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.textDark,
              fontSize: isSmall ? 20 : 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Phase 4 & 5: Premium transaction tile with status badges and amount formatting.
class _TransactionTile extends StatelessWidget {
  final String title;
  final String date;
  final double amount;
  final bool isCredit;
  final String status;

  const _TransactionTile({
    required this.title,
    required this.date,
    required this.amount,
    required this.isCredit,
    this.status = 'success',
  });

  @override
  Widget build(BuildContext context) {
    final bool isFailed = status == 'failed';
    final bool isPending = status == 'pending';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: isDark ? Colors.white12 : AppColors.border.withValues(alpha: 0.5),
        ),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Row(
        children: [
          // Icon Box -> Color Coding (Credit -> Green, Debit -> Red)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCredit
                  ? AppColors.success.withValues(alpha: isDark ? 0.2 : 0.1)
                  : AppColors.error.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Icon(
              isCredit ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
              color: isCredit 
                  ? (isDark ? Colors.greenAccent : AppColors.success) 
                  : (isDark ? Colors.redAccent : AppColors.error),
              size: 20,
            ),
          ),
          const SizedBox(width: AppSizes.md),

          // Details column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : AppColors.textMuted,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isFailed || isPending) ...[
                      const SizedBox(width: AppSizes.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isFailed
                              ? AppColors.error.withValues(alpha: 0.1)
                              : AppColors.warningBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isFailed ? 'Failed' : 'Pending',
                          style: TextStyle(
                            color: isFailed
                                ? AppColors.error
                                : AppColors.warningDark,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Amount -> +₹20 or -₹500
          const SizedBox(width: AppSizes.sm),
          Text(
            '${isCredit ? '+' : '-'}₹${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: isFailed
                  ? (isDark ? Colors.white38 : AppColors.textMuted)
                  : (isCredit 
                      ? (isDark ? Colors.greenAccent : AppColors.success) 
                      : (isDark ? Colors.redAccent : AppColors.error)),
              fontWeight: FontWeight.w800,
              fontSize: 16,
              decoration: isFailed ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawalSheet extends StatefulWidget {
  final double maxAmount;
  final double minAmount;
  final Function(double amount, String method, String details) onSubmit;

  const _WithdrawalSheet({
    required this.maxAmount,
    required this.minAmount,
    required this.onSubmit,
  });

  @override
  State<_WithdrawalSheet> createState() => _WithdrawalSheetState();
}

class _WithdrawalSheetState extends State<_WithdrawalSheet> {
  final _amountController = TextEditingController();
  final _detailsController = TextEditingController();
  String _selectedMethod = 'upi';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.maxAmount.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    final amountText = _amountController.text.trim();
    final detailsText = _detailsController.text.trim();
    
    if (amountText.isEmpty) {
      setState(() => _errorText = 'Please enter amount');
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _errorText = 'Please enter a valid amount');
      return;
    }
    
    if (amount > widget.maxAmount) {
      setState(() => _errorText = 'Amount exceeds your withdrawable balance');
      return;
    }
    if (amount < widget.minAmount) {
      setState(() => _errorText = 'Minimum withdrawal is ₹${widget.minAmount.toStringAsFixed(0)}');
      return;
    }

    if (detailsText.isEmpty) {
      setState(() => _errorText = _selectedMethod == 'upi' ? 'Please enter your UPI ID' : 'Please enter Bank Account & IFSC');
      return;
    }

    widget.onSubmit(amount, _selectedMethod, detailsText);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.only(
        top: 24,
        left: AppSizes.screenPaddingH,
        right: AppSizes.screenPaddingH,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Withdraw Earnings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Text(
            'Withdrawable Balance: ₹${widget.maxAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              labelStyle: const TextStyle(color: AppColors.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(LucideIcons.indianRupee, size: 18, color: AppColors.textDark),
            ),
          ),
          const SizedBox(height: 16),
          
          const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 14)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _selectedMethod,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedMethod = value;
                  _detailsController.clear();
                });
              }
            },
            child: const Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('UPI', style: TextStyle(fontSize: 14, color: AppColors.textDark, fontWeight: FontWeight.w500)),
                    value: 'upi',
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: Text('Bank Transfer', style: TextStyle(fontSize: 14, color: AppColors.textDark, fontWeight: FontWeight.w500)),
                    value: 'bank_account',
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _detailsController,
            style: const TextStyle(color: AppColors.textDark, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: _selectedMethod == 'upi' ? 'UPI ID (e.g. 98765@ybl)' : 'A/C Number & IFSC Code',
              labelStyle: const TextStyle(color: AppColors.textMuted),
              hintText: _selectedMethod == 'upi' ? 'name@okhdfcbank' : 'A/C: 1234567890, IFSC: ABCD0123456',
              hintStyle: const TextStyle(color: AppColors.textPlaceholder),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            maxLines: _selectedMethod == 'upi' ? 1 : 2,
          ),
          
          if (_errorText != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorText!,
              style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
          
          const SizedBox(height: 24),
          CustomButton(
            label: 'Confirm Withdraw',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
