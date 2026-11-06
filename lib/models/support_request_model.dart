import 'package:cloud_firestore/cloud_firestore.dart';

class SupportRequestModel {
  final String id;
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String subject;
  final String message;
  final String status; // open, in_progress, resolved
  final String?
      issueType; // App crash, Task problem, Payment issue, Call issue, Other
  final String? screenshotUrl;
  final DateTime createdAt;

  const SupportRequestModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.subject,
    required this.message,
    this.status = 'open',
    this.issueType,
    this.screenshotUrl,
    required this.createdAt,
  });

  factory SupportRequestModel.fromJson(Map<String, dynamic> json, String id) {
    return SupportRequestModel(
      id: id,
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      issueType: json['issueType'] as String?,
      screenshotUrl: json['screenshotUrl'] as String?,
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'email': email,
        'phone': phone,
        'subject': subject,
        'message': message,
        'status': status,
        'issueType': issueType,
        'screenshotUrl': screenshotUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
