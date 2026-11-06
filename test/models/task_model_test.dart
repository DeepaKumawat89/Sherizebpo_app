import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/models/task_model.dart';

/// Phase 3 — TaskModel unit tests.
///
/// Verifies JSON serialisation, computed properties, and edge cases.
void main() {
  group('TaskModel', () {
    // ─── fromJson ──────────────────────────────────────────────
    group('fromJson', () {
      test('should parse a complete JSON map', () {
        final json = {
          'id': 'task-001',
          'company': 'Acme Corp',
          'type': 'call',
          'title': 'Customer Outreach Campaign',
          'description': 'Cold calling for new leads',
          'payout_per_unit': 15.0,
          'payout_unit': 'call',
          'total_volume': 100,
          'completed_volume': 25,
          'status': 'in_progress',
          'urgency': 'urgent',
          'deadline': '2026-04-01T23:59:59.000Z',
          'created_at': '2026-03-01T10:00:00.000Z',
        };

        final model = TaskModel.fromJson(json);

        expect(model.id, 'task-001');
        expect(model.company, 'Acme Corp');
        expect(model.type, 'call');
        expect(model.title, 'Customer Outreach Campaign');
        expect(model.description, 'Cold calling for new leads');
        expect(model.payoutPerUnit, 15.0);
        expect(model.payoutUnit, 'call');
        expect(model.totalVolume, 100);
        expect(model.completedVolume, 25);
        expect(model.status, 'in_progress');
        expect(model.urgency, 'urgent');
        expect(model.deadline.year, 2026);
        expect(model.createdAt.month, 3);
      });

      test('should use default values for optional fields', () {
        final json = {
          'id': 'task-002',
          'company': 'Beta Inc',
          'type': 'email',
          'title': 'Email Campaign',
          'payout_per_unit': 5,
          'payout_unit': 'msg',
          'total_volume': 200,
          'deadline': '2026-05-01T00:00:00.000Z',
          'created_at': '2026-03-15T09:00:00.000Z',
        };

        final model = TaskModel.fromJson(json);

        expect(model.description, '');
        expect(model.completedVolume, 0);
        expect(model.status, 'available');
        expect(model.urgency, isNull);
      });

      test('should handle integer payout_per_unit', () {
        final json = {
          'id': 'task-003',
          'company': 'Gamma Ltd',
          'type': 'chat',
          'title': 'Chat Support',
          'payout_per_unit': 10, // int not double
          'payout_unit': 'ticket',
          'total_volume': 50,
          'deadline': '2026-06-01T00:00:00.000Z',
          'created_at': '2026-03-20T12:00:00.000Z',
        };

        final model = TaskModel.fromJson(json);
        expect(model.payoutPerUnit, 10.0);
        expect(model.payoutPerUnit, isA<double>());
      });
    });

    // ─── toJson ────────────────────────────────────────────────
    group('toJson', () {
      test('should produce valid JSON map', () {
        final model = TaskModel(
          id: 'task-100',
          company: 'Delta Corp',
          type: 'call',
          title: 'Survey Campaign',
          description: 'Phone survey for product feedback',
          payoutPerUnit: 20.0,
          payoutUnit: 'call',
          totalVolume: 500,
          completedVolume: 100,
          status: 'in_progress',
          urgency: 'urgent',
          deadline: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 3, 1),
        );

        final json = model.toJson();

        expect(json['id'], 'task-100');
        expect(json['company'], 'Delta Corp');
        expect(json['payout_per_unit'], 20.0);
        expect(json['total_volume'], 500);
        expect(json['completed_volume'], 100);
        expect(json['urgency'], 'urgent');
      });

      test('should roundtrip fromJson → toJson → fromJson', () {
        final original = TaskModel(
          id: 'rt-task',
          company: 'Roundtrip Inc',
          type: 'call',
          title: 'RT Campaign',
          payoutPerUnit: 12.5,
          payoutUnit: 'call',
          totalVolume: 75,
          completedVolume: 30,
          deadline: DateTime(2026, 8, 15),
          createdAt: DateTime(2026, 3, 10),
        );

        final json = original.toJson();
        final restored = TaskModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.payoutPerUnit, original.payoutPerUnit);
        expect(restored.totalVolume, original.totalVolume);
        expect(restored.completedVolume, original.completedVolume);
      });
    });

    // ─── Computed Properties ───────────────────────────────────
    group('computed properties', () {
      test('progress returns correct fraction', () {
        final model = TaskModel(
          id: 't',
          company: 'c',
          type: 'call',
          title: 'T',
          payoutPerUnit: 10,
          payoutUnit: 'call',
          totalVolume: 200,
          completedVolume: 50,
          deadline: DateTime.now(),
          createdAt: DateTime.now(),
        );

        expect(model.progress, closeTo(0.25, 0.001));
      });

      test('progress returns 0 when totalVolume is 0', () {
        final model = TaskModel(
          id: 't',
          company: 'c',
          type: 'call',
          title: 'T',
          payoutPerUnit: 10,
          payoutUnit: 'call',
          totalVolume: 0,
          completedVolume: 0,
          deadline: DateTime.now(),
          createdAt: DateTime.now(),
        );

        expect(model.progress, 0.0);
      });

      test('progress returns 1.0 when fully complete', () {
        final model = TaskModel(
          id: 't',
          company: 'c',
          type: 'call',
          title: 'T',
          payoutPerUnit: 10,
          payoutUnit: 'call',
          totalVolume: 100,
          completedVolume: 100,
          deadline: DateTime.now(),
          createdAt: DateTime.now(),
        );

        expect(model.progress, 1.0);
      });

      test('isUrgent returns true when urgency is "urgent"', () {
        final urgent = TaskModel(
          id: 't',
          company: 'c',
          type: 'call',
          title: 'T',
          payoutPerUnit: 10,
          payoutUnit: 'call',
          totalVolume: 10,
          urgency: 'urgent',
          deadline: DateTime.now(),
          createdAt: DateTime.now(),
        );
        final normal = TaskModel(
          id: 't',
          company: 'c',
          type: 'call',
          title: 'T',
          payoutPerUnit: 10,
          payoutUnit: 'call',
          totalVolume: 10,
          deadline: DateTime.now(),
          createdAt: DateTime.now(),
        );

        expect(urgent.isUrgent, isTrue);
        expect(normal.isUrgent, isFalse);
      });
    });
  });
}
