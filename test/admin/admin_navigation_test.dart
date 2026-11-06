import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:human_bpo/core/constants/app_colors.dart';
import 'package:human_bpo/routes.dart';
import 'package:human_bpo/screens/admin/admin_review_screen.dart';
import 'package:human_bpo/screens/auth/admin_role_select_screen.dart';
import 'package:human_bpo/screens/dashboard/admin_dashboard_screen.dart';

class _AdminUser extends Fake implements User {
  @override
  String get uid => 'admin-preview';

  @override
  String get email => 'admin@example.test';

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
}

class _AdminAuth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => _AdminUser();
}

Future<void> _pumpAdmin(
  WidgetTester tester, {
  String role = 'super_admin',
  String? activeRole = 'super_admin',
  bool picker = false,
  Size viewport = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('admin-preview').set({
    'role': role,
    'name': 'Private owner name',
  });
  final auth = _AdminAuth();
  await tester.pumpWidget(RepaintBoundary(
    key: const ValueKey('admin-preview'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: const bool.fromEnvironment('CAPTURE_ADMIN_PREVIEW')
            ? 'AdminPreview'
            : null,
        scaffoldBackgroundColor:
            brightness == Brightness.light ? AppColors.background : null,
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: brightness,
            surface: brightness == Brightness.light ? AppColors.surface : null,
            onSurface:
                brightness == Brightness.light ? AppColors.textDark : null,
            outlineVariant:
                brightness == Brightness.light ? AppColors.border : null),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: picker
          ? AdminRoleSelectScreen(auth: auth, firestore: firestore)
          : AdminDashboardScreen(
              auth: auth, firestore: firestore, activeRole: activeRole),
      routes: {
        for (final route in [
          AppRoutes.adminReview,
          AppRoutes.adminKyc,
          AppRoutes.adminWithdrawals,
          AppRoutes.adminUsers,
          AppRoutes.adminTasks,
          AppRoutes.adminSettings,
          AppRoutes.adminSupport,
          AppRoutes.adminSupportChats,
          AppRoutes.adminMail
        ])
          route: (_) => Scaffold(body: Text('Destination: $route')),
      },
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('review decisions display their date instead of submitted or updated time', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('admin-preview').set({'role': 'task_review_admin'});
    for (final status in ['approved', 'rejected']) {
      await firestore.collection('task_submissions').doc(status).set({
        'status': status, 'workerName': 'Example Employee', 'userId': 'employee',
        'submittedAt': DateTime(2026, 9, 20, 9),
        'reviewedAt': DateTime(2026, 9, 23, 14, 30),
        'updatedAt': DateTime(2026, 9, 24, 16),
      });
    }
    await tester.pumpWidget(MaterialApp(home: AdminReviewScreen(firestore: firestore, auth: _AdminAuth())));
    await tester.pump(const Duration(seconds: 2));
    for (final label in ['Approved', 'Rejected']) {
      await tester.tap(find.widgetWithText(Tab, label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('23 Sep 2026, 2:30 PM'), findsOneWidget,
          reason: label);
      expect(find.textContaining('24 Sep 2026, 4:00 PM'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('review queue searches beyond 20 and keeps undated submissions', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('admin-preview').set({'role': 'task_review_admin'});
    await firestore.collection('users').doc('employee-old').set({'systemWorkerId': 'SHR-9001', 'name': 'Older Employee'});
    for (var index = 0; index < 25; index++) {
      await firestore.collection('task_submissions').doc('review-$index').set({
        'status': 'pending_admin_review',
        'userId': index == 0 ? 'employee-old' : 'employee-new',
        'workerId': index == 0 ? 'SHR-1001' : 'SHR-2002',
        'workerName': 'Employee $index',
        if (index == 1) 'systemWorkerId': 'SHR-4004',
        if (index == 0) 'leadPhone': '9000001234',
        'submittedAt': DateTime(2026, 9, 23, 12, index),
        'result': 'Interested',
      });
    }
    await firestore.collection('task_submissions').doc('undated-review').set({
      'status': 'pending_admin_review', 'userId': 'employee-undated', 'employeeId': 'SHR-3003',
    });
    await firestore.collection('task_submissions').doc('already-approved').set({
      'status': 'approved', 'userId': 'employee-old', 'workerId': 'SHR-1001',
    });
    await tester.pumpWidget(MaterialApp(home: AdminReviewScreen(firestore: firestore, auth: _AdminAuth())));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('26 of 26 submissions'), findsOneWidget);
    expect(find.text('Approve'), findsWidgets);
    expect(find.text('Approve & Pay'), findsNothing);
    for (final query in ['  shr-1001  ', 'shr-9001', 'Older Employee', 'SHR-3003', 'shr-4004', '9000001234']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1 of 26 submissions'), findsOneWidget, reason: query);
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(find.byType(TextField), 'shr-2002');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('24 of 26 submissions'), findsOneWidget);
    await tester.tap(find.text('Not Interested').first);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0 of 26 submissions'), findsOneWidget);
    await tester.tap(find.text('All').first);
    await tester.enterText(find.byType(TextField), 'no-such-employee');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('No matching submissions'), findsOneWidget);
    expect(find.text('All caught up! 🎉'), findsNothing);
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('26 of 26 submissions'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Undated (1)').last);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 of 26 submissions'), findsOneWidget);
    expect(find.text('Undated'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('review dates filter live results and survive the last review leaving a day', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('users').doc('admin-preview').set({'role': 'task_review_admin'});
    for (final day in [23, 24]) {
      await firestore.collection('task_submissions').doc('day-$day').set({
        'status': 'pending_admin_review', 'userId': 'employee-$day', 'workerId': 'SHR-$day',
        'submittedAt': DateTime(2026, 9, day, 12),
      });
    }
    await tester.pumpWidget(MaterialApp(home: AdminReviewScreen(firestore: firestore, auth: _AdminAuth())));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2 of 2 submissions'), findsOneWidget);
    expect(find.text('24 Sep 2026').first.hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Newest first'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('23 Sep 2026').first.hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Oldest first'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('23 Sep 2026 (1)').last);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 of 2 submissions'), findsOneWidget);
    await firestore.collection('task_submissions').doc('day-23').update({'status': 'approved'});
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0 of 1 submissions'), findsOneWidget);
    expect(find.text('No matching submissions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 of 1 submissions'), findsOneWidget);
    await tester.tap(find.byTooltip('Newest first'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Oldest first'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('retry row follows live lead and task changes', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final lead = firestore.collection('campaign_leads').doc('retry-lead');
    final task = firestore.collection('tasks').doc('retry-task');
    final originalDue = DateTime.now().subtract(const Duration(minutes: 2));
    await task.set({
      'status': 'active', 'distributionMode': 'individual', 'remainingSlots': 0,
    });
    await lead.set({
      'taskId': task.id, 'status': 'requeue_pending', 'requeueAfter': originalDue,
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: RequeueScheduleRow(
        leadId: lead.id, taskId: task.id,
        requeueAfter: originalDue, firestore: firestore,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Retry due - waiting for scheduler'), findsOneWidget);

    await lead.update({'status': 'pending'});
    await task.update({'status': 'pending_team_leader'});
    await tester.pumpAndSettle();
    expect(find.text('Returned - Awaiting Team Leader'), findsOneWidget);
    expect(find.textContaining('waiting for scheduler'), findsNothing);
    expect(find.textContaining('Marketplace'), findsNothing);

    await task.update({
      'status': 'active', 'distributionMode': 'marketplace', 'remainingSlots': 1,
    });
    await tester.pumpAndSettle();
    expect(find.text('Returned - Available in Marketplace'), findsOneWidget);
    await task.update({'distributionMode': 'unknown'});
    await tester.pumpAndSettle();
    expect(find.text('Returned - location unavailable'), findsOneWidget);
    expect(find.textContaining('Marketplace'), findsNothing);
    await task.update({'distributionMode': 'individual'});
    await tester.pumpAndSettle();
    expect(find.text('Returned - Individual task'), findsOneWidget);
    await task.update({'distributionMode': 'marketplace'});
    await task.update({'remainingSlots': 0});
    await tester.pumpAndSettle();
    expect(find.text('Returned - Waiting for an available slot'), findsOneWidget);
    await task.update({'status': 'paused'});
    await tester.pumpAndSettle();
    expect(find.text('Returned - Task not available'), findsOneWidget);
    await task.delete();
    await tester.pumpAndSettle();
    expect(find.text('Returned - location unavailable'), findsOneWidget);

    for (final entry in {
      'assigned': 'Reassigned - Awaiting work',
      'in_progress': 'Reassigned - In progress',
      'completed': 'Retry completed - Awaiting review',
      'approved': 'Retry approved',
      'unreachable': 'Closed - Retry limit reached',
      'wrong_number': 'Closed - Wrong number',
      'rejected': 'Closed - Rejected',
    }.entries) {
      await lead.update({'status': entry.key});
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('waiting for scheduler'), findsNothing);
    }

    await lead.update({
      'status': 'requeue_pending',
      'requeueAfter': DateTime.now().add(const Duration(hours: 1)),
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry scheduled - '), findsOneWidget);
    expect(find.textContaining('waiting for scheduler'), findsNothing);
    await lead.delete();
    await tester.pumpAndSettle();
    expect(find.text('Lead status unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry row handles missing identity and subscription changes',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('tasks').doc('task').set({
      'status': 'pending_team_leader', 'distributionMode': 'individual',
    });
    await firestore.collection('campaign_leads').doc('lead').set({
      'taskId': 'task', 'status': 'pending',
    });
    Future<void> showRow(String leadId, String taskId) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SizedBox(width: 280, child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: RequeueScheduleRow(
            leadId: leadId, taskId: taskId,
            requeueAfter: null, firestore: firestore,
          ),
        )),
      )));
      await tester.pumpAndSettle();
    }

    await showRow('', 'task');
    expect(find.text('Lead status unavailable'), findsOneWidget);
    await showRow('lead', 'task');
    expect(find.text('Returned - Awaiting Team Leader'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await showRow('lead', 'different-task');
    expect(find.text('Lead status unavailable'), findsOneWidget);
    await showRow('invalid/id', 'task');
    expect(find.text('Lead status unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  if (const bool.fromEnvironment('CAPTURE_ADMIN_PREVIEW')) {
    setUpAll(() async {
      final fontFile = File(const String.fromEnvironment('ADMIN_PREVIEW_FONT'));
      final font = FontLoader('AdminPreview')
        ..addFont(
            Future.value(ByteData.sublistView(await fontFile.readAsBytes())));
      await font.load();
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final family in manifest) {
        final loader = FontLoader(family['family'] as String);
        for (final font in family['fonts'] as List) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
    });
    for (final picker in [true, false]) {
      for (final viewport in [const Size(390, 844), const Size(1280, 900)]) {
        testWidgets('capture ${picker ? 'roles' : 'dashboard'} $viewport',
            (tester) async {
          await _pumpAdmin(tester, picker: picker, viewport: viewport);
          await expectLater(
              find.byKey(const ValueKey('admin-preview')),
              matchesGoldenFile(
                  '../../build/admin-previews/${picker ? 'roles' : 'dashboard'}-${viewport.width.toInt()}.png'));
        });
      }
    }
  }

  final destinations = {
    'Review Task Submissions': AppRoutes.adminReview,
    'Review KYC Submissions': AppRoutes.adminKyc,
    'Process Withdrawals': AppRoutes.adminWithdrawals,
    'Manage Users': AppRoutes.adminUsers,
    'Manage Tasks': AppRoutes.adminTasks,
    'Platform Settings': AppRoutes.adminSettings,
    'Support Tickets': AppRoutes.adminSupport,
    'Live Chats': AppRoutes.adminSupportChats,
    'Employee Mail': AppRoutes.adminMail,
  };

  testWidgets('Super Admin keeps active routes without deprecated creation',
      (tester) async {
    await _pumpAdmin(tester);
    expect(find.text('Sherize'), findsOneWidget);
    expect(find.textContaining('Private owner'), findsNothing);
    expect(find.text('Create New Task'), findsNothing);
    expect(find.text('New Task'), findsNothing);
    expect(tester.getTopLeft(find.text('Reviews & payouts')).dy,
        lessThan(tester.getTopLeft(find.text('Review overview')).dy));
    for (final destination in destinations.entries) {
      await tester.ensureVisible(find.text(destination.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(destination.key));
      await tester.pumpAndSettle();
      expect(find.text('Destination: ${destination.value}'), findsOneWidget);
      Navigator.of(
              tester.element(find.text('Destination: ${destination.value}')))
          .pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('role picker opens the Super Admin workspace', (tester) async {
    await _pumpAdmin(tester, picker: true);
    expect(find.text('Select workspace'), findsOneWidget);
    await tester.tap(find.text('Super Admin'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('adminWorkspace:admin-preview'), 'super_admin');
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    expect(find.text('Manage Users'), findsOneWidget);
    expect(find.text('Create New Task'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('support admin cannot select Super Admin', (tester) async {
    await _pumpAdmin(tester, role: 'support_admin', picker: true);
    await tester.tap(find.text('Super Admin'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsNothing);
    await tester.ensureVisible(find.text('Support Admin'));
    await tester.tap(find.text('Support Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Support Tickets'), findsOneWidget);
    expect(find.text('Manage Users'), findsNothing);
    expect(find.text('Process Withdrawals'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Super Admin scoped to support sees only support tools',
      (tester) async {
    await _pumpAdmin(tester, activeRole: 'support_admin');
    expect(find.text('Support Tickets'), findsOneWidget);
    expect(find.text('Employee Mail'), findsOneWidget);
    expect(find.text('Manage Users'), findsNothing);
    expect(find.text('Review Task Submissions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [const Size(320, 640), const Size(1280, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets('admin options fit $viewport at 2x text in $brightness',
          (tester) async {
        await _pumpAdmin(tester,
            viewport: viewport, textScale: 2, brightness: brightness);
        expect(tester.takeException(), isNull);
        for (final destination in destinations.keys) {
          await tester.ensureVisible(find.text(destination));
          await tester.pumpAndSettle();
          expect(find.text(destination).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('Pending Payouts'));
        await tester.pumpAndSettle();
        expect(find.text('Pending Payouts').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('role picker fits $viewport at 2x text in $brightness',
          (tester) async {
        await _pumpAdmin(tester,
            picker: true,
            viewport: viewport,
            textScale: 2,
            brightness: brightness);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Support Admin'));
        await tester.pumpAndSettle();
        expect(find.text('Support Admin').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
