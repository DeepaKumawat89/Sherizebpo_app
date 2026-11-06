import 'package:cloud_firestore/cloud_firestore.dart';

class FaqModel {
  final String id;
  final String question;
  final String answer;
  final String category;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int order;
  final bool isActive;

  const FaqModel({
    required this.id,
    required this.question,
    required this.answer,
    required this.category,
    required this.order,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
    this.tags = const [],
  });

  factory FaqModel.fromJson(Map<String, dynamic> json, String id) {
    return FaqModel(
      id: id,
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      category: json['category'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : const [],
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? (json['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'category': category,
        'order': order,
        'isActive': isActive,
        'tags': tags,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
