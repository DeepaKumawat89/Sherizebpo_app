import 'dart:async';
 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
 
import '../../../core/constants/constants.dart';
import '../../../models/work_session.dart';
import '../../../services/work_session_service.dart';
 
/// Dedicated screen keeps the two live activity streams out of the already
/// complex dashboard scroll tree. This avoids competing layout invalidations
/// while the dashboard's own analytics streams are rebuilding.
class AdminWorkSessionScreen extends StatelessWidget {
  const AdminWorkSessionScreen({super.key, FirebaseFirestore? firestore})
      : _firestore = firestore;
 
  final FirebaseFirestore? _firestore;
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work Sessions'),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: AdminWorkSessionMonitor(firestore: _firestore),
      ),
    );
  }
}
 
enum _Filter { all, working, onBreak, completed, notStarted }
 
extension on _Filter {
  String get label => switch (this) {
        _Filter.all => 'All',
        _Filter.working => 'Working',
        _Filter.onBreak => 'On break',
        _Filter.completed => 'Completed',
        _Filter.notStarted => 'Not started',
      };
 
  bool matches(WorkStatus s) => switch (this) {
        _Filter.all => true,
        _Filter.working => s == WorkStatus.active,
        _Filter.onBreak => s == WorkStatus.onBreak,
        _Filter.completed => s == WorkStatus.ended,
        _Filter.notStarted => s == WorkStatus.idle,
      };
}
 
(String, Color, IconData) _statusStyle(WorkStatus status) => switch (status) {
      WorkStatus.idle => ('Not started', AppColors.textMuted, LucideIcons.moon),
      WorkStatus.active => ('Working', AppColors.info, LucideIcons.zap),
      WorkStatus.onBreak => ('On break', AppColors.warning, LucideIcons.coffee),
      WorkStatus.ended =>
        ('Completed', AppColors.success, LucideIcons.checkCircle2),
    };
 
class AdminWorkSessionMonitor extends StatefulWidget {
  const AdminWorkSessionMonitor({super.key, FirebaseFirestore? firestore})
      : _firestore = firestore;
 
  final FirebaseFirestore? _firestore;
 
  @override
  State<AdminWorkSessionMonitor> createState() =>
      _AdminWorkSessionMonitorState();
}
 
class _AdminWorkSessionMonitorState extends State<AdminWorkSessionMonitor> {
  FirebaseFirestore get _db => widget._firestore ?? FirebaseFirestore.instance;
 
  DateTime _selectedDate = DateTime.now();
  DateTime _now = DateTime.now();
  Timer? _ticker;
  final _searchCtrl = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;
 
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }
 
  @override
  void dispose() {
    _ticker?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }
 
  String get _dateKey => WorkSessionService.todayKey(_selectedDate);
 
  bool get _isToday =>
      WorkSessionService.todayKey(_selectedDate) ==
      WorkSessionService.todayKey(_now);
 
  DateTime get _referenceTime {
    if (_isToday) return _now;
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      23,
      59,
      59,
    );
  }
 
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').snapshots(),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.connectionState == ConnectionState.waiting &&
            !usersSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (usersSnapshot.hasError) {
          return _messageList(
            isDark,
            _stateCard(
              'Unable to load employees',
              'Check your admin permissions and try again.',
              LucideIcons.alertCircle,
              AppColors.error,
            ),
          );
        }
 
        final employees = (usersSnapshot.data?.docs ?? const [])
            .where(_isEmployee)
            .toList()
          ..sort((a, b) => _employeeName(a.data())
              .toLowerCase()
              .compareTo(_employeeName(b.data()).toLowerCase()));
 
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('work_sessions')
              .where('date', isEqualTo: _dateKey)
              .snapshots(),
          builder: (context, sessionsSnapshot) {
            if (sessionsSnapshot.connectionState == ConnectionState.waiting &&
                !sessionsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sessionsSnapshot.hasError) {
              return _messageList(
                isDark,
                _stateCard(
                  'Unable to load sessions',
                  'Something went wrong loading this date.',
                  LucideIcons.alertCircle,
                  AppColors.error,
                ),
              );
            }
 
            final sessions = <String, WorkSession>{};
            for (final doc in sessionsSnapshot.data?.docs ?? const []) {
              try {
                final session = WorkSession.fromDoc(doc);
                sessions[session.userId] = session;
              } catch (_) {
                // Ignore malformed legacy records without taking down the list.
              }
            }
 
            WorkSession sessionFor(String id) =>
                sessions[id] ?? WorkSession.empty(id, _dateKey);
 
            // Summary counts across all employees (unfiltered).
            final counts = <WorkStatus, int>{};
            for (final e in employees) {
              final s = sessionFor(e.id).status;
              counts[s] = (counts[s] ?? 0) + 1;
            }
 
            final q = _query.trim().toLowerCase();
            final visible = employees.where((e) {
              final s = sessionFor(e.id);
              if (!_filter.matches(s.status)) return false;
              if (q.isEmpty) return true;
              return _employeeName(e.data()).toLowerCase().contains(q);
            }).toList();
 
            final hasRows = visible.isNotEmpty;
            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPaddingH,
                AppSizes.sm,
                AppSizes.screenPaddingH,
                32,
              ),
              itemCount: hasRows ? visible.length + 1 : 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _header(isDark, employees.length, counts);
                }
                if (!hasRows) {
                  return employees.isEmpty
                      ? _stateCard(
                          'No employees yet',
                          'Employees will appear here once they are onboarded.',
                          LucideIcons.users,
                          AppColors.textMuted,
                        )
                      : _stateCard(
                          'No matches',
                          'Try a different name or filter.',
                          LucideIcons.searchX,
                          AppColors.textMuted,
                        );
                }
                final employee = visible[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
                  child: _EmployeeSessionCard(
                    name: _employeeName(employee.data()),
                    session: sessionFor(employee.id),
                    workDate: _selectedDate,
                    referenceTime: _referenceTime,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
 
  Widget _messageList(bool isDark, Widget message) => ListView(
        padding: const EdgeInsets.all(AppSizes.screenPaddingH),
        children: [
          _dateStrip(isDark),
          const SizedBox(height: AppSizes.md),
          message,
        ],
      );
 
  // ───────────────────────── Header ─────────────────────────
 
  Widget _header(bool isDark, int total, Map<WorkStatus, int> counts) {
    final working = counts[WorkStatus.active] ?? 0;
    final onBreak = counts[WorkStatus.onBreak] ?? 0;
    final done = counts[WorkStatus.ended] ?? 0;
    final idle = counts[WorkStatus.idle] ?? 0;
 
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dateStrip(isDark),
          const SizedBox(height: AppSizes.md),
          _heroBanner(total, working, onBreak, done, idle),
          const SizedBox(height: AppSizes.md),
          _searchField(isDark),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _Filter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _Filter.values[i];
                final selected = f == _filter;
                final n = switch (f) {
                  _Filter.all => total,
                  _Filter.working => working,
                  _Filter.onBreak => onBreak,
                  _Filter.completed => done,
                  _Filter.notStarted => idle,
                };
                return ChoiceChip(
                  label: Text('${f.label} · $n'),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : (isDark ? Colors.white70 : AppColors.textMuted),
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.primary.withValues(alpha: 0.06),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _dateStrip(bool isDark) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final selectedKey = _dateKey;
    final inStrip = days.any((d) => WorkSessionService.todayKey(d) == selectedKey);
 
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = days[days.length - 1 - i];
                final selected = WorkSessionService.todayKey(d) == selectedKey;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: selected
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.75),
                              ],
                            )
                          : null,
                      color: selected
                          ? null
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Theme.of(context).cardColor),
                      border: selected
                          ? null
                          : Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : AppColors.border,
                            ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.30),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(d).toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white70 : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: !inStrip
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickDate,
            child: SizedBox(
              width: 52,
              height: 66,
              child: Icon(
                LucideIcons.calendarDays,
                size: 22,
                color: !inStrip ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
 
  Widget _heroBanner(int total, int working, int onBreak, int done, int idle) {
    final started = total - idle;
    final pct = total == 0 ? 0.0 : started / total;
 
    Widget stat(String label, int value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 24,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
 
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            Color.lerp(AppColors.primary, Colors.black, 0.35)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isToday
                          ? 'Today'
                          : DateFormat('EEEE').format(_selectedDate),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd MMMM yyyy').format(_selectedDate),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isToday)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.radio, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              stat('Working', working, const Color(0xFF7DD3FC)),
              stat('On break', onBreak, const Color(0xFFFCD34D)),
              stat('Done', done, const Color(0xFF86EFAC)),
              stat('Away', idle, Colors.white54),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$started of $total employees have started their day',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
 
  Widget _searchField(bool isDark) => TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search employees',
          hintStyle: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white38 : AppColors.textMuted,
          ),
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Theme.of(context).cardColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
          ),
        ),
      );
 
  // ───────────────────────── Data helpers ─────────────────────────
 
  bool _isEmployee(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if ((data['onboardingStatus'] ?? '').toString() == 'applicant') return false;
    final roles = <String>{
      (data['role'] ?? 'worker').toString().toLowerCase(),
      if (data['roles'] is List)
        ...(data['roles'] as List).map((role) => role.toString().toLowerCase()),
    };
    const nonEmployeeRoles = {
      'admin',
      'super_admin',
      'task_review_admin',
      'kyc_admin',
      'payment_admin',
      'support_admin',
      'developer',
      'client',
    };
    return !roles.any(nonEmployeeRoles.contains);
  }
 
  String _employeeName(Map<String, dynamic> data) =>
      (data['fullName'] ?? data['name'] ?? data['employeeId'] ?? 'Employee')
          .toString();
 
  Widget _stateCard(String title, String subtitle, IconData icon, Color color) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
 
// ───────────────────────── Employee card ─────────────────────────
 
class _EmployeeSessionCard extends StatelessWidget {
  const _EmployeeSessionCard({
    required this.name,
    required this.session,
    required this.workDate,
    required this.referenceTime,
  });
 
  final String name;
  final WorkSession session;
  final DateTime workDate;
  final DateTime referenceTime;
 
  static const _workColor = AppColors.info;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final elapsed = session.sessionAt(referenceTime);
    final worked = session.workedAt(referenceTime);
    final breaks = session.breakAt(referenceTime);
    final breakCount = session.segments.where((s) => s.isBreak).length;
    final (_, statusColor, _) = _statusStyle(session.status);
    final progress =
        (elapsed.inSeconds / const Duration(hours: 8).inSeconds).clamp(0.0, 1.0);
 
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openTimeline(context),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(name: name, ringColor: statusColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(LucideIcons.clock3,
                                  size: 12, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  session.startedAt == null
                                      ? 'No activity'
                                      : '${_clock(session.startedAt, short: true)}'
                                          ' → ${_clock(session.endedAt, short: true, fallback: 'now')}',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _SessionStatusChip(status: session.status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _metricTile(
                      context,
                      LucideIcons.briefcase,
                      'Work',
                      _duration(worked, compact: true),
                      _workColor,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _metricTile(
                      context,
                      LucideIcons.coffee,
                      breakCount > 0 ? 'Break ×$breakCount' : 'Break',
                      _duration(breaks, compact: true),
                      AppColors.warning,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _metricTile(
                      context,
                      LucideIcons.timer,
                      'Session',
                      _duration(elapsed, compact: true),
                      AppColors.primary,
                      isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _activityBar(isDark),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${(progress * 100).round()}% of 8h target',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      'View timeline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(LucideIcons.chevronRight,
                        size: 14, color: AppColors.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
 
  /// Segmented bar: blue = work, amber = breaks, laid out in time order.
  Widget _activityBar(bool isDark) {
    final track = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.08);
    final segs = session.segments.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final weights =
        segs.map((s) => s.duration(referenceTime).inSeconds).toList();
    final total = weights.fold<int>(0, (a, b) => a + b);
 
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 8,
        color: track,
        child: total <= 0
            ? null
            : Row(
                children: [
                  for (var i = 0; i < segs.length; i++)
                    if (weights[i] > 0)
                      Expanded(
                        flex: weights[i],
                        child: Container(
                          margin: EdgeInsets.only(right: i == segs.length - 1 ? 0 : 1.5),
                          color: segs[i].isBreak ? AppColors.warning : _workColor,
                        ),
                      ),
                ],
              ),
      ),
    );
  }
 
  Widget _metricTile(BuildContext context, IconData icon, String label,
          String value, Color color, bool isDark) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 12, color: color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
 
  // ───────────────────────── Timeline sheet ─────────────────────────
 
  void _openTimeline(BuildContext context) {
    final entries = _buildEntries();
    final elapsed = session.sessionAt(referenceTime);
    final worked = session.workedAt(referenceTime);
    final breaks = session.breakAt(referenceTime);
 
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(
                    name: name,
                    ringColor: _statusStyle(session.status).$2,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          DateFormat('EEEE, dd MMMM yyyy').format(workDate),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _SessionStatusChip(status: session.status),
                ],
              ),
              const SizedBox(height: 18),
              if (session.status != WorkStatus.idle)
                Row(
                  children: [
                    _sheetStat(context, 'Session', _duration(elapsed),
                        AppColors.primary),
                    const SizedBox(width: 8),
                    _sheetStat(context, 'Actual work', _duration(worked),
                        AppColors.info),
                    const SizedBox(width: 8),
                    _sheetStat(context, 'Breaks', _duration(breaks),
                        AppColors.warning),
                  ],
                ),
              const SizedBox(height: 18),
              Text(
                'Timeline',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.calendarX,
                                size: 36,
                                color:
                                    AppColors.textMuted.withValues(alpha: 0.6)),
                            const SizedBox(height: 10),
                            const Text('No activity recorded for this date.'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _timelineTile(
                          context,
                          entries[i],
                          isFirst: i == 0,
                          isLast: i == entries.length - 1,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
 
  Widget _sheetStat(
          BuildContext context, String label, String value, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );
 
  List<_TimelineEntry> _buildEntries() {
    final entries = <_TimelineEntry>[];
    if (session.startedAt != null) {
      entries.add(_TimelineEntry(
        session.startedAt!,
        'Start Day',
        'Session started',
        LucideIcons.play,
        AppColors.success,
      ));
    }
    var breakNumber = 0;
    for (final segment in session.segments.where((s) => s.isBreak)) {
      breakNumber++;
      entries.add(_TimelineEntry(
        segment.start,
        'Break $breakNumber started',
        'Break timer started',
        LucideIcons.coffee,
        AppColors.warning,
      ));
      if (segment.end != null) {
        entries.add(_TimelineEntry(
          segment.end!,
          'Resume Work',
          'Break $breakNumber lasted ${_duration(segment.duration(referenceTime))}',
          LucideIcons.zap,
          AppColors.info,
        ));
      }
    }
    if (session.endedAt != null) {
      entries.add(_TimelineEntry(
        session.endedAt!,
        'End Day',
        'Session completed',
        LucideIcons.flag,
        AppColors.primary,
      ));
    }
    entries.sort((a, b) => a.at.compareTo(b.at));
    return entries;
  }
 
  Widget _timelineTile(
    BuildContext context,
    _TimelineEntry e, {
    required bool isFirst,
    required bool isLast,
  }) {
    final lineColor = AppColors.textMuted.withValues(alpha: 0.25);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                      width: 2, color: isFirst ? Colors.transparent : lineColor),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: e.color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(e.icon, size: 15, color: e.color),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                      width: 2, color: isLast ? Colors.transparent : lineColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          e.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _clock(e.at),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  static String _clock(DateTime? value,
      {bool short = false, String fallback = '—'}) {
    if (value == null) return fallback;
    return DateFormat(short ? 'hh:mm a' : 'hh:mm:ss a').format(value);
  }
 
  static String _duration(Duration value, {bool compact = false}) {
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (compact) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    final seconds = value.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
 
class _TimelineEntry {
  const _TimelineEntry(
      this.at, this.title, this.description, this.icon, this.color);
 
  final DateTime at;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}
 
// ───────────────────────── Small widgets ─────────────────────────
 
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.ringColor, this.size = 44});
 
  final String name;
  final Color ringColor;
  final double size;
 
  static const _palette = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFEF4444),
  ];
 
  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final list = parts.toList();
    final a = list.first[0];
    final b = list.length > 1 ? list.last[0] : '';
    return (a + b).toUpperCase();
  }
 
  @override
  Widget build(BuildContext context) {
    final base = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor.withValues(alpha: 0.7), width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, Color.lerp(base, Colors.black, 0.25)!],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.33,
          ),
        ),
      ),
    );
  }
}
 
class _SessionStatusChip extends StatelessWidget {
  const _SessionStatusChip({required this.status});
 
  final WorkStatus status;
 
  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}