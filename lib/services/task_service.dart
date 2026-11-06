import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/task_model.dart';
import '../core/utils/string_utils.dart';

/// Service handling background fetch and commits connecting to Cloud Firestore
/// specific to Task retrieval, creation, and execution state.
class TaskService {
  TaskService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _functions = functions, _database = firestore;

  FirebaseFirestore get _firestore => _database ?? FirebaseFirestore.instance;
  final FirebaseFunctions? _functions;
  final FirebaseFirestore? _database;

  Future<Map<String, String>> getTaskGuidance(String taskId, {String? fallbackScript}) async {
    final task = await _firestore.collection('tasks').doc(taskId).get();
    if (!task.exists) throw StateError('This task is no longer available.');
    final data = task.data()!;
    final guidance = <String, String>{};
    final seen = <String>{};
    final savedScript = data['script'];
    for (final entry in {
      'INSTRUCTIONS': data['instructions'],
      'DESCRIPTION': data['description'],
      'CALL SCRIPT': savedScript is String && savedScript.trim().isNotEmpty
          ? savedScript : fallbackScript,
    }.entries) {
      final text = entry.value is String ? (entry.value as String).trim() : '';
      if (text.isNotEmpty && seen.add(text)) guidance[entry.key] = text;
    }
    return guidance;
  }

  Future<int> acceptMarketplaceTask({
    required String taskId,
  }) async {
    final result = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable('acceptMarketplaceTask').call({'taskId': taskId});
    return (result.data['acceptedCount'] as num).toInt();
  }

  /// Generates a TSK-XXXX code guaranteed unique against existing `tasks`.
  /// Mirrors the super-admin portal + Cloud Function generators so a display
  /// code never refers to two different tasks. Widens to 6 digits if the
  /// 4-digit space is crowded.
  Future<String> _generateUniqueTaskCode() async {
    for (int i = 0; i < 8; i++) {
      final code = StringUtils.generateTaskCode();
      final dup = await _firestore
          .collection('tasks')
          .where('taskCode', isEqualTo: code)
          .limit(1)
          .get();
      if (dup.docs.isEmpty) return code;
    }
    // ponytail: 4-digit space crowded — widen to 6 digits to stay unique.
    for (;;) {
      final code = StringUtils.generateTaskCode(width: 6);
      final dup = await _firestore
          .collection('tasks')
          .where('taskCode', isEqualTo: code)
          .limit(1)
          .get();
      if (dup.docs.isEmpty) return code;
    }
  }

  /// Retrieves a stream of Available Tasks to listen to real-time events.
  Stream<List<TaskModel>> getAvailableTasks() {
    return _firestore
        .collection('tasks')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return TaskModel.fromJson(data);
      }).toList();
    });
  }

  // ─── Admin: Create Task with Leads ──────────────────────────
  /// Creates a new task document in [tasks/] and optionally batch-writes
  /// leads to the [tasks/{taskId}/leads/] subcollection.
  ///
  /// Uses Firestore batch writes for efficiency when inserting multiple leads.
  /// Handles network failures gracefully with proper error propagation.
  Future<String> createTaskWithLeads({
    String? predefinedTaskId,
    required String title,
    required String clientName,
    required String description,
    required String script,
    required double payout,
    required int totalSlots,
    required String priority,
    required String status,
    required String adminId,
    int totalLeads = 0, // Number of leads in this task
    List<Map<String, String>> leads = const [],
    String? campaignId, // optional: link to an existing client campaign
  }) async {
    try {
      final docRef = predefinedTaskId != null
          ? _firestore.collection('tasks').doc(predefinedTaskId)
          : _firestore.collection('tasks').doc();

      // Step 1: Create the task document
      // Use provided campaignId if linking to an existing client campaign,
      // otherwise default to the task's own ID (self-referential).
      final effectiveCampaignId = campaignId ?? docRef.id;
      await docRef.set({
        'title': title,
        'clientName': clientName,
        'description': description,
        'script': script,
        'payout': payout,
        'totalSlots': totalSlots,
        'remainingSlots': totalSlots,
        'priority': priority,
        'status': status,
        'totalLeads': totalLeads,
        'campaignId': effectiveCampaignId,
        'taskCode': await _generateUniqueTaskCode(),
        'requiresAdminApproval': true,
        'createdBy': adminId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final taskId = docRef.id;

      // Step 2: Batch-write leads if any
      if (leads.isNotEmpty) {
        await _batchUploadLeads(campaignId: effectiveCampaignId, taskId: taskId, leads: leads);
      } else if (campaignId != null && totalLeads > 0) {
        // Allocate existing campaign leads directly to this new task
        final snap = await _firestore.collection('campaign_leads')
            .where('campaignId', isEqualTo: campaignId)
            .where('status', isEqualTo: 'pending')
            .where('taskId', isNull: true)
            .limit(totalLeads)
            .get();
        final batch = _firestore.batch();
        for (var doc in snap.docs) {
          batch.update(doc.reference, {'taskId': taskId});
        }
        await batch.commit();
      }

      return taskId;
    } catch (e) {
      throw Exception('Failed to create task: $e');
    }
  }

  // ─── Private: Batch Upload Leads ────────────────────────────
  /// Uploads leads in batches of 500 (Firestore batch limit)
  /// to [tasks/{campaignId}/leads/] subcollection.
  Future<void> _batchUploadLeads({
    required String campaignId,
    required String taskId,
    required List<Map<String, String>> leads,
  }) async {
    const batchLimit = 500;
    final leadsCollection = _firestore.collection('campaign_leads');

    // Process in chunks of 500
    for (int i = 0; i < leads.length; i += batchLimit) {
      final batch = _firestore.batch();
      final chunk = leads.sublist(
        i,
        (i + batchLimit > leads.length) ? leads.length : i + batchLimit,
      );

      for (final lead in chunk) {
        final docRef = leadsCollection.doc(); // Auto-generate leadId
        batch.set(docRef, {
          'leadId': docRef.id,
          'campaignId': campaignId,
          'taskId': taskId,
          'name': lead['name'] ?? '',
          'phone': lead['phone'] ?? '',
          'email': lead['email'] ?? '',
          'city': lead['city'] ?? '',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    }
  }

  // ─── Worker: Claim Next Lead ──────────────────────────────────
  /// Assigns a pending lead from a specific campaign to the given [userId].
  /// Uses a transaction to prevent duplicate claims by multiple workers.
  Future<String?> claimNextLead({
    required String campaignId,
    required String userId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection('campaign_leads')
          .where('campaignId', isEqualTo: campaignId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null; // No leads available
      }

      final leadDocRef = querySnapshot.docs.first.reference;

      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(leadDocRef);

        if (!snapshot.exists) {
          return null;
        }

        final data = snapshot.data();
        if (data?['status'] != 'pending' || data?['assignedTo'] != null) {
          // Lead was already claimed by someone else in the meantime
          return null; 
        }

        transaction.update(leadDocRef, {
          'status': 'in_progress',
          'assignedTo': userId,
          'assignedAt': FieldValue.serverTimestamp(),
        });

        return leadDocRef.id;
      });
    } catch (e) {
      return null;
    }
  }
}
