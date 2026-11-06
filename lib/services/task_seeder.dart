import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Utility to seed a sample task into the Firestore `tasks` collection.
/// Useful for testing the worker flow.
class TaskSeeder {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a realistic sample task in Firestore.
  static Future<bool> seedSampleTask() async {
    try {
      final taskRef = _firestore.collection('tasks').doc();

      final sampleTask = {
        'company': 'TechCorp Solutions',
        'type': 'call',
        'title': 'Outbound B2B Sales',
        'description':
            'Call provided leads to qualify them for our new enterprise software suite. Use the provided script.',
        'payout_per_unit': 12.50,
        'payout_unit': 'lead',
        'total_volume': 100,
        'completed_volume': 0,
        'status': 'active',
        'urgency': 'urgent',
        'deadline':
            DateTime.now().add(const Duration(days: 7)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'script':
            '"Hello, am I speaking with [Contact Name]? I\'m calling on behalf of TechCorp Solutions..."',
      };

      await taskRef.set(sampleTask);

      debugPrint('Successfully seeded sample task: ${taskRef.id}');
      return true;
    } catch (e) {
      debugPrint('Failed to seed task: $e');
      return false;
    }
  }
}
