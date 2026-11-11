// lib/services/work_session_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/work_session.dart';
 
class WorkSessionService {
  WorkSessionService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;
 
  final FirebaseFirestore _db;
 
  static String todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
 
  DocumentReference<Map<String, dynamic>> _ref(String uid, String date) =>
      _db.collection('work_sessions').doc('${uid}_$date');
 
  /// Live stream of today's session (empty session if none exists yet).
  Stream<WorkSession> watchToday(String uid) {
    final date = todayKey();
    return _ref(uid, date).snapshots().map((snap) =>
        snap.exists ? WorkSession.fromDoc(snap) : WorkSession.empty(uid, date));
  }
 
  Future<void> start(String uid) => _mutate(uid, (s, segs, now) {
        if (s.status != WorkStatus.idle) return null;
        segs.add(WorkSegment(isBreak: false, start: now));
        return {'status': 'active', 'startedAt': Timestamp.fromDate(now)};
      });
 
  Future<void> startBreak(String uid) => _mutate(uid, (s, segs, now) {
        if (s.status != WorkStatus.active) return null;
        _closeOpen(segs, now);
        segs.add(WorkSegment(isBreak: true, start: now));
        return {'status': 'on_break'};
      });
 
  Future<void> resume(String uid) => _mutate(uid, (s, segs, now) {
        if (s.status != WorkStatus.onBreak) return null;
        _closeOpen(segs, now);
        segs.add(WorkSegment(isBreak: false, start: now));
        return {'status': 'active'};
      });
 
  Future<void> endDay(String uid) => _mutate(uid, (s, segs, now) {
        if (s.status != WorkStatus.active && s.status != WorkStatus.onBreak) {
          return null;
        }
        _closeOpen(segs, now);
        return {'status': 'ended', 'endedAt': Timestamp.fromDate(now)};
      });
 
  Future<void> saveProgress(String uid,
      {required String note, required int percent}) {
    final date = todayKey();
    return _ref(uid, date).set({
      'userId': uid,
      'date': date,
      'progressNote': note.trim(),
      'progressPercent': percent.clamp(0, 100),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
 
  // ── helpers ──────────────────────────────────────────────
  void _closeOpen(List<WorkSegment> segs, DateTime now) {
    if (segs.isNotEmpty && segs.last.end == null) {
      final last = segs.removeLast();
      segs.add(WorkSegment(isBreak: last.isBreak, start: last.start, end: now));
    }
  }
 
  /// Runs a transactional state change. [change] returns extra fields to
  /// write, or null if the transition is not valid (no-op).
  Future<void> _mutate(
    String uid,
    Map<String, dynamic>? Function(
            WorkSession s, List<WorkSegment> segs, DateTime now)
        change,
  ) async {
    final date = todayKey();
    final ref = _ref(uid, date);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final session =
          snap.exists ? WorkSession.fromDoc(snap) : WorkSession.empty(uid, date);
      final segs = List<WorkSegment>.from(session.segments);
      final extra = change(session, segs, DateTime.now());
      if (extra == null) return;
 
      final now = DateTime.now();
      final worked = segs
          .where((s) => !s.isBreak && s.end != null)
          .fold<int>(0, (a, s) => a + s.duration().inSeconds);
      final brk = segs
          .where((s) => s.isBreak && s.end != null)
          .fold<int>(0, (a, s) => a + s.duration().inSeconds);
 
      tx.set(
          ref,
          {
            'userId': uid,
            'date': date,
            'segments': segs.map((s) => s.toMap()).toList(),
            'totalWorkedSeconds': worked, // closed segments only
            'totalBreakSeconds': brk,
            'lastEventAt': Timestamp.fromDate(now),
            'updatedAt': FieldValue.serverTimestamp(),
            if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
            ...extra,
          },
          SetOptions(merge: true));
    });
  }
}
 