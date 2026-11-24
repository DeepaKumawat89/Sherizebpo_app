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

List<WorkSessionEvent> _eventsFrom(dynamic rawEvents) {
  final events = <WorkSessionEvent>[];
  if (rawEvents is! List) return events;
  for (final rawEvent in rawEvents.whereType<Map>()) {
    try {
      events.add(
        WorkSessionEvent.fromMap(Map<String, dynamic>.from(rawEvent)),
      );
    } catch (_) {
      // A malformed legacy event should not hide the employee's whole session.
    }
  }
  return events;
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

class AttendanceLocation {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime? capturedAt;
  final String address;
  final String street;
  final String locality;
  String get area => locality;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final bool addressUnavailable;

  const AttendanceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.capturedAt,
    this.address = '',
    this.street = '',
    this.locality = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.country = '',
    this.addressUnavailable = false,
  });

  factory AttendanceLocation.fromMap(Map<String, dynamic> map) {
    final capturedAt = map['capturedAt'];
    return AttendanceLocation(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      capturedAt: capturedAt is Timestamp ? capturedAt.toDate() : null,
      address: (map['address'] ?? '').toString(),
      street: (map['street'] ?? '').toString(),
      locality: (map['area'] ?? map['locality'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      state: (map['state'] ?? '').toString(),
      postalCode: (map['postalCode'] ?? '').toString(),
      country: (map['country'] ?? '').toString(),
      addressUnavailable: map['addressUnavailable'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        if (capturedAt != null) 'capturedAt': Timestamp.fromDate(capturedAt!),
        if (address.isNotEmpty) 'address': address,
        if (street.isNotEmpty) 'street': street,
        if (locality.isNotEmpty) 'locality': locality,
        if (locality.isNotEmpty) 'area': locality,
        if (city.isNotEmpty) 'city': city,
        if (state.isNotEmpty) 'state': state,
        if (postalCode.isNotEmpty) 'postalCode': postalCode,
        if (country.isNotEmpty) 'country': country,
        if (addressUnavailable) 'addressUnavailable': true,
      };
}

class WorkSessionEvent {
  final String type;
  final DateTime at;
  final int? durationSeconds;
  final AttendanceLocation? location;

  const WorkSessionEvent({
    required this.type,
    required this.at,
    this.durationSeconds,
    this.location,
  });

  factory WorkSessionEvent.fromMap(Map<String, dynamic> map) {
    final rawLocation = map['location'];
    // Some pre-event-location records may have coordinates directly on the
    // event. Accept both shapes so the admin timeline remains compatible.
    final locationMap = rawLocation is Map
        ? Map<String, dynamic>.from(rawLocation)
        : map['latitude'] is num && map['longitude'] is num
            ? map
            : null;
    AttendanceLocation? location;
    if (locationMap != null) {
      try {
        location = AttendanceLocation.fromMap(locationMap);
      } catch (_) {
        location = null;
      }
    }
    return WorkSessionEvent(
      type: (map['type'] ?? '').toString(),
      at: (map['at'] as Timestamp).toDate(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      location: location,
    );
  }
}
 
class WorkSession {
  final String id;
  final String userId;
  final String date; // yyyy-MM-dd
  final WorkStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<WorkSegment> segments;
  final List<WorkSessionEvent> events;
  final String progressNote;
  final int progressPercent;
 
  const WorkSession({
    required this.id,
    required this.userId,
    required this.date,
    required this.status,
    required this.segments,
    this.events = const [],
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
      events: _eventsFrom(d['events']),
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
