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

  Stream<WorkSession> watchToday(String uid) {
    final date = todayKey();
    return _ref(uid, date).snapshots().map((snap) =>
        snap.exists ? WorkSession.fromDoc(snap) : WorkSession.empty(uid, date));
  }

  Future<void> start(String uid) => _transition(uid, 'start_day');

  Future<void> startBreak(String uid) => _transition(uid, 'start_break');

  Future<void> resume(String uid) => _transition(uid, 'resume_work');

  Future<void> endDay(String uid) => _transition(uid, 'end_day');

  Future<void> saveProgress(String uid,
      {required String note, required int percent}) {
    final date = todayKey();
    return _ref(uid, date).update({
      'progressNote': note.trim(),
      'progressPercent': percent.clamp(0, 100),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Applies one lifecycle event atomically in Firestore. Reading the current
  /// status inside the transaction prevents double taps and stale clients from
  /// appending duplicate or out-of-order segments.
  Future<void> _transition(String uid, String action) async {
    final date = todayKey();
    final ref = _ref(uid, date);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final session = snapshot.exists
          ? WorkSession.fromDoc(snapshot)
          : WorkSession.empty(uid, date);
      final raw = snapshot.data() ?? const <String, dynamic>{};
      final segments = List<WorkSegment>.from(session.segments);
      final events = ((raw['events'] as List?) ?? const [])
          .whereType<Map>()
          .map((event) => Map<String, dynamic>.from(event))
          .toList();
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);
      final update = <String, dynamic>{};

      switch (action) {
        case 'start_day':
          if (session.status != WorkStatus.idle || session.startedAt != null) {
            throw StateError('This work day has already started.');
          }
          segments.add(WorkSegment(isBreak: false, start: now));
          events.add({'type': 'start_day', 'at': timestamp});
          update.addAll({'status': 'active', 'startedAt': timestamp});
          break;
        case 'start_break':
          if (session.status != WorkStatus.active) {
            throw StateError('A break can only start while working.');
          }
          _closeOpenSegment(segments, now, expectedBreak: false);
          segments.add(WorkSegment(isBreak: true, start: now));
          events.add({'type': 'break_start', 'at': timestamp});
          update['status'] = 'on_break';
          break;
        case 'resume_work':
          if (session.status != WorkStatus.onBreak) {
            throw StateError('Work can only resume from an active break.');
          }
          final breakStart = _closeOpenSegment(
            segments,
            now,
            expectedBreak: true,
          );
          events.add({
            'type': 'break_end',
            'at': timestamp,
            'durationSeconds': now.difference(breakStart).inSeconds,
          });
          segments.add(WorkSegment(isBreak: false, start: now));
          update['status'] = 'active';
          break;
        case 'end_day':
          if (session.status != WorkStatus.active &&
              session.status != WorkStatus.onBreak) {
            throw StateError('This work day has already ended.');
          }
          final wasOnBreak = session.status == WorkStatus.onBreak;
          final segmentStart = _closeOpenSegment(
            segments,
            now,
            expectedBreak: wasOnBreak,
          );
          if (wasOnBreak) {
            events.add({
              'type': 'break_end',
              'at': timestamp,
              'durationSeconds': now.difference(segmentStart).inSeconds,
            });
          }
          events.add({'type': 'end_day', 'at': timestamp});
          update.addAll({'status': 'ended', 'endedAt': timestamp});
          break;
        default:
          throw ArgumentError.value(action, 'action');
      }

      final workedSeconds = segments
          .where((segment) => !segment.isBreak && segment.end != null)
          .fold<int>(0, (total, segment) =>
              total + segment.duration().inSeconds);
      final breakSeconds = segments
          .where((segment) => segment.isBreak && segment.end != null)
          .fold<int>(0, (total, segment) =>
              total + segment.duration().inSeconds);

      transaction.set(
        ref,
        {
          'userId': uid,
          'date': date,
          'segments': segments.map((segment) => segment.toMap()).toList(),
          'events': events,
          'totalWorkedSeconds': workedSeconds,
          'totalBreakSeconds': breakSeconds,
          'lastEventAt': timestamp,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!snapshot.exists || raw['createdAt'] == null)
            'createdAt': FieldValue.serverTimestamp(),
          ...update,
        },
        SetOptions(merge: true),
      );
    });
  }

  DateTime _closeOpenSegment(
    List<WorkSegment> segments,
    DateTime now, {
    required bool expectedBreak,
  }) {
    if (segments.isEmpty ||
        segments.last.end != null ||
        segments.last.isBreak != expectedBreak) {
      throw StateError('The current work session is inconsistent.');
    }
    final open = segments.removeLast();
    segments.add(WorkSegment(
      isBreak: open.isBreak,
      start: open.start,
      end: now,
    ));
    return open.start;
  }
}
