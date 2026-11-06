import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String message;
  final String type;
  final String? relatedTaskId;
  final String? relatedSubmissionId;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    this.relatedTaskId,
    this.relatedSubmissionId,
    this.read = false,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json, String id) {
    return NotificationModel(
      id: id,
      userId: json['userId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      type: json['type'] as String? ?? '',
      relatedTaskId: json['relatedTaskId'] as String?,
      relatedSubmissionId: json['relatedSubmissionId'] as String?,
      read: json['read'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'title': title,
        'message': message,
        'type': type,
        'relatedTaskId': relatedTaskId,
        'relatedSubmissionId': relatedSubmissionId,
        'read': read,
        'createdAt': FieldValue.serverTimestamp(),
      };

  NotificationModel copyWith({
    String? title,
    String? message,
    String? type,
    String? relatedTaskId,
    String? relatedSubmissionId,
    bool? read,
  }) {
    return NotificationModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      relatedTaskId: relatedTaskId ?? this.relatedTaskId,
      relatedSubmissionId: relatedSubmissionId ?? this.relatedSubmissionId,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}
