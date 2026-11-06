/// Transaction model representing an earnings transaction.
class TransactionModel {
  final String id;
  final String title;
  final String type; // payout | withdrawal
  final double amount;
  final String status; // completed | processing | failed
  final DateTime date;

  const TransactionModel({
    required this.id,
    required this.title,
    required this.type,
    required this.amount,
    required this.status,
    required this.date,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      title: json['title'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      status: json['status'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'amount': amount,
        'status': status,
        'date': date.toIso8601String(),
      };

  bool get isCredit => type == 'payout';
}
