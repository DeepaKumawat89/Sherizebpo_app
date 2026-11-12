// lib/models/work_session.dart
import 'package:cloud_firestore/cloud_firestore.dart';
 
enum WorkStatus { idle, active, onBreak, ended }
 
WorkStatus _statusFrom(String? s) {
  switch (s) {
    case 'active':
      return WorkStatus.active;
    case 'on_break':
      return WorkStatus.onBreak;
    case 'ended':
      return WorkStatus.ended;
    default:
      return WorkStatus.idle;
  }
}
 
String statusToString(WorkStatus s) {
  switch (s) {
    case WorkStatus.active:
      return 'active';
    case WorkStatus.onBreak:
      return 'on_break';
    case WorkStatus.ended:
      return 'ended';
    case WorkStatus.idle:
      return 'idle';
  }
}
 
class WorkSegment {
  final bool isBreak;
  final DateTime start;
  final DateTime? end; // null => currently running
 
  const WorkSegment({required this.isBreak, required this.start, this.end});
 
  factory WorkSegment.fromMap(Map<String, dynamic> m) => WorkSegment(
        isBreak: m['type'] == 'break',
        start: (m['start'] as Timestamp).toDate(),
        end: (m['end'] as Timestamp?)?.toDate(),
      );
 
  Map<String, dynamic> toMap() => {
        'type': isBreak ? 'break' : 'work',
        'start': Timestamp.fromDate(start),
        'end': end == null ? null : Timestamp.fromDate(end!),
      };
 
  Duration duration([DateTime? now]) =>
      (end ?? now ?? DateTime.now()).difference(start);
}
 
class WorkSession {
  final String id;
  final String userId;
  final String date; // yyyy-MM-dd
  final WorkStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<WorkSegment> segments;
  final String progressNote;
  final int progressPercent;
 
  const WorkSession({
    required this.id,
    required this.userId,
    required this.date,
    required this.status,
    required this.segments,
    this.startedAt,
    this.endedAt,
    this.progressNote = '',
    this.progressPercent = 0,
  });
 
  factory WorkSession.empty(String uid, String date) => WorkSession(
        id: '${uid}_$date',
        userId: uid,
        date: date,
        status: WorkStatus.idle,
        segments: const [],
      );
 
  factory WorkSession.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    return WorkSession(
      id: doc.id,
      userId: (d['userId'] ?? '').toString(),
      date: (d['date'] ?? '').toString(),
      status: _statusFrom(d['status'] as String?),
      startedAt: (d['startedAt'] as Timestamp?)?.toDate(),
      endedAt: (d['endedAt'] as Timestamp?)?.toDate(),
      segments: ((d['segments'] as List?) ?? [])
          .map((e) => WorkSegment.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      progressNote: (d['progressNote'] ?? '').toString(),
      progressPercent: (d['progressPercent'] ?? 0) as int,
    );
  }
 
  Duration workedAt(DateTime now) => segments
      .where((s) => !s.isBreak)
      .fold(Duration.zero, (a, s) => a + s.duration(now));
 
  Duration breakAt(DateTime now) => segments
      .where((s) => s.isBreak)
      .fold(Duration.zero, (a, s) => a + s.duration(now));

  /// Full elapsed session time, including breaks. The daily goal intentionally
  /// continues while an employee is on break.
  Duration sessionAt(DateTime now) {
    if (startedAt == null) return Duration.zero;
    final end = endedAt ?? now;
    if (end.isBefore(startedAt!)) return Duration.zero;
    return end.difference(startedAt!);
  }
}
