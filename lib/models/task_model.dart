/// Task model representing a BPO task from the marketplace.
class TaskModel {
  final String id;
  final String company;
  final String type; // call | email | chat
  final String title;
  final String description;
  final double payoutPerUnit;
  final String payoutUnit; // call | msg | ticket
  final int totalVolume;
  final int completedVolume;
  final String status; // available | in_progress | completed | rejected | out_of_tat
  final String? urgency; // null | urgent
  final DateTime deadline;
  final DateTime createdAt;

  const TaskModel({
    required this.id,
    required this.company,
    required this.type,
    required this.title,
    this.description = '',
    required this.payoutPerUnit,
    required this.payoutUnit,
    required this.totalVolume,
    this.completedVolume = 0,
    this.status = 'active',
    this.urgency,
    required this.deadline,
    required this.createdAt,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] as String,
      company: json['company'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      payoutPerUnit: (json['payout_per_unit'] as num).toDouble(),
      payoutUnit: json['payout_unit'] as String,
      totalVolume: json['total_volume'] as int,
      completedVolume: json['completed_volume'] as int? ?? 0,
      status: json['status'] as String? ?? 'active',
      urgency: json['urgency'] as String?,
      deadline: DateTime.parse(json['deadline'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'type': type,
        'title': title,
        'description': description,
        'payout_per_unit': payoutPerUnit,
        'payout_unit': payoutUnit,
        'total_volume': totalVolume,
        'completed_volume': completedVolume,
        'status': status,
        'urgency': urgency,
        'deadline': deadline.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  double get progress => totalVolume > 0 ? completedVolume / totalVolume : 0;
  bool get isUrgent => urgency == 'urgent' || urgency == 'high';
}
