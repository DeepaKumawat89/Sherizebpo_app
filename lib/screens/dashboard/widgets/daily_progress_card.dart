// lib/widgets/daily_progress_card.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;
 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:human_bpo/core/constants/app_colors.dart';
import 'package:human_bpo/core/constants/app_sizes.dart';
import 'package:human_bpo/core/theme/app_decorations.dart';
import 'package:human_bpo/models/work_session.dart';
import 'package:human_bpo/services/work_session_service.dart';
import 'package:lucide_icons/lucide_icons.dart';
 
// Semantic colours for the session states.
const _kWork = Color(0xFF3B82F6);
const _kWorkLight = Color(0xFF60A5FA);
const _kBreak = Color(0xFFF59E0B);
const _kBreakLight = Color(0xFFFBBF24);
const _kDone = Color(0xFF16A34A);
const _kDoneLight = Color(0xFF4ADE80);
 
/// Daily time-utilization card. Place it directly below the dashboard app bar.
class DailyProgressCard extends StatefulWidget {
  const DailyProgressCard({Key? key, required this.uid, this.targetHours = 8})
      : super(key: key);
 
  final String uid;
  final int targetHours;
 
  @override
  State<DailyProgressCard> createState() => _DailyProgressCardState();
}
 
class _DailyProgressCardState extends State<DailyProgressCard> {
  final _service = WorkSessionService();
  late Stream<WorkSession> _stream;
  late String _streamDate;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  bool _busy = false;
 
  @override
  void initState() {
    super.initState();
    _streamDate = WorkSessionService.todayKey();
    _stream = _service.watchToday(widget.uid);
    // Repaint only. Real time is derived from timestamps, so it is safe
    // if the app is backgrounded or killed.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final date = WorkSessionService.todayKey(now);
      if (date != _streamDate) {
        setState(() {
          _now = now;
          _streamDate = date;
          _stream = _service.watchToday(widget.uid);
        });
      } else {
        setState(() => _now = now);
      }
    });
  }
 
  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
 
  // ── helpers ────────────────────────────────────────────────
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
 
  String _hms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
 
  String _hm(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
 
  String _clock(DateTime? t) {
    if (t == null) return '--';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h12:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }
 
  String _dateLabel(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]}';
  }
 
  Color _statusColor(WorkStatus s) {
    switch (s) {
      case WorkStatus.active:
        return _kWork;
      case WorkStatus.onBreak:
        return _kBreak;
      case WorkStatus.ended:
        return _kDone;
      case WorkStatus.idle:
        return AppColors.primary;
    }
  }
 
  // ── dialogs / sheets ───────────────────────────────────────
  Future<void> _confirmEnd(WorkSession s) async {
    final worked = s.workedAt(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('End your day?'),
        content: Text(
          'You have worked ${_hm(worked)} today. '
          'You will not be able to restart the timer after ending.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep working')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End Day')),
        ],
      ),
    );
    if (ok == true) await _run(() => _service.endDay(widget.uid));
  }
 
  Future<void> _openProgressSheet(WorkSession s) async {
    final noteCtrl = TextEditingController(text: s.progressNote);
    double percent = s.progressPercent.toDouble();
    final isDark = Theme.of(context).brightness == Brightness.dark;
 
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 4, 22, MediaQuery.of(ctx).viewInsets.bottom + 22),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                          AppDecorations.iconBox(color: AppColors.primary),
                      child: const Icon(LucideIcons.target,
                          size: 20, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today's progress",
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          Text('Log how much of your daily goal is done',
                              style: Theme.of(ctx).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    '${percent.round()}%',
                    style: Theme.of(ctx).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    trackHeight: 8,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 22),
                  ),
                  child: Slider(
                    value: percent,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (v) => setSheet(() => percent = v),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final p in const [0, 25, 50, 75, 100])
                      ChoiceChip(
                        label: Text('$p%'),
                        selected: percent.round() == p,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setSheet(() => percent = p.toDouble());
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: noteCtrl,
                  maxLines: 4,
                  minLines: 3,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'What did you work on today?',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _GradientButton(
                  label: 'Save progress',
                  icon: LucideIcons.check,
                  gradient: AppDecorations.primaryGradient,
                  shadowColor: AppColors.primary,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _run(() => _service.saveProgress(widget.uid,
                        note: noteCtrl.text, percent: percent.round()));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }
 
  // ── build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
 
    return StreamBuilder<WorkSession>(
      stream: _stream,
      initialData: WorkSession.empty(
        widget.uid,
        _streamDate,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return _streamError(context);
        }
        final s = snap.data ??
            WorkSession.empty(widget.uid, _streamDate);
        final accent = _statusColor(s.status);
        final worked = s.workedAt(_now);
        final onBreak = s.breakAt(_now);
 
        return Container(
          margin: const EdgeInsets.only(bottom: AppSizes.xl),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(AppSizes.radiusXl),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border.withValues(alpha: 0.7),
            ),
            boxShadow: isDark ? null : AppDecorations.shadowMd,
          ),
          child: Stack(
            children: [
              // Soft status-tinted glow in the corner.
              Positioned(
                right: -50,
                top: -50,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: isDark ? 0.14 : 0.09),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(s, accent, isDark),
                    const SizedBox(height: 18),
                    _hero(s, worked, onBreak, isDark),
                    const SizedBox(height: 20),
                    _timeline(s, isDark),
                    const SizedBox(height: 20),
                    _actions(s, worked),
                    if (s.status != WorkStatus.idle) ...[
                      const SizedBox(height: 14),
                      _progressTile(s, isDark),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _streamError(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.xl),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Unable to load today's work session. "
              'Please check your connection and try again.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
 
  // ── sections ───────────────────────────────────────────────
  Widget _header(WorkSession s, Color accent, bool isDark) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: AppDecorations.iconBox(color: accent),
          child: Icon(LucideIcons.clock, size: 20, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Work Session",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _dateLabel(_now),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark ? Colors.white54 : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        _StatusChip(status: s.status),
      ],
    );
  }
 
  Widget _hero(WorkSession s, Duration worked, Duration onBreak, bool isDark) {
    final goal = Duration(hours: widget.targetHours);
    final progress = (worked.inSeconds / goal.inSeconds).clamp(0.0, 1.0);
    final goalReached = worked >= goal;
    final textMain = isDark ? Colors.white : AppColors.textDark;
    final textSub = isDark ? Colors.white54 : AppColors.textMuted;
 
    final List<Color> ringColors;
    switch (s.status) {
      case WorkStatus.onBreak:
        ringColors = const [_kBreak, _kBreakLight];
        break;
      case WorkStatus.ended:
        ringColors = const [_kDone, _kDoneLight];
        break;
      default:
        ringColors = const [_kWork, _kWorkLight];
    }
 
    return LayoutBuilder(builder: (context, c) {
      final ring = math.min(136.0, c.maxWidth * 0.46);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: ring,
            height: ring,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(ring),
                  painter: _RingPainter(
                    progress: progress,
                    colors: ringColors,
                    trackColor: isDark
                        ? Colors.white.withValues(alpha: 0.09)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hms(worked),
                      style: TextStyle(
                        fontSize: ring < 120 ? 17 : 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: textMain,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    goalReached
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.checkCircle,
                                  size: 12, color: _kDone),
                              const SizedBox(width: 3),
                              Text('Goal reached',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: _kDone)),
                            ],
                          )
                        : Text(
                            'of ${widget.targetHours}h goal',
                            style: TextStyle(fontSize: 10.5, color: textSub),
                          ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                _StatTile(
                  icon: LucideIcons.briefcase,
                  color: _kWork,
                  label: 'Worked',
                  value: _hm(worked),
                ),
                const SizedBox(height: 12),
                _StatTile(
                  icon: LucideIcons.coffee,
                  color: _kBreak,
                  label: 'Break',
                  value: _hm(onBreak),
                ),
                const SizedBox(height: 12),
                _StatTile(
                  icon: LucideIcons.logIn,
                  color: _kDone,
                  label: 'Started',
                  value: _clock(s.startedAt),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
 
  Widget _timeline(WorkSession s, bool isDark) {
    final textSub = isDark ? Colors.white54 : AppColors.textMuted;
    final start = s.startedAt ?? _now;
    final end = s.status == WorkStatus.ended ? (s.endedAt ?? _now) : _now;
    final elapsedSec = s.startedAt == null ? 0 : end.difference(start).inSeconds;
    final scaleHours =
        math.max(widget.targetHours, (elapsedSec / 3600).ceil());
    final step = scaleHours > 8 ? 2 : 1;
    final live = s.status == WorkStatus.active || s.status == WorkStatus.onBreak;
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Timeline',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    )),
            const Spacer(),
            const _LegendDot(color: _kWork, label: 'Work'),
            const SizedBox(width: 12),
            const _LegendDot(color: _kBreak, label: 'Break', hatched: true),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 26,
          width: double.infinity,
          child: CustomPaint(
            painter: _TimelinePainter(
              segments: s.segments,
              dayStart: start,
              now: end,
              scaleHours: scaleHours,
              showMarker: live,
              markerColor: s.status == WorkStatus.onBreak ? _kBreak : _kWork,
              trackColor: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.06),
              tickColor: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              gapColor: Theme.of(context).cardColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 14,
          child: Stack(
            children: [
              for (var h = 0; h <= scaleHours; h += step)
                Align(
                  alignment: Alignment(-1 + 2 * h / scaleHours, 0),
                  child: Text('${h}h',
                      style: TextStyle(fontSize: 10, color: textSub)),
                ),
            ],
          ),
        ),
      ],
    );
  }
 
  Widget _actions(WorkSession s, Duration worked) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
 
    Widget endButton() => SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _confirmEnd(s),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              side: BorderSide(
                  color: isDark
                      ? Colors.white24
                      : AppColors.border.withValues(alpha: 0.9)),
            ),
            icon: const Icon(LucideIcons.flag, size: 16),
            label: const Text('End Day',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        );
 
    switch (s.status) {
      case WorkStatus.idle:
        return _GradientButton(
          label: 'Start Day',
          icon: LucideIcons.play,
          gradient: AppDecorations.primaryGradient,
          shadowColor: AppColors.primary,
          loading: _busy,
          onTap: () => _run(() => _service.start(widget.uid)),
        );
      case WorkStatus.active:
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: _GradientButton(
                label: 'Take Break',
                icon: LucideIcons.pause,
                gradient: const LinearGradient(
                    colors: [_kBreak, _kBreakLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                shadowColor: _kBreak,
                loading: _busy,
                onTap: () => _run(() => _service.startBreak(widget.uid)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: endButton()),
          ],
        );
      case WorkStatus.onBreak:
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: _GradientButton(
                label: 'Resume',
                icon: LucideIcons.play,
                gradient: AppDecorations.primaryGradient,
                shadowColor: AppColors.primary,
                loading: _busy,
                onTap: () => _run(() => _service.resume(widget.uid)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: endButton()),
          ],
        );
      case WorkStatus.ended:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kDone.withValues(alpha: isDark ? 0.14 : 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kDone.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.checkCircle, color: _kDone, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Day completed',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(
                      '${_hm(worked)} worked · ended ${_clock(s.endedAt)}',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              isDark ? Colors.white60 : AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
 
  Widget _progressTile(WorkSession s, bool isDark) {
    final hasNote = s.progressNote.isNotEmpty || s.progressPercent > 0;
    final textMain = isDark ? Colors.white : AppColors.textDark;
    final textSub = isDark ? Colors.white54 : AppColors.textMuted;
 
    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : AppColors.primarySoft.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProgressSheet(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration:
                        AppDecorations.iconBox(color: AppColors.primary),
                    child: Icon(
                        hasNote ? LucideIcons.edit3 : LucideIcons.plus,
                        size: 17,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasNote ? 'Daily progress' : "Log today's progress",
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: textMain),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.progressNote.isNotEmpty
                              ? s.progressNote
                              : 'Tap to add what you worked on',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.3, color: textSub),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  hasNote
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${s.progressPercent}%',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: AppColors.primary)),
                        )
                      : Icon(LucideIcons.chevronRight,
                          size: 18, color: textSub),
                ],
              ),
              if (s.progressPercent > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: s.progressPercent / 100,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
 
// ═══════════════════════════════════════════════════════════
// SMALL WIDGETS
// ═══════════════════════════════════════════════════════════
 
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final WorkStatus status;
 
  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;
    switch (status) {
      case WorkStatus.active:
        text = 'Active';
        color = _kDone;
        break;
      case WorkStatus.onBreak:
        text = 'On Break';
        color = _kBreak;
        break;
      case WorkStatus.ended:
        text = 'Completed';
        color = AppColors.primary;
        break;
      case WorkStatus.idle:
        text = 'Not started';
        color = Colors.grey;
        break;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, pulsing: status == WorkStatus.active),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
 
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;
 
  @override
  State<_PulseDot> createState() => _PulseDotState();
}
 
class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
 
  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }
 
  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }
 
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: widget.pulsing
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.55 * (1 - _c.value)),
                    blurRadius: 2 + 8 * _c.value,
                    spreadRadius: 4 * _c.value,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
 
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
 
  final IconData icon;
  final Color color;
  final String label;
  final String value;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : AppColors.textMuted)),
              const SizedBox(height: 1),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: isDark ? Colors.white : AppColors.textDark)),
            ],
          ),
        ),
      ],
    );
  }
}
 
class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.hatched = false,
  });
  final Color color;
  final String label;
  final bool hatched;
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: hatched ? color.withValues(alpha: 0.35) : color,
            borderRadius: BorderRadius.circular(3),
            border: hatched ? Border.all(color: color, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : AppColors.textMuted)),
      ],
    );
  }
}
 
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
    required this.onTap,
    this.loading = false,
  });
 
  final String label;
  final IconData icon;
  final Gradient gradient;
  final Color shadowColor;
  final VoidCallback onTap;
  final bool loading;
 
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: loading ? 0.10 : 0.32),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 17, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              letterSpacing: 0.1)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
 
// ═══════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════
 
/// Circular goal ring with a gradient arc and soft glow.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.colors,
    required this.trackColor,
  });
 
  final double progress;
  final List<Color> colors;
  final Color trackColor;
 
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
 
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );
 
    if (progress <= 0.004) return;
    final sweep = math.pi * 2 * progress;
 
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.max(sweep, 0.01),
      colors: colors,
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
 
    // Glow
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = colors.first.withValues(alpha: 0.4),
    );
 
    // Arc
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }
 
  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.colors != colors;
}
 
/// Segmented day timeline: blue = work, hatched amber = break,
/// with a glowing marker at the current moment.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.segments,
    required this.dayStart,
    required this.now,
    required this.scaleHours,
    required this.showMarker,
    required this.markerColor,
    required this.trackColor,
    required this.tickColor,
    required this.gapColor,
  });
 
  final List<WorkSegment> segments;
  final DateTime dayStart;
  final DateTime now;
  final int scaleHours;
  final bool showMarker;
  final Color markerColor;
  final Color trackColor;
  final Color tickColor;
  final Color gapColor;
 
  @override
  void paint(Canvas canvas, Size size) {
    final totalSec = scaleHours * 3600.0;
    final h = size.height;
    final bar = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(h / 2));
 
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
 
    // Hour ticks
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    for (var i = 1; i < scaleHours; i++) {
      final x = size.width * i / scaleHours;
      canvas.drawLine(Offset(x, 0), Offset(x, h), tick);
    }
 
    var first = true;
    for (final seg in segments) {
      final a = seg.start.difference(dayStart).inSeconds / totalSec;
      final b = (seg.end ?? now).difference(dayStart).inSeconds / totalSec;
      final left = a.clamp(0.0, 1.0) * size.width;
      final right = b.clamp(0.0, 1.0) * size.width;
      if (right <= left) continue;
      final rect = Rect.fromLTRB(left, 0, right, h);
 
      if (seg.isBreak) {
        canvas.drawRect(
            rect, Paint()..color = _kBreak.withValues(alpha: 0.22));
        canvas.save();
        canvas.clipRect(rect);
        final stripe = Paint()
          ..color = _kBreak.withValues(alpha: 0.9)
          ..strokeWidth = 3.5;
        for (double x = left - h; x < right; x += 9) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), stripe);
        }
        canvas.restore();
      } else {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(colors: [_kWork, _kWorkLight])
                .createShader(rect),
        );
      }
 
      if (!first) {
        canvas.drawRect(Rect.fromLTWH(left - 1, 0, 2, h),
            Paint()..color = gapColor);
      }
      first = false;
    }
    canvas.restore();
 
    // "Now" marker
    if (showMarker) {
      final x = ((now.difference(dayStart).inSeconds / totalSec)
                  .clamp(0.0, 1.0)) *
              size.width;
      final cx = x.clamp(h / 2, size.width - h / 2);
      final c = Offset(cx, h / 2);
      canvas.drawCircle(
          c, h / 2 + 2, Paint()..color = markerColor.withValues(alpha: 0.25));
      canvas.drawCircle(c, h / 2 - 5, Paint()..color = Colors.white);
      canvas.drawCircle(
          c,
          h / 2 - 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = markerColor);
    }
  }
 
  @override
  bool shouldRepaint(covariant _TimelinePainter old) => true;
}