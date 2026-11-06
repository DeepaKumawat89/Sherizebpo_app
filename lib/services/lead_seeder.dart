import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Utility to seed sample leads into a task's subcollection.
///
/// Creates 5 sample leads under tasks/{taskId}/leads/ with
/// name, phone, and status fields.
class LeadSeeder {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Seeds 5 sample leads into the specified task.
  /// Returns true on success, false on failure.
  static Future<bool> seedLeads(String taskId) async {
    try {
      final leadsRef =
          _firestore.collection('tasks').doc(taskId).collection('leads');

      // Check if leads already exist (prevent duplicate seeding)
      final existing = await leadsRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        debugPrint('Leads already exist for task $taskId — skipping seed.');
        return true;
      }

      final sampleLeads = [
        {
          'name': 'Rahul Sharma',
          'phone': '+91 98765 43210',
          'status': 'not_called',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Priya Patel',
          'phone': '+91 87654 32109',
          'status': 'not_called',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Amit Kumar',
          'phone': '+91 76543 21098',
          'status': 'not_called',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Sneha Reddy',
          'phone': '+91 65432 10987',
          'status': 'not_called',
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Vikram Singh',
          'phone': '+91 54321 09876',
          'status': 'not_called',
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      final batch = _firestore.batch();
      for (final lead in sampleLeads) {
        batch.set(leadsRef.doc(), lead);
      }
      await batch.commit();

      debugPrint(
          'Successfully seeded ${sampleLeads.length} leads for task $taskId');
      return true;
    } catch (e) {
      debugPrint('Failed to seed leads: $e');
      return false;
    }
  }
}
