import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../models/call_model.dart';
import '../../services/call_service.dart';
import '../../core/utils/string_utils.dart';

/// Full-featured VOIP Call Screen.
///
/// Shows real-time call status, timer, recording indicator,
/// and result submission after the call ends.
class CallScreen extends StatefulWidget {
  final String? taskId;
  final String? assignmentId;
  final String? leadId;
  final String? leadName;
  final String? customerPhone;
  final String? clientName;

  const CallScreen({
    Key? key,
    this.taskId,
    this.assignmentId,
    this.leadId,
    this.leadName,
    this.customerPhone,
    this.clientName,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();

  String? _activeCallId;
  CallModel? _currentCall;
  StreamSubscription? _callSubscription;

  // UI State
  bool _isInitiating = false;
  bool _isEnding = false;
  String _callStatus =
      'idle'; // idle | initiating | ringing | in_progress | completed | failed
  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  String? _errorMessage;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Start Call ───────────────────────────────────────────────
  Future<void> _initiateCall() async {
    if (_isInitiating || widget.customerPhone == null) return;

    setState(() {
      _isInitiating = true;
      _callStatus = 'initiating';
      _errorMessage = null;
      _callDurationSeconds = 0;
    });

    try {
      final callId = await _callService.startCall(
        taskId: widget.taskId ?? '',
        assignmentId: widget.assignmentId ?? '',
        leadId: widget.leadId ?? '',
        customerPhone: widget.customerPhone!,
      );

      if (callId != null && mounted) {
        _activeCallId = callId;

        // Listen to real-time call updates
        _callSubscription = _callService.watchCall(callId).listen((call) {
          if (!mounted) return;
          setState(() {
            _currentCall = call;
            if (call != null) {
              _callStatus = call.status;

              // Start timer when call is in progress
              if (call.status == 'in_progress' && _durationTimer == null) {
                _startDurationTimer();
              }

              // Stop timer when call ends
              if (call.status == 'completed' || call.status == 'failed') {
                _stopDurationTimer();
                if (call.duration > 0) {
                  _callDurationSeconds = call.duration;
                }
              }
            }
          });
        });

        setState(() => _isInitiating = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitiating = false;
          _callStatus = 'failed';
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  // ─── End Call ─────────────────────────────────────────────────
  Future<void> _endCall() async {
    if (_isEnding || _activeCallId == null) return;

    setState(() => _isEnding = true);

    try {
      await _callService.endCall(_activeCallId!);
      _stopDurationTimer();

      if (mounted) {
        setState(() {
          _isEnding = false;
          _callStatus = 'completed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEnding = false;
          _errorMessage = 'Failed to end call: $e';
        });
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _returnWithResult() {
    Navigator.pop(context, {
      'callId': _activeCallId,
      'duration': _callDurationSeconds,
      'status': _callStatus,
      'recordingUrl': _currentCall?.recordingUrl,
    });
  }

  // ─── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.lg, vertical: AppSizes.md),
              child: Row(
                children: [
                  if (_callStatus == 'idle' ||
                      _callStatus == 'completed' ||
                      _callStatus == 'failed')
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  if (_callStatus == 'in_progress' ||
                      _callStatus == 'ringing') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'REC',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // ── Contact Avatar ──
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final isActive =
                    _callStatus == 'ringing' || _callStatus == 'in_progress';
                return Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A1A2E),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppColors.success.withValues(
                                  alpha: 0.15 + 0.1 * _pulseController.value),
                              blurRadius: 40 + 20 * _pulseController.value,
                              spreadRadius: 5 + 10 * _pulseController.value,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      (widget.leadName?.isNotEmpty == true)
                          ? widget.leadName![0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSizes.xl),

            // ── Contact Name ──
            Text(
              widget.leadName ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.customerPhone != null ? StringUtils.maskPhoneNumber(widget.customerPhone!) : '',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            if (widget.clientName != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.clientName!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: AppSizes.xxxl),

            // ── Call Status & Timer ──
            _buildStatusDisplay(),

            const Spacer(flex: 3),

            // ── Error Message ──
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.xxl),
                child: Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertTriangle,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_errorMessage != null) const SizedBox(height: AppSizes.lg),

            // ── Action Buttons ──
            _buildActionButtons(),

            const SizedBox(height: AppSizes.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDisplay() {
    String statusText;
    Color statusColor;

    switch (_callStatus) {
      case 'idle':
        statusText = 'Ready to call';
        statusColor = Colors.white.withValues(alpha: 0.5);
        break;
      case 'initiating':
        statusText = 'Connecting...';
        statusColor = AppColors.warning;
        break;
      case 'ringing':
        statusText = 'Ringing...';
        statusColor = AppColors.info;
        break;
      case 'in_progress':
        statusText = _formatDuration(_callDurationSeconds);
        statusColor = AppColors.success;
        break;
      case 'completed':
        statusText = 'Call ended · ${_formatDuration(_callDurationSeconds)}';
        statusColor = Colors.white.withValues(alpha: 0.7);
        break;
      case 'failed':
        statusText = 'Call failed';
        statusColor = AppColors.error;
        break;
      default:
        statusText = _callStatus;
        statusColor = Colors.white.withValues(alpha: 0.5);
    }

    return Column(
      children: [
        if (_callStatus == 'in_progress')
          Text(
            _formatDuration(_callDurationSeconds),
            style: TextStyle(
              color: statusColor,
              fontSize: 48,
              fontWeight: FontWeight.w300,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (_callStatus == 'in_progress') ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Call in progress',
                style: TextStyle(
                  color: AppColors.success.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    switch (_callStatus) {
      case 'idle':
      case 'failed':
        return Column(
          children: [
            // Call button
            GestureDetector(
              onTap: _isInitiating ? null : _initiateCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _isInitiating
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _isInitiating
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    : const Icon(LucideIcons.phone,
                        color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              _callStatus == 'failed' ? 'Retry Call' : 'Start Call',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

      case 'initiating':
      case 'ringing':
      case 'in_progress':
        return Column(
          children: [
            // End call button
            GestureDetector(
              onTap: _isEnding ? null : _endCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.error.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _isEnding
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      )
                    : const Icon(LucideIcons.phoneOff,
                        color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              'End Call',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

      case 'completed':
        return Column(
          children: [
            // Return with result
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.xxxl),
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: ElevatedButton.icon(
                  onPressed: _returnWithResult,
                  icon: const Icon(LucideIcons.checkCircle, size: 20),
                  label: const Text('Continue to Submit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            // Call again option
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _callStatus = 'idle';
                  _activeCallId = null;
                  _currentCall = null;
                  _callDurationSeconds = 0;
                  _errorMessage = null;
                  _callSubscription?.cancel();
                });
              },
              icon: Icon(LucideIcons.phoneCall,
                  size: 16, color: Colors.white.withValues(alpha: 0.5)),
              label: Text(
                'Call Again',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

/// Custom AnimatedBuilder that works like AnimatedBuilder
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    Key? key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(key: key, listenable: animation);

  @override
  Widget build(BuildContext context) => builder(context, child);
}
