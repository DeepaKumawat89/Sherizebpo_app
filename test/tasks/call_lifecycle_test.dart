import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/core/utils/call_lifecycle.dart';
import 'package:human_bpo/screens/tasks/task_execution_screen.dart';

void main() {
  group('QA manual-call opt-in', () {
    test('only the two approved QA task IDs follow the debug define', () {
      const enabled = bool.fromEnvironment('QA_SIMULATE_MANUAL_CALLS');
      for (final taskId in ['CLIE-QARE-2177', 'CLIE-QARE-2615']) {
        expect(TaskExecutionScreen(taskId: taskId).simulateQaManualCall, enabled);
      }
    });

    test('does not simulate missing or unrelated task IDs', () {
      for (final taskId in [null, '', 'CLIE-QARE-2177-other', 'ordinary-task']) {
        expect(TaskExecutionScreen(taskId: taskId).simulateQaManualCall, isFalse);
      }
    });
  });

  group('CallLifecycle', () {
    test('does not accept a call before Exotel assigns a SID', () {
      expect(
        CallLifecycle.wasAccepted({
          'status': 'starting',
          'exotelCallSid': null,
        }),
        isFalse,
      );
    });

    test('keeps an accepted completed call eligible for submission', () {
      final call = {
        'status': 'completed',
        'exotelCallSid': 'a-leg-sid',
        'duration': 42,
      };

      expect(CallLifecycle.wasAccepted(call), isTrue);
      expect(CallLifecycle.isTerminal(call), isTrue);
      expect(CallLifecycle.duration(call), 42);
    });

    test('distinguishes a provider rejection from an accepted failed call', () {
      expect(
        CallLifecycle.wasAccepted({'status': 'failed'}),
        isFalse,
      );
      expect(
        CallLifecycle.wasAccepted({
          'status': 'failed',
          'exotelCallSid': 'failed-call-sid',
        }),
        isTrue,
      );
    });
  });
}