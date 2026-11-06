import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/models/call_model.dart';

/// Phase 11 — CallModel unit tests.
///
/// Verifies JSON serialisation, computed properties, and edge cases
/// for the VOIP call data model.
void main() {
  group('CallModel', () {
    // ─── fromJson ──────────────────────────────────────────────
    group('fromJson', () {
      test('should parse a complete JSON map', () {
        final json = {
          'callId': 'call-123',
          'taskId': 'task-456',
          'assignmentId': 'asn-789',
          'userId': 'user-001',
          'leadId': 'lead-002',
          'customerPhone': '+919876543210',
          'exotelCallSid': 'CA_abc',
          'status': 'in_progress',
          'recordingUrl': 'https://api.twilio.com/recording.mp3',
          'duration': 120,
          'startedAt': '2026-03-06T08:00:00.000Z',
          'endedAt': '2026-03-06T08:02:00.000Z',
        };

        final model = CallModel.fromJson(json);

        expect(model.callId, 'call-123');
        expect(model.taskId, 'task-456');
        expect(model.assignmentId, 'asn-789');
        expect(model.userId, 'user-001');
        expect(model.leadId, 'lead-002');
        expect(model.customerPhone, '+919876543210');
        expect(model.exotelCallSid, 'CA_abc');
        expect(model.status, 'in_progress');
        expect(model.recordingUrl, 'https://api.twilio.com/recording.mp3');
        expect(model.duration, 120);
        expect(model.startedAt, isNotNull);
        expect(model.endedAt, isNotNull);
      });

      test('should handle missing optional fields gracefully', () {
        final json = <String, dynamic>{
          'callId': 'call-minimal',
          'taskId': 'task-1',
          'assignmentId': 'asn-1',
          'userId': 'uid-1',
          'leadId': 'lead-1',
          'customerPhone': '+911234567890',
        };

        final model = CallModel.fromJson(json);

        expect(model.callId, 'call-minimal');
        expect(model.exotelCallSid, isNull);
        expect(model.recordingUrl, isNull);
        expect(model.duration, 0);
        expect(model.status, 'initiated');
        expect(model.startedAt, isNull);
        expect(model.endedAt, isNull);
      });

      test('should handle completely empty map', () {
        final json = <String, dynamic>{};
        final model = CallModel.fromJson(json);

        expect(model.callId, '');
        expect(model.taskId, '');
        expect(model.customerPhone, '');
        expect(model.status, 'initiated');
        expect(model.duration, 0);
      });

      test('should handle null values for all fields', () {
        final json = <String, dynamic>{
          'callId': null,
          'taskId': null,
          'assignmentId': null,
          'userId': null,
          'leadId': null,
          'customerPhone': null,
          'exotelCallSid': null,
          'status': null,
          'recordingUrl': null,
          'duration': null,
          'startedAt': null,
          'endedAt': null,
        };

        final model = CallModel.fromJson(json);
        expect(model.callId, '');
        expect(model.status, 'initiated');
        expect(model.duration, 0);
      });

      test('should parse DateTime from string', () {
        final json = {
          'callId': 'c1',
          'taskId': 't1',
          'assignmentId': 'a1',
          'userId': 'u1',
          'leadId': 'l1',
          'customerPhone': '+91000',
          'startedAt': '2026-01-15T10:30:00.000Z',
        };

        final model = CallModel.fromJson(json);
        expect(model.startedAt, isA<DateTime>());
        expect(model.startedAt!.year, 2026);
        expect(model.startedAt!.month, 1);
        expect(model.startedAt!.day, 15);
      });

      test('should parse DateTime from DateTime object', () {
        final now = DateTime.now();
        final json = {
          'callId': 'c1',
          'taskId': 't1',
          'assignmentId': 'a1',
          'userId': 'u1',
          'leadId': 'l1',
          'customerPhone': '+91000',
          'startedAt': now,
        };

        final model = CallModel.fromJson(json);
        expect(model.startedAt, now);
      });
    });

    // ─── toJson ────────────────────────────────────────────────
    group('toJson', () {
      test('should produce valid JSON map', () {
        final model = CallModel(
          callId: 'call-1',
          taskId: 'task-1',
          assignmentId: 'asn-1',
          userId: 'user-1',
          leadId: 'lead-1',
          customerPhone: '+919876543210',
          exotelCallSid: 'CA_xyz',
          status: 'completed',
          recordingUrl: 'https://example.com/rec.mp3',
          duration: 65,
          startedAt: DateTime(2026, 3, 1, 10, 0),
          endedAt: DateTime(2026, 3, 1, 10, 1, 5),
        );

        final json = model.toJson();

        expect(json['callId'], 'call-1');
        expect(json['taskId'], 'task-1');
        expect(json['assignmentId'], 'asn-1');
        expect(json['userId'], 'user-1');
        expect(json['leadId'], 'lead-1');
        expect(json['customerPhone'], '+919876543210');
        expect(json['exotelCallSid'], 'CA_xyz');
        expect(json['status'], 'completed');
        expect(json['recordingUrl'], 'https://example.com/rec.mp3');
        expect(json['duration'], 65);
        expect(json['startedAt'], isA<String>());
        expect(json['endedAt'], isA<String>());
      });

      test('should handle null optional fields', () {
        const model = CallModel(
          callId: 'c1',
          taskId: 't1',
          assignmentId: 'a1',
          userId: 'u1',
          leadId: 'l1',
          customerPhone: '+91000',
        );

        final json = model.toJson();
        expect(json['exotelCallSid'], isNull);
        expect(json['recordingUrl'], isNull);
        expect(json['startedAt'], isNull);
        expect(json['endedAt'], isNull);
      });

      test('should roundtrip fromJson → toJson → fromJson', () {
        final original = CallModel(
          callId: 'rt-1',
          taskId: 'task-rt',
          assignmentId: 'asn-rt',
          userId: 'user-rt',
          leadId: 'lead-rt',
          customerPhone: '+919999999999',
          exotelCallSid: 'CA_roundtrip',
          status: 'completed',
          recordingUrl: 'https://rec.example.com/file.mp3',
          duration: 300,
          startedAt: DateTime(2026, 6, 15, 14, 30),
          endedAt: DateTime(2026, 6, 15, 14, 35),
        );

        final json = original.toJson();
        final restored = CallModel.fromJson(json);

        expect(restored.callId, original.callId);
        expect(restored.taskId, original.taskId);
        expect(restored.status, original.status);
        expect(restored.duration, original.duration);
        expect(restored.recordingUrl, original.recordingUrl);
      });
    });

    // ─── Computed Properties ───────────────────────────────────
    group('computed properties', () {
      test('isActive returns true for initiated, ringing, in_progress', () {
        for (final s in ['initiated', 'ringing', 'in_progress']) {
          final m = CallModel(
            callId: 'c',
            taskId: 't',
            assignmentId: 'a',
            userId: 'u',
            leadId: 'l',
            customerPhone: '+91',
            status: s,
          );
          expect(m.isActive, isTrue, reason: 'status=$s should be active');
        }
      });

      test('isActive returns false for completed, failed', () {
        for (final s in ['completed', 'failed']) {
          final m = CallModel(
            callId: 'c',
            taskId: 't',
            assignmentId: 'a',
            userId: 'u',
            leadId: 'l',
            customerPhone: '+91',
            status: s,
          );
          expect(m.isActive, isFalse, reason: 'status=$s should not be active');
        }
      });

      test('isCompleted returns true only for completed', () {
        const completed = CallModel(
          callId: 'c',
          taskId: 't',
          assignmentId: 'a',
          userId: 'u',
          leadId: 'l',
          customerPhone: '+91',
          status: 'completed',
        );
        const ringing = CallModel(
          callId: 'c',
          taskId: 't',
          assignmentId: 'a',
          userId: 'u',
          leadId: 'l',
          customerPhone: '+91',
          status: 'ringing',
        );

        expect(completed.isCompleted, isTrue);
        expect(ringing.isCompleted, isFalse);
      });

      test('isFailed returns true only for failed', () {
        const failed = CallModel(
          callId: 'c',
          taskId: 't',
          assignmentId: 'a',
          userId: 'u',
          leadId: 'l',
          customerPhone: '+91',
          status: 'failed',
        );
        const inProgress = CallModel(
          callId: 'c',
          taskId: 't',
          assignmentId: 'a',
          userId: 'u',
          leadId: 'l',
          customerPhone: '+91',
          status: 'in_progress',
        );

        expect(failed.isFailed, isTrue);
        expect(inProgress.isFailed, isFalse);
      });
    });

    // ─── copyWith ──────────────────────────────────────────────
    group('copyWith', () {
      test('should create a copy with updated status', () {
        const original = CallModel(
          callId: 'c1',
          taskId: 't1',
          assignmentId: 'a1',
          userId: 'u1',
          leadId: 'l1',
          customerPhone: '+91',
          status: 'initiated',
          duration: 0,
        );

        final updated = original.copyWith(status: 'in_progress', duration: 30);

        expect(updated.status, 'in_progress');
        expect(updated.duration, 30);
        expect(updated.callId, 'c1'); // unchanged
        expect(updated.taskId, 't1'); // unchanged
      });

      test('should preserve values when no arguments provided', () {
        const original = CallModel(
          callId: 'c2',
          taskId: 't2',
          assignmentId: 'a2',
          userId: 'u2',
          leadId: 'l2',
          customerPhone: '+91999',
          status: 'completed',
          duration: 120,
          recordingUrl: 'https://rec.com/file.mp3',
        );

        final copy = original.copyWith();

        expect(copy.callId, original.callId);
        expect(copy.status, original.status);
        expect(copy.duration, original.duration);
        expect(copy.recordingUrl, original.recordingUrl);
      });
    });
  });
}
