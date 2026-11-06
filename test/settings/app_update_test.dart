import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/services/app_update_service.dart';
import 'package:human_bpo/widgets/app_update_gate.dart';

void main() {
  test('live policy changes, optional dismissal and remote rollback', () async {
    final db = FakeFirebaseFirestore();
    final document = db.collection('app_config').doc('android_update');
    final service = AppUpdateService(
        firestore: db, loadBuild: () async => 6, supported: true);
    addTearDown(service.dispose);
    await service.init();
    expect(service.ready, isTrue);
    expect(service.requirement, AppUpdateRequirement.none);
    await document.set({'enabled': true, 'minimumBuild': 0, 'latestBuild': 8});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.requirement, AppUpdateRequirement.optional);
    service.dismissOptional();
    await service.refresh();
    expect(service.requirement, AppUpdateRequirement.none);
    await document.update({'minimumBuild': 7});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.requirement, AppUpdateRequirement.required);
    service.dismissOptional();
    expect(service.requirement, AppUpdateRequirement.required);
    await document.update({'enabled': false});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.requirement, AppUpdateRequirement.none);
    await document
        .update({'enabled': true, 'minimumBuild': 0, 'latestBuild': 9});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.requirement, AppUpdateRequirement.optional);
    await document.delete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.requirement, AppUpdateRequirement.none);
  });

  test('unsupported platforms and unavailable metadata do not block', () async {
    final unsupported = AppUpdateService(
        supported: false,
        loadBuild: () async => throw StateError('Must not be called'));
    await unsupported.init();
    expect(unsupported.ready, isTrue);
    expect(unsupported.requirement, AppUpdateRequirement.none);
    unsupported.dispose();
    final unavailable = AppUpdateService(
        supported: true,
        loadBuild: () async => throw StateError('Plugin unavailable'));
    await unavailable.init();
    expect(unavailable.ready, isTrue);
    expect(unavailable.requirement, AppUpdateRequirement.none);
    unavailable.dispose();
  });

  testWidgets(
      'mandatory gate blocks actions and survives store errors and back',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db
        .collection('app_config')
        .doc('android_update')
        .set({'enabled': true, 'minimumBuild': 7, 'latestBuild': 8});
    final service = AppUpdateService(
        firestore: db, loadBuild: () async => 6, supported: true);
    await service.init();
    addTearDown(service.dispose);
    var actions = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: AppUpdateGate(
            service: service, openStore: () async => false, child: child!),
      ),
      home: Scaffold(
          body: TextButton(
              onPressed: () => actions++, child: const Text('Worker action'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
    await tester.tap(find.text('Worker action'), warnIfMissed: false);
    expect(actions, 0);
    await tester.ensureVisible(find.text('Update now'));
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open Google Play. Please try again.'),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional gate opens store and Later restores the app',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('app_config')
        .doc('android_update')
        .set({'enabled': true, 'minimumBuild': 0, 'latestBuild': 8});
    final service = AppUpdateService(
        firestore: db, loadBuild: () async => 6, supported: true);
    await service.init();
    addTearDown(service.dispose);
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: AppUpdateGate(
            service: service,
            openStore: () async {
              opened++;
              return true;
            },
            child: const Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  test('build thresholds distinguish required, optional and current', () {
    final policy = AppUpdatePolicy.fromMap({
      'enabled': true,
      'minimumBuild': 6,
      'latestBuild': 8,
    });
    expect(policy.requirementFor(5), AppUpdateRequirement.required);
    expect(policy.requirementFor(6), AppUpdateRequirement.optional);
    expect(policy.requirementFor(7), AppUpdateRequirement.optional);
    expect(policy.requirementFor(8), AppUpdateRequirement.none);
    expect(policy.requirementFor(9), AppUpdateRequirement.none);
    expect(policy.requirementFor(0), AppUpdateRequirement.none);
  });

  test('missing, disabled and malformed policies cannot block users', () {
    for (final data in <Map<String, dynamic>?>[
      null,
      {},
      {'enabled': false, 'minimumBuild': 6, 'latestBuild': 8},
      {'enabled': true, 'minimumBuild': 9, 'latestBuild': 8},
      {'enabled': true, 'minimumBuild': -1, 'latestBuild': 8},
      {'enabled': true, 'minimumBuild': '6', 'latestBuild': 8},
      {'enabled': true, 'minimumBuild': 6, 'latestBuild': 8.5},
      {'enabled': true, 'minimumBuild': 6, 'latestBuild': 2100000001},
    ]) {
      expect(AppUpdatePolicy.fromMap(data).requirementFor(5),
          AppUpdateRequirement.none,
          reason: '$data');
    }
  });
}
