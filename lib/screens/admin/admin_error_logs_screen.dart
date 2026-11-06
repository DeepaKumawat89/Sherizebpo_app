import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/constants/constants.dart';
import '../../core/utils/snackbar_utils.dart';

/// Admin Error Logs Screen — view, resolve, and delete application error logs.
///
/// Reads from the `error_logs` Firestore collection populated by
/// [ErrorLoggingService]. Shows error message, source, timestamp, stack trace
/// in an expandable detail view, with filter toggles and batch actions.
///
/// Inspired by Lovable AI's admin ErrorLogs page.
class AdminErrorLogsScreen extends StatefulWidget {
  const AdminErrorLogsScreen({Key? key}) : super(key: key);

  @override
  State<AdminErrorLogsScreen> createState() => _AdminErrorLogsScreenState();
}

class _AdminErrorLogsScreenState extends State<AdminErrorLogsScreen> {
  bool _showResolved = false;
  String? _sourceFilter; // null = all
  Future<QuerySnapshot>? _logsFuture;

  static const List<String> _sourceOptions = [
    'flutter_framework',
    'platform_dispatcher',
    'zone_uncaught',
    'manual',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('error_logs')
        .where('resolved', isEqualTo: _showResolved)
        .orderBy('createdAt', descending: true)
        .limit(100);

    if (_sourceFilter != null) {
      query = FirebaseFirestore.instance
          .collection('error_logs')
          .where('resolved', isEqualTo: _showResolved)
          .where('errorSource', isEqualTo: _sourceFilter)
          .orderBy('createdAt', descending: true)
          .limit(100);
    }

    _logsFuture = query.get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Error Logs'),
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
        actions: [
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: () => setState(() => _loadLogs()),
          ),
          // Source filter
          PopupMenuButton<String?>(
            icon: Icon(
              LucideIcons.filter,
              color: _sourceFilter != null
                  ? AppColors.primary
                  : AppColors.textMuted,
              size: 20,
            ),
            tooltip: 'Filter by source',
            onSelected: (value) => setState(() {
              _sourceFilter = value;
              _loadLogs();
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All Sources')),
              ..._sourceOptions.map((s) => PopupMenuItem(
                    value: s,
                    child: Text(_prettifySource(s)),
                  )),
            ],
          ),
          // Toggle resolved/unresolved
          IconButton(
            icon: Icon(
              _showResolved ? LucideIcons.eyeOff : LucideIcons.eye,
              size: 20,
              color: AppColors.textBody,
            ),
            tooltip: _showResolved ? 'Show unresolved' : 'Show resolved',
            onPressed: () => setState(() {
              _showResolved = !_showResolved;
              _loadLogs();
            }),
          ),
          const SizedBox(width: AppSizes.sm),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<QuerySnapshot>(
      future: _logsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.alertTriangle,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    'Failed to load error logs.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shieldCheck,
                    size: 56, color: AppColors.success),
                const SizedBox(height: AppSizes.md),
                Text(
                  _showResolved
                      ? 'No resolved errors.'
                      : 'No unresolved errors!',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _showResolved
                      ? 'Switch to unresolved to see active errors.'
                      : 'All clear — your app is running smoothly.',
                  style:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Stats bar
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.screenPaddingH, vertical: AppSizes.sm),
              color: AppColors.surface,
              child: Row(
                children: [
                  _buildStatChip(
                    '${docs.length}',
                    _showResolved ? 'resolved' : 'unresolved',
                    _showResolved ? AppColors.success : AppColors.error,
                  ),
                  const Spacer(),
                  if (_sourceFilter != null)
                    Chip(
                      label: Text(
                        _prettifySource(_sourceFilter!),
                        style: const TextStyle(fontSize: 12),
                      ),
                      deleteIcon: const Icon(LucideIcons.x, size: 14),
                      onDeleted: () => setState(() => _sourceFilter = null),
                      backgroundColor: AppColors.infoBg,
                      labelStyle: const TextStyle(color: AppColors.info),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Error list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSizes.screenPaddingH),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSizes.sm),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _ErrorLogCard(
                    docId: doc.id,
                    data: data,
                    onResolve: () => _toggleResolved(doc.id, !_showResolved),
                    onDelete: () => _deleteError(doc.id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatChip(String count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _toggleResolved(String docId, bool resolved) async {
    try {
      await FirebaseFirestore.instance
          .collection('error_logs')
          .doc(docId)
          .update({
        'resolved': resolved,
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });
      if (mounted) {
        SnackBarUtils.showSuccess(
            resolved ? 'Marked as resolved.' : 'Marked as unresolved.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Error: $e');
      }
    }
  }

  Future<void> _deleteError(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Error Log'),
        content: const Text('This cannot be undone. Delete this log entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('error_logs')
          .doc(docId)
          .delete();
      if (mounted) {
        SnackBarUtils.showSuccess('Error log deleted.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showError('Failed to delete: $e');
      }
    }
  }

  String _prettifySource(String source) {
    switch (source) {
      case 'flutter_framework':
        return 'Flutter Framework';
      case 'platform_dispatcher':
        return 'Platform Error';
      case 'zone_uncaught':
        return 'Uncaught Async';
      case 'manual':
        return 'Manual Log';
      default:
        return source;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Error Log Card (Expandable)
// ═══════════════════════════════════════════════════════════════════
class _ErrorLogCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onResolve;
  final VoidCallback onDelete;

  const _ErrorLogCard({
    required this.docId,
    required this.data,
    required this.onResolve,
    required this.onDelete,
  });

  @override
  State<_ErrorLogCard> createState() => _ErrorLogCardState();
}

class _ErrorLogCardState extends State<_ErrorLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.data['errorMessage'] ?? 'No message';
    final source = widget.data['errorSource'] ?? 'unknown';
    final stack = widget.data['errorStack'] as String?;
    final platform = widget.data['platform'] ?? '-';
    final userId = widget.data['userId'];
    final resolved = widget.data['resolved'] == true;
    final createdAt = widget.data['createdAt'];
    final metadata = widget.data['metadata'] as Map<String, dynamic>?;

    String timeAgo = 'Unknown time';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours}h ago';
      } else {
        timeAgo = '${diff.inDays}d ago';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: resolved
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getSourceColor(source).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getSourceIcon(source),
                      size: 16,
                      color: _getSourceColor(source),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildTag(
                              _prettifySource(source),
                              _getSourceColor(source),
                            ),
                            const SizedBox(width: 6),
                            _buildTag(platform, AppColors.textMuted),
                            const Spacer(),
                            Text(
                              timeAgo,
                              style: const TextStyle(
                                color: AppColors.textPlaceholder,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: AppColors.textPlaceholder,
                  ),
                ],
              ),
            ),
          ),

          // Expanded details
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User ID
                  if (userId != null) ...[
                    _buildDetailRow('User', userId),
                    const SizedBox(height: AppSizes.sm),
                  ],

                  // Metadata
                  if (metadata != null && metadata.isNotEmpty) ...[
                    _buildDetailRow('Metadata', metadata.toString()),
                    const SizedBox(height: AppSizes.sm),
                  ],

                  // Stack trace
                  if (stack != null && stack.isNotEmpty) ...[
                    const Text(
                      'Stack Trace',
                      style: TextStyle(
                        color: AppColors.textLabel,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          stack,
                          style: const TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                  ],

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onResolve,
                          icon: Icon(
                            resolved
                                ? LucideIcons.undo
                                : LucideIcons.checkCircle,
                            size: 16,
                          ),
                          label: Text(resolved ? 'Unresolve' : 'Mark Resolved'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      OutlinedButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 16),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textLabel,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textBody,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Color _getSourceColor(String source) {
    switch (source) {
      case 'flutter_framework':
        return AppColors.info;
      case 'platform_dispatcher':
        return AppColors.error;
      case 'zone_uncaught':
        return AppColors.warning;
      case 'manual':
        return AppColors.accent;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'flutter_framework':
        return LucideIcons.layout;
      case 'platform_dispatcher':
        return LucideIcons.smartphone;
      case 'zone_uncaught':
        return LucideIcons.alertCircle;
      case 'manual':
        return LucideIcons.pencil;
      default:
        return LucideIcons.alertTriangle;
    }
  }

  String _prettifySource(String source) {
    switch (source) {
      case 'flutter_framework':
        return 'Flutter';
      case 'platform_dispatcher':
        return 'Platform';
      case 'zone_uncaught':
        return 'Async';
      case 'manual':
        return 'Manual';
      default:
        return source;
    }
  }
}
