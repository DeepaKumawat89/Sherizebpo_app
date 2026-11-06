import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/core/constants/app_colors.dart';
import 'package:human_bpo/routes.dart';
import 'package:human_bpo/screens/jobs/public_jobs_screen.dart';

class _RetryFirestore extends Fake implements FirebaseFirestore {
  _RetryFirestore(QuerySnapshot<Map<String, dynamic>> snapshot)
      : openings = _RetryCollection(snapshot);

  final _RetryCollection openings;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, 'job_postings');
    return openings;
  }
}

// ignore: subtype_of_sealed_class, must_be_immutable
class _RetryCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _RetryCollection(this.snapshot);

  final QuerySnapshot<Map<String, dynamic>> snapshot;
  int subscriptions = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      expect(invocation.positionalArguments, ['status']);
      expect(invocation.namedArguments[#isEqualTo], 'open');
      return this;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    subscriptions++;
    return subscriptions == 1
        ? Stream.error(
            FirebaseException(plugin: 'firestore', code: 'unavailable'))
        : Stream.value(snapshot);
  }
}

Future<void> _pumpPortal(
  WidgetTester tester,
  FirebaseFirestore firestore, {
  Size viewport = const Size(390, 844),
  double textScale = 1,
  double keyboardInset = 0,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary, brightness: brightness),
      outlinedButtonTheme: const OutlinedButtonThemeData(
          style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(double.infinity, 52)))),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: child!,
    ),
    home: PublicJobsScreen(firestore: firestore),
    routes: {
      AppRoutes.login: (_) => const Scaffold(body: Text('Shared login')),
    },
  ));
}

Future<void> _addOpening(FakeFirebaseFirestore firestore) =>
    firestore.collection('job_postings').doc('support').set({
      'status': 'open',
      'title': 'Customer Support Associate',
      'location':
          'Hyderabad, Telangana, with remote opportunities across India',
      'payNote': 'Monthly salary plus performance incentives after training',
      'description':
          'Support customers and keep their service requests up to date.',
    });

void main() {
  testWidgets('single header Login opens the shared login route',
      (tester) async {
    await _pumpPortal(tester, FakeFirebaseFirestore());
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Employee Login'), findsNothing);
    expect(find.text('Login with mobile number'), findsNothing);
    expect(tester.getTopLeft(find.text('Login')).dy,
        lessThan(tester.getTopLeft(find.text('Open positions')).dy));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Shared login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and empty openings have distinct states',
      (tester) async {
    await _pumpPortal(tester, FakeFirebaseFirestore());
    expect(find.text('Loading openings...'), findsOneWidget);
    expect(find.text('No open positions right now'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('0 roles available'), findsOneWidget);
    expect(find.text('No open positions right now'), findsOneWidget);
    expect(find.text('Apply now'), findsNothing);
  });

  testWidgets('only open jobs appear and live updates remove closed jobs',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _addOpening(firestore);
    await firestore.collection('job_postings').doc('closed').set({
      'status': 'closed',
      'title': 'Closed position',
    });
    await _pumpPortal(tester, firestore);
    await tester.pumpAndSettle();
    expect(find.text('Customer Support Associate'), findsOneWidget);
    expect(find.text('Closed position'), findsNothing);
    expect(find.text('1 role available'), findsOneWidget);

    await firestore.collection('job_postings').doc('support').update({
      'status': 'closed',
    });
    await tester.pumpAndSettle();
    expect(find.text('Customer Support Associate'), findsNothing);
    expect(find.text('No open positions right now'), findsOneWidget);
  });

  testWidgets('query errors stay distinct from empty state and Retry recovers',
      (tester) async {
    final data = FakeFirebaseFirestore();
    await _addOpening(data);
    final firestore =
        _RetryFirestore(await data.collection('job_postings').get());
    await _pumpPortal(tester, firestore);
    await tester.pumpAndSettle();
    expect(find.text('Unable to load openings'), findsOneWidget);
    expect(find.text('No open positions right now'), findsNothing);
    expect(find.text('0 roles available'), findsNothing);

    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();
    expect(firestore.openings.subscriptions, 1);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(firestore.openings.subscriptions, 2);
    expect(find.text('Unable to load openings'), findsNothing);
    expect(find.text('Customer Support Associate'), findsOneWidget);
    expect(find.text('1 role available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in [const Size(320, 640), const Size(1280, 900)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('job details fit $viewport with text scale $textScale',
          (tester) async {
        final firestore = FakeFirebaseFirestore();
        await _addOpening(firestore);
        await _pumpPortal(tester, firestore,
            viewport: viewport, textScale: textScale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ListView)).width,
            lessThanOrEqualTo(840));
        await tester.scrollUntilVisible(find.text('Apply now'), 180,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(find.text('Login').hitTestable(), findsOneWidget);
        expect(find.text('Apply now').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('application remains scrollable above keyboard with large text',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _addOpening(firestore);
    await _pumpPortal(tester, firestore,
        viewport: const Size(320, 640), textScale: 1.5, keyboardInset: 260);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Apply now'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply now'));
    await tester.pumpAndSettle();
    expect(find.text('Apply — Customer Support Associate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final submit = find.text('Submit Application');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(submit).dy, lessThanOrEqualTo(380));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid 10-digit number'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('job cards and application sheet follow dark theme',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _addOpening(firestore);
    await _pumpPortal(tester, firestore, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    final colors =
        Theme.of(tester.element(find.text('Open positions'))).colorScheme;
    final card = tester.widget<Container>(find
        .ancestor(
            of: find.text('Customer Support Associate'),
            matching: find.byType(Container))
        .first);
    expect((card.decoration! as BoxDecoration).color, colors.surface);
    await tester.tap(find.text('Apply now'));
    await tester.pumpAndSettle();
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        colors.surface);
    expect(tester.takeException(), isNull);
  });
}
