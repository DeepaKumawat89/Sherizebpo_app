import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/call_lifecycle.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/string_utils.dart';
import '../../routes.dart';
import '../../services/task_service.dart';
import '../../widgets/custom_button.dart';

class TaskExecutionScreen extends StatefulWidget {
  final String? taskId;
  final String? assignmentId;
  final dynamic payout;
  final String? script;
  final String? clientName;
  final dynamic tatDeadline; // Timestamp from Firestore
  final int totalLeads; // Lead quota assigned to this subtask

  const TaskExecutionScreen({
    Key? key,
    this.taskId,
    this.assignmentId,
    this.payout,
    this.script,
    this.clientName,
    this.tatDeadline,
    this.totalLeads = 0,
  }) : super(key: key);

  bool get simulateQaManualCall =>
      kDebugMode &&
      const bool.fromEnvironment('QA_SIMULATE_MANUAL_CALLS') &&
      (taskId == 'CLIE-QARE-2177' || taskId == 'CLIE-QARE-2615');

  @override
  State<TaskExecutionScreen> createState() => _TaskExecutionScreenState();
}

class _TaskExecutionScreenState extends State<TaskExecutionScreen>
    with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  final _notesCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isConnectingCall = false;
  bool _isCallActive = false;
  bool _activeCallEnded = false;
  bool _taskStarted = false;
  bool _showSuccessCard = false;

  Map<String, dynamic>? _currentLead;
  String? _currentLeadId;
  int _leadsProcessed = 0;
  int _totalLeads = 0;
  String? _errorMessage;
  final Map<String, String> _guidance = {};
  bool _guidanceLoadFailed = false;

  int _callSeconds = 0;
  Timer? _callTimer;
  String? _selectedOutcome;
  DateTime? _requeueAt;
  String? _activeCallSid; // Exotel Call SID for recording lookup
  String? _activeCallId; // Firestore calls/{id} doc for the active Exotel call
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _callSubscription;

  // ── TAT countdown ─────────────────────────────────────
  Timer? _tatTimer;
  Duration _tatRemaining = Duration.zero;
  bool _isTatOverdue = false;

  late AnimationController _fadeCtrl;

  final _outcomes = [
    {
      'value': 'interested',
      'label': 'Interested',
      'icon': LucideIcons.thumbsUp,
      'color': AppColors.success
    },
    {
      'value': 'not_interested',
      'label': 'Not Interested',
      'icon': LucideIcons.thumbsDown,
      'color': AppColors.error
    },
    {
      'value': 'callback',
      'label': 'Callback',
      'icon': LucideIcons.phoneForwarded,
      'color': AppColors.warning
    },
    {
      'value': 'no_answer',
      'label': 'No Answer',
      'icon': LucideIcons.phoneMissed,
      'color': AppColors.textMuted
    },
    {
      'value': 'wrong_number',
      'label': 'Wrong Number',
      'icon': LucideIcons.ban,
      'color': AppColors.error
    },
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _loadLeads();
  }

  void _initTatTimer(dynamic raw) {
    _tatTimer?.cancel();
    if (raw == null) return;
    DateTime deadline;
    if (raw is Timestamp) {
      deadline = raw.toDate();
    } else {
      return;
    }
    _updateTatRemaining(deadline);
    _tatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTatRemaining(deadline);
    });
  }

  void _updateTatRemaining(DateTime deadline) {
    final diff = deadline.difference(DateTime.now());
    setState(() {
      _tatRemaining = diff.isNegative ? Duration.zero : diff;
      _isTatOverdue = diff.isNegative;
    });
  }

  String _formatTat(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _callTimer?.cancel();
    _callSubscription?.cancel();
    _tatTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeads() async {
    try {
      if (widget.taskId == null) throw StateError('A task is required.');
      _guidance.addAll(await TaskService().getTaskGuidance(
        widget.taskId!, fallbackScript: widget.script,
      ));
    } catch (error) {
      debugPrint('Error loading task guidance: $error');
      _guidanceLoadFailed = true;
      if (widget.script?.trim().isNotEmpty == true) {
        _guidance['CALL SCRIPT'] = widget.script!.trim();
      }
    }
    if (!mounted) return;
    try {
      // Leads are now scoped by taskId (per-task ownership), so the old
      // campaign-id resolution from the assignment is no longer needed.
      await _fetchNextLead();
    } catch (e) {
      debugPrint('Error loading leads: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchNextLead() async {
    await _callSubscription?.cancel();
    _callSubscription = null;
    try {
      if (mounted) setState(() => _errorMessage = null);
      final response = await FirebaseFunctions.instance
          .httpsCallable('getTaskAssignmentProgress')
          .call({'assignmentId': widget.assignmentId, 'claimLead': true});
      final progress = Map<String, dynamic>.from(response.data as Map);
      if (progress['taskId'] != widget.taskId) {
        throw StateError('This assignment belongs to a different task.');
      }
      if (!mounted) return;
      final deadline = progress['tatDeadline'] as num?;
      _initTatTimer(deadline == null ? null : Timestamp.fromMillisecondsSinceEpoch(deadline.toInt()));
      setState(() {
        _leadsProcessed = (progress['leadsProcessed'] as num).toInt();
        _totalLeads = (progress['totalLeads'] as num).toInt();
        _currentLead = progress['lead'] == null ? null : Map<String, dynamic>.from(progress['lead'] as Map);
        _currentLeadId = _currentLead?['id'] as String?;
        _errorMessage = _isTatOverdue ? 'This assignment has exceeded its TAT.'
            : !['active', 'in_progress', 'completed'].contains(progress['status'])
                ? 'This assignment is no longer active.' : null;
        _notesCtrl.clear();
        _selectedOutcome = null;
        _requeueAt = null;
        _callSeconds = 0;
        _isCallActive = false;
        _activeCallEnded = false;
        _activeCallSid = null;
        _activeCallId = null;
      });
    } catch (e) {
      debugPrint('Error fetching next lead: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _currentLead = null;
          _currentLeadId = null;
        });
      }
    }
  }

  Future<void> _startCall() async {
    if (widget.simulateQaManualCall) return;
    final customerPhone = _currentLead?['phone'];
    if (customerPhone == null) return;

    setState(() {
      _isConnectingCall = true;
      _activeCallEnded = false;
    });

    DocumentReference<Map<String, dynamic>>? callRef;

    try {
      // Exotel bridges the worker's phone with the customer's, masking both
      // behind the ExoPhone. The backend holds the Exotel credentials — the app
      // only creates the call record and asks the backend to start the call.
      callRef = FirebaseFirestore.instance.collection('calls').doc();
      await callRef.set({
        'callId': callRef.id,
        'taskId': widget.taskId,
        'assignmentId': widget.assignmentId,
        'userId': user!.uid,
        'leadId': _currentLeadId,
        'customerPhone': customerPhone,
        'status': 'initiated',
        'recordingUrl': null,
        'exotelCallSid': null,
        'duration': 0,
        'startedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
      });

      if (!mounted) return;
      setState(() => _activeCallId = callRef!.id);
      _watchCall(callRef);

      final idToken = await user!.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/start-call'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'callId': callRef.id,
          'userId': user!.uid,
          'taskId': widget.taskId,
          'assignmentId': widget.assignmentId,
          'leadId': _currentLeadId,
          'customerPhone': customerPhone,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['error'] ?? 'Failed to connect');
      }

      final resultData = jsonDecode(response.body) as Map<String, dynamic>;

      if (mounted) {
        // Capture the Exotel Call SID so we can look up the recording later.
        final callSid = resultData['callSid'] as String?;
        setState(() {
          _isConnectingCall = false;
          _isCallActive = !_activeCallEnded;
          _taskStarted = true;
          if (callSid != null) _activeCallSid = callSid;
        });

        if (!_activeCallEnded) _ensureCallTimer();
      }
    } catch (e) {
      Map<String, dynamic>? callData;
      if (callRef != null) {
        try {
          callData = (await callRef.get()).data();
          _applyCallUpdate(callData);
        } catch (_) {
          // The live listener can still reconcile a later provider update.
        }
      }
      if (!mounted || CallLifecycle.wasAccepted(callData)) return;

      if (CallLifecycle.status(callData) == 'starting') {
        SnackBarUtils.showInfo(
          'Exotel is still confirming the call. This screen will update automatically.',
        );
      } else {
        setState(() => _isConnectingCall = false);
        SnackBarUtils.showError('Failed to connect call: $e');
      }
    }
  }

  void _watchCall(DocumentReference<Map<String, dynamic>> callRef) {
    _callSubscription?.cancel();
    _callSubscription = callRef.snapshots().listen(
      (snapshot) {
        if (!mounted || _activeCallId != callRef.id) return;
        _applyCallUpdate(snapshot.data());
      },
      onError: (Object error) {
        debugPrint('Error watching Exotel call ${callRef.id}: $error');
      },
    );
  }

  void _applyCallUpdate(Map<String, dynamic>? callData) {
    if (!mounted || callData == null) return;

    final accepted = CallLifecycle.wasAccepted(callData);
    final terminal = CallLifecycle.isTerminal(callData);
    final providerDuration = CallLifecycle.duration(callData);
    final callSid = callData['exotelCallSid']?.toString();

    if (!accepted && !terminal) return;

    setState(() {
      _isConnectingCall = false;
      if (terminal) _activeCallEnded = true;
      _isCallActive = accepted && !terminal;
      if (accepted) {
        _taskStarted = true;
        if (callSid != null && callSid.isNotEmpty) _activeCallSid = callSid;
      }
      if (providerDuration > _callSeconds) _callSeconds = providerDuration;
    });

    if (terminal) {
      _callTimer?.cancel();
      _callTimer = null;
    } else if (accepted) {
      _ensureCallTimer();
    }
  }

  void _ensureCallTimer() {
    if (_callTimer?.isActive == true) return;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  void _endCall() {
    _callTimer?.cancel();
    _callTimer = null;
    // Best-effort: ask the backend to hang up the Exotel legs. The call also
    // ends naturally when the worker/customer hang up their phones.
    final callId = _activeCallId;
    if (callId != null && !widget.simulateQaManualCall) {
      user!.getIdToken().then((idToken) {
        http.post(
          Uri.parse('${AppConstants.baseUrl}/end-call'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'callId': callId, 'userId': user!.uid}),
        ).timeout(const Duration(seconds: 10));
      }).catchError((_) {/* non-critical */});
    }
    setState(() {
      _isCallActive = false;
    });
  }

  Future<void> _startManualCall() async {
    final customerPhone = _currentLead?['phone'];
    if (customerPhone == null) return;
    
    final uri = Uri.parse('tel:$customerPhone');
    try {
      if (!widget.simulateQaManualCall) await launchUrl(uri);
      if (mounted) {
        setState(() {
          if (widget.simulateQaManualCall) {
            _activeCallId = null;
            _activeCallSid = null;
          }
          _isCallActive = true;
          _taskStarted = true;
        });
        
        _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _callSeconds++);
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Could not launch native dialer: $e');
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isRequeueOutcome =>
      _selectedOutcome == 'callback' || _selectedOutcome == 'no_answer';

  Future<void> _pickRequeueAt() async {
    final now = DateTime.now();
    final initial = _requeueAt ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 364)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (selected.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      SnackBarUtils.showInfo('Choose a return time at least 1 minute from now.');
      return;
    }
    if (selected.isAfter(DateTime.now().add(const Duration(days: 365)))) {
      SnackBarUtils.showInfo('Choose a return time within 365 days.');
      return;
    }
    setState(() => _requeueAt = selected);
  }

  Future<void> _submitLead() async {
    if (_selectedOutcome == null) {
      SnackBarUtils.showInfo('Please select a call outcome');
      return;
    }

    if (_isRequeueOutcome &&
        (_requeueAt == null ||
            _requeueAt!.isBefore(DateTime.now().add(const Duration(minutes: 1))))) {
      SnackBarUtils.showInfo('Set a return time at least 1 minute from now.');
      return;
    }

    if (_callSeconds < 5 && _selectedOutcome != 'no_answer' && _selectedOutcome != 'wrong_number') {
      SnackBarUtils.showInfo('Minimum 5 seconds call duration required');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Submission is server-authoritative: the submitTaskWork callable
      // re-checks campaign pause state, funds, and lead ownership, sets the
      // payout, writes the submission, and updates the lead status.
      final callable = FirebaseFunctions.instance.httpsCallable('submitTaskWork');
      final result = await callable.call(<String, dynamic>{
        'taskId': widget.taskId,
        'assignmentId': widget.assignmentId,
        'leadId': _currentLeadId,
        'outcome': _selectedOutcome,
        if (_requeueAt != null) 'requeueAt': _requeueAt!.millisecondsSinceEpoch,
        'notes': widget.simulateQaManualCall
          ? 'QA SIMULATION: no call was placed; duration is a simulated timer.\n${_notesCtrl.text.trim()}'.trimRight()
          : _notesCtrl.text.trim(),
        'callDuration': _callSeconds,
        'callSid': _activeCallSid,
        'callId': _activeCallId,
        'workerName': user?.displayName ?? user?.email ?? 'Unknown Employee',
      });

      if (mounted) {
        setState(() {
          _leadsProcessed = (result.data['leadsProcessed'] as num).toInt();
          _showSuccessCard = true;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        SnackBarUtils.showError(e.message ?? 'Failed to submit.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Failed to submit: $e');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusXl)),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(gradient: AppDecorations.accentGradient, shape: BoxShape.circle),
                child: const Icon(LucideIcons.checkCircle, size: 36, color: Colors.white),
              ),
              const SizedBox(height: AppSizes.xl),
              const Text('Task Complete! 🎉', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: AppSizes.sm),
              const Text('All leads have been processed.', textAlign: TextAlign.center),
              const SizedBox(height: AppSizes.xxl),
              CustomButton(
                label: 'Back to Dashboard',
                icon: LucideIcons.home,
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goToNextLead() async {
    setState(() {
      _showSuccessCard = false;
      _taskStarted = false;
      _isLoading = true;
    });
    await _fetchNextLead();
    if (mounted) setState(() => _isLoading = false);
    if (_currentLead == null && _errorMessage == null && _totalLeads > 0 &&
      _leadsProcessed >= _totalLeads && mounted) {
      if (mounted) {
        SnackBarUtils.showSuccess('Task completed successfully! 🎉');
        _showCompletionDialog();
      }
    } else if (mounted) {
      SnackBarUtils.showSuccess('Lead processed successfully.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Task Execution'), backgroundColor: Theme.of(context).scaffoldBackgroundColor),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentLead == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Task Execution'), backgroundColor: Theme.of(context).scaffoldBackgroundColor),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_errorMessage != null ? LucideIcons.alertCircle : LucideIcons.inbox, size: 48, color: isDark ? Colors.white24 : AppColors.textLightest),
              const SizedBox(height: AppSizes.md),
                Text(_errorMessage ?? (_totalLeads > 0 && _leadsProcessed >= _totalLeads
                  ? 'All $_totalLeads leads processed' : 'No leads to process')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.clientName ?? 'Execution'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          // Leads done counter
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.radiusRound),
            ),
            child: Center(
              child: Text(
                _totalLeads > 0
                  ? '${(_leadsProcessed + (_showSuccessCard ? 0 : 1)).clamp(0, _totalLeads)}/$_totalLeads'
                    : '${_leadsProcessed + 1} done',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
          // TAT countdown chip
          if (widget.tatDeadline != null)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (_isTatOverdue ? AppColors.error : (_tatRemaining.inMinutes < 30 ? AppColors.warning : AppColors.success)).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSizes.radiusRound),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isTatOverdue ? LucideIcons.alertCircle : LucideIcons.timer,
                    size: 13,
                    color: _isTatOverdue ? AppColors.error : (_tatRemaining.inMinutes < 30 ? AppColors.warning : AppColors.success),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isTatOverdue ? 'OVERDUE' : _formatTat(_tatRemaining),
                    style: TextStyle(
                      color: _isTatOverdue ? AppColors.error : (_tatRemaining.inMinutes < 30 ? AppColors.warning : AppColors.success),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.screenPaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressBar(isDark),
            const SizedBox(height: AppSizes.xl),
            _buildLeadInfoCard(isDark),
            const SizedBox(height: AppSizes.lg),
            for (final entry in _guidance.entries) ...[
              _buildScriptCard(isDark, entry.key, entry.value),
              const SizedBox(height: AppSizes.md),
            ],
            if (_guidanceLoadFailed || _guidance.isEmpty)
              Text(
                _guidanceLoadFailed
                    ? 'Unable to load task instructions. Reopen this task to retry.'
                    : 'No instructions or call script provided for this task.',
                style: TextStyle(color: isDark ? Colors.white60 : AppColors.textMuted),
              ),
            const SizedBox(height: AppSizes.lg),
            _buildCallSection(isDark),
            const SizedBox(height: AppSizes.lg),
            _buildOutcomeSection(isDark),
            const SizedBox(height: AppSizes.lg),
            _buildNotesSection(isDark),
            const SizedBox(height: AppSizes.xl),
            if (_showSuccessCard) _buildSubmitSuccessCard(isDark) else
              CustomButton(
                label: _isTatOverdue ? 'Time Expired (TAT Overdue)' : (_isSubmitting ? 'Submitting...' : 'Submit & Next'),
                icon: LucideIcons.send,
                isLoading: _isSubmitting,
                isDisabled: !_taskStarted || _isSubmitting || _isTatOverdue,
                onPressed: _submitLead,
              ),
            const SizedBox(height: AppSizes.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(bool isDark) {
    final double? progressValue = _totalLeads > 0
      ? (_leadsProcessed / _totalLeads).clamp(0.0, 1.0)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            _totalLeads > 0
              ? 'Progress: $_leadsProcessed / $_totalLeads leads done'
              : 'Progress: $_leadsProcessed leads done',
          style: TextStyle(color: isDark ? Colors.white38 : AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressValue,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildLeadInfoCard(bool isDark) {
    final name = _currentLead?['name'] ?? 'Unknown';
    final rawPhone = _currentLead?['phone'] ?? 'N/A';
    final phone = rawPhone != 'N/A' ? StringUtils.maskPhoneNumber(rawPhone) : rawPhone;
    final bool isRequeued = _currentLead?['isRequeued'] == true;
    final String? requeueReason = _currentLead?['requeueReason'] as String?;
    final int requeueCount = (_currentLead?['requeueCount'] as int?) ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: isRequeued
            ? (isDark ? AppColors.warning.withValues(alpha: 0.08) : const Color(0xFFFFFBEB))
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(
          color: isRequeued
              ? AppColors.warning.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor,
        ),
        boxShadow: isDark ? null : AppDecorations.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Retry badge — only shown when this lead was previously unanswered/callback
          if (isRequeued) ...[
            Container(
              margin: const EdgeInsets.only(bottom: AppSizes.md),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.refreshCw, size: 13, color: AppColors.warning),
                  const SizedBox(width: 5),
                  Text(
                    'Retry Call #$requeueCount'
                    '${requeueReason == "no_answer" ? " — No Answer" : requeueReason == "callback" ? " — Callback" : ""}',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : AppColors.textDark)),
                  Text(phone, style: TextStyle(color: isDark ? Colors.white38 : AppColors.textMuted, fontSize: 13)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptCard(bool isDark, String title, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.primary.withValues(alpha: 0.05) : AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: isDark ? AppColors.primary.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.fileText, size: 16, color: isDark ? AppColors.primaryLight : AppColors.primary),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: isDark ? AppColors.primaryLight : AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),
        SelectableText(text, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : AppColors.textDark, height: 1.5)),
      ]),
    );
  }

  Widget _buildCallSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: _isCallActive ? (isDark ? AppColors.success.withValues(alpha: 0.1) : AppColors.successBg) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: _isCallActive ? AppColors.success.withValues(alpha: 0.2) : Theme.of(context).dividerColor),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_isCallActive ? LucideIcons.phoneCall : LucideIcons.phone, size: 24, color: _isCallActive ? AppColors.success : (isDark ? Colors.white24 : AppColors.textLightest)),
          const SizedBox(width: 12),
          Text(_formatDuration(_callSeconds), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.textDark, fontFamily: 'monospace')),
        ]),
        const SizedBox(height: AppSizes.lg),
        if (!_isCallActive && !_taskStarted)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (widget.simulateQaManualCall || _isConnectingCall || _isTatOverdue) ? null : _startCall,
                  icon: _isConnectingCall
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.phoneCall, size: 18),
                  label: Text(widget.simulateQaManualCall ? 'Exotel disabled for QA' : (_isTatOverdue ? 'TAT Overdue' : (_isConnectingCall ? 'Dialing your phone...' : 'Connect via Exotel'))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTatOverdue ? AppColors.surfaceVariant : AppColors.success,
                    foregroundColor: _isTatOverdue ? AppColors.textMuted : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isConnectingCall || _isTatOverdue) ? null : _startManualCall,
                  icon: const Icon(LucideIcons.smartphone, size: 18),
                  label: Text(widget.simulateQaManualCall ? 'Simulate Manual Call (QA)' : 'Manual Call (Fallback)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : AppColors.textDark,
                    side: BorderSide(color: isDark ? Colors.white24 : AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        if (_isCallActive)
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _endCall, icon: const Icon(LucideIcons.phoneOff, size: 18), label: const Text('End Call'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)))),
      ]),
    );
  }

  Widget _buildOutcomeSection(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Call Outcome', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : AppColors.textDark)),
      const SizedBox(height: AppSizes.md),
      Wrap(spacing: 8, runSpacing: 8, children: _outcomes.map((o) {
        final selected = _selectedOutcome == o['value'];
        final color = o['color'] as Color;
        return GestureDetector(
          onTap: () => setState(() {
            _selectedOutcome = o['value'] as String;
            if (!_isRequeueOutcome) _requeueAt = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.15) : (isDark ? Colors.white10 : AppColors.surfaceVariant),
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              border: Border.all(color: selected ? color : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(o['icon'] as IconData, size: 14, color: selected ? color : (isDark ? Colors.white38 : AppColors.textMuted)),
              const SizedBox(width: 6),
              Text(o['label'] as String, style: TextStyle(color: selected ? color : (isDark ? Colors.white60 : AppColors.textBody), fontWeight: selected ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
            ]),
          ),
        );
      }).toList()),
      if (_isRequeueOutcome) ...[
        const SizedBox(height: AppSizes.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickRequeueAt,
            icon: const Icon(LucideIcons.calendarClock, size: 18),
            label: Text(
              _requeueAt == null
                  ? 'Set retry time'
                  : '${MaterialLocalizations.of(context).formatMediumDate(_requeueAt!)} at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_requeueAt!))}',
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Only this lead will return for retry at the selected time under the same task.',
          style: TextStyle(
            color: isDark ? Colors.white38 : AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    ]);
  }

  Widget _buildNotesSection(bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Call Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : AppColors.textDark)),
      const SizedBox(height: AppSizes.md),
      TextField(
        controller: _notesCtrl,
        maxLines: 3,
        style: TextStyle(color: isDark ? Colors.white : AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Enter any specific details about the conversation...',
          hintStyle: TextStyle(color: isDark ? Colors.white24 : AppColors.textPlaceholder),
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
    ]);
  }

  Widget _buildSubmitSuccessCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.xl),
      decoration: BoxDecoration(
        color: isDark ? AppColors.success.withValues(alpha: 0.1) : AppColors.successBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        const Icon(LucideIcons.checkCircle, color: AppColors.success, size: 48),
        const SizedBox(height: AppSizes.md),
        const Text('Submission Received!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.success)),
        const SizedBox(height: AppSizes.lg),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _goToNextLead, style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white), child: const Text('Next Lead'))),
      ]),
    );
  }
}
