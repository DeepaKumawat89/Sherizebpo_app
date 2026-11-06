import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:human_bpo/services/platform_settings_service.dart';
import 'package:human_bpo/services/task_service.dart';
import 'package:human_bpo/widgets/my_task_card.dart';
import 'package:human_bpo/screens/tasks/task_history_screen.dart';

class _HistoryUser extends Fake implements User {
  @override
  String get uid => 'employee';
}

class _HistoryAuth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => _HistoryUser();
}

class _TestFunctions extends Fake implements FirebaseFunctions {
  final callable = _TestCallable();
  String? name;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return callable;
  }
}

class _TestCallable extends Fake implements HttpsCallable {
  dynamic parameters;
  FirebaseFunctionsException? error;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    this.parameters = parameters;
    if (error != null) throw error!;
    return _TestResult<T>({'acceptedCount': 1, 'assignmentId': 'attempt-1'} as T);
  }
}

class _TestResult<T> extends Fake implements HttpsCallableResult<T> {
  _TestResult(this.data);
  @override
  final T data;
}

void main() {
  testWidgets('history keeps undated and revoked assignments without fake dates', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final settings = PlatformSettingsService();
    addTearDown(settings.dispose);
    await firestore.collection('task_assignments').doc('undated').set({
      'userId': 'employee', 'status': 'completed', 'title': 'Undated task',
    });
    await firestore.collection('task_assignments').doc('revoked').set({
      'userId': 'employee', 'status': 'revoked', 'title': 'Revoked task',
      'assignedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 9)),
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(home: TaskHistoryScreen(auth: _HistoryAuth(), firestore: firestore)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Date not recorded'), findsOneWidget);
    expect(find.text('20 Sep 2026'), findsOneWidget);
    expect(find.textContaining('2000'), findsNothing);
    await tester.tap(find.text('Date not recorded'));
    await tester.pumpAndSettle();
    expect(find.text('Undated task'), findsOneWidget);
    expect(find.text('Completed: Not recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('assignment cards show event dates and never invent missing dates', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = PlatformSettingsService();
    addTearDown(settings.dispose);
    for (final status in ['completed', 'revoked', 'rejected']) {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(
          child: MyTaskCard(key: ValueKey(status), assignmentId: 'attempt', data: {
            'title': 'Example assignment', 'status': status,
            'assignedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 9)),
            'startedAt': Timestamp.fromDate(DateTime(2026, 9, 20, 10)),
            'completedAt': Timestamp.fromDate(DateTime(2026, 9, 21, 11)),
            'revokedAt': Timestamp.fromDate(DateTime(2026, 9, 22, 12)),
            'updatedAt': Timestamp.fromDate(DateTime(2026, 9, 24, 14)),
          }),
        ))),
      ));
      expect(find.textContaining('Assigned: 20 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Started: 20 Sep 2026'), findsOneWidget);
      expect(find.textContaining('Last updated: 24 Sep 2026'), findsOneWidget);
      if (status == 'completed') expect(find.textContaining('Completed: 21 Sep 2026'), findsOneWidget);
      if (status == 'revoked') expect(find.textContaining('Revoked: 22 Sep 2026'), findsOneWidget);
      if (status == 'rejected') expect(find.text('Rejected: Not recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Acceptance sends only task identity to the authoritative callable', () async {
    final functions = _TestFunctions();
    final result = await TaskService(functions: functions).acceptMarketplaceTask(taskId: 'task-1');
    expect(functions.name, 'acceptMarketplaceTask');
    expect(functions.callable.parameters, {'taskId': 'task-1'});
    expect(result, 1);
  });

  for (final code in ['already-exists', 'resource-exhausted', 'permission-denied', 'failed-precondition', 'unavailable']) {
    test('Acceptance propagates $code without a direct-write fallback', () async {
      final functions = _TestFunctions();
      final error = FirebaseFunctionsException(code: code, message: 'Server rejected acceptance');
      functions.callable.error = error;
      await expectLater(TaskService(functions: functions).acceptMarketplaceTask(taskId: 'task-1'), throwsA(same(error)));
    });
  }
}
