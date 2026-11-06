/// Call model representing a VOIP call record in Firestore.
///
/// Maps directly to the `calls` collection.
class CallModel {
  final String callId;
  final String taskId;
  final String assignmentId;
  final String userId;
  final String leadId;
  final String customerPhone;
  final String? exotelCallSid;
  final String status; // initiated | ringing | in_progress | completed | failed
  final String? recordingUrl;
  final int duration; // seconds
  final DateTime? startedAt;
  final DateTime? endedAt;

  const CallModel({
    required this.callId,
    required this.taskId,
    required this.assignmentId,
    required this.userId,
    required this.leadId,
    required this.customerPhone,
    this.exotelCallSid,
    this.status = 'initiated',
    this.recordingUrl,
    this.duration = 0,
    this.startedAt,
    this.endedAt,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      callId: json['callId'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      assignmentId: json['assignmentId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      leadId: json['leadId'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      exotelCallSid: json['exotelCallSid'] as String?,
      status: json['status'] as String? ?? 'initiated',
      recordingUrl: json['recordingUrl'] as String?,
      duration: json['duration'] as int? ?? 0,
      startedAt: json['startedAt'] != null
          ? (json['startedAt'] is DateTime
              ? json['startedAt'] as DateTime
              : DateTime.tryParse(json['startedAt'].toString()))
          : null,
      endedAt: json['endedAt'] != null
          ? (json['endedAt'] is DateTime
              ? json['endedAt'] as DateTime
              : DateTime.tryParse(json['endedAt'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'taskId': taskId,
        'assignmentId': assignmentId,
        'userId': userId,
        'leadId': leadId,
        'customerPhone': customerPhone,
        'exotelCallSid': exotelCallSid,
        'status': status,
        'recordingUrl': recordingUrl,
        'duration': duration,
        'startedAt': startedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
      };

  CallModel copyWith({
    String? status,
    String? exotelCallSid,
    String? recordingUrl,
    int? duration,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return CallModel(
      callId: callId,
      taskId: taskId,
      assignmentId: assignmentId,
      userId: userId,
      leadId: leadId,
      customerPhone: customerPhone,
      exotelCallSid: exotelCallSid ?? this.exotelCallSid,
      status: status ?? this.status,
      recordingUrl: recordingUrl ?? this.recordingUrl,
      duration: duration ?? this.duration,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  bool get isActive =>
      status == 'initiated' || status == 'ringing' || status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}
