import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/core/constants/constants.dart';
import 'package:human_bpo/routes.dart';
import 'package:human_bpo/screens/profile/profile_screen.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double textScale = 1,
    bool dark = false,
    String name = 'Ananya Reddy',
    String employeeId = 'SHR10248',
    String status = 'Verified',
    String image = '',
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: dark ? AppColors.primaryLight : AppColors.primary,
      surface: dark ? AppColors.secondaryLight : AppColors.surface,
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        fontFamily: 'ProfilePreview',
        cardColor: dark ? AppColors.secondaryLight : AppColors.surface,
        dividerColor: dark
            ? Colors.white.withValues(alpha: 0.05)
            : AppColors.border.withValues(alpha: 0.5),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      routes: {
        AppRoutes.editProfile: (_) =>
            const Scaffold(body: Text('Edit destination'))
      },
      home: Scaffold(
          body: SingleChildScrollView(
              child: RepaintBoundary(
        key: const ValueKey('profile-preview'),
        child: ProfileHeader(
          userName: name,
          employeeId: employeeId,
          initial: name.characters.first,
          profileImageUrl: image,
          kycStatus: status,
          kycColor: status == 'Verified'
              ? AppColors.success
              : status == 'Rejected'
                  ? AppColors.error
                  : status == 'Under Review'
                      ? AppColors.info
                      : AppColors.warning,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('compact identity, copy feedback and edit navigation',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester);
    expect(find.text('Ananya Reddy'), findsOneWidget);
    expect(find.text('Employee ID'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(tester.getSize(find.byType(ProfileHeader)).height, lessThan(260));
    for (final label in ['Copy Employee ID', 'Edit profile']) {
      final size = tester.getSize(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == label));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Copy Employee ID'));
    await tester.pumpAndSettle();
    expect(copied, 'SHR10248');
    expect(find.text('Employee ID copied'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard failure reports an error without navigating',
      (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester);
    await tester.tap(find.byTooltip('Copy Employee ID'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy Employee ID. Try again.'), findsOneWidget);
    expect(find.byType(ProfileHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back returns to the preceding route', (tester) async {
    await mount(tester);
    final context = tester.element(find.byType(ProfileHeader));
    final header = tester.widget<ProfileHeader>(find.byType(ProfileHeader));
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: header)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byType(ProfileHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing ID disables copy and broken photo retains initial',
      (tester) async {
    await mount(tester,
        employeeId: '', image: 'https://example.invalid/avatar.png');
    expect(find.text('Not assigned'), findsOneWidget);
    final copy = tester.widget<IconButton>(find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Copy Employee ID',
    ));
    expect(copy.onPressed, isNull);
    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final status in [
      'KYC Pending',
      'Under Review',
      'Verified',
      'Rejected'
    ]) {
      testWidgets('$status fits at 320px with large text, dark=$dark',
          (tester) async {
        await mount(tester,
            width: 320,
            textScale: 2,
            dark: dark,
            status: status,
            name: 'Ananya Venkatalakshmi Reddy',
            employeeId: 'SHERIZE12345678901234567890');
        expect(find.text(status), findsOneWidget);
        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(ProfileHeader));
        for (final label in ['Copy Employee ID', 'Edit profile']) {
          final rect = tester.getRect(find.byTooltip(label));
          expect(rect.left, greaterThanOrEqualTo(header.left));
          expect(rect.right, lessThanOrEqualTo(header.right));
        }
      });
    }
  }

  if (const bool.fromEnvironment('CAPTURE_PROFILE_PREVIEW')) {
    setUpAll(() async {
      final fontFile =
          File(const String.fromEnvironment('PROFILE_PREVIEW_FONT'));
      final font = FontLoader('ProfilePreview')
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
    for (final dark in [false, true]) {
      testWidgets('capture header dark=$dark', (tester) async {
        await mount(tester, dark: dark);
        await expectLater(
            find.byKey(const ValueKey('profile-preview')),
            matchesGoldenFile(
                '../../build/profile-previews/header-${dark ? 'dark' : 'light'}.png'));
      });
    }
    testWidgets('capture narrow header with large text', (tester) async {
      await mount(tester,
          width: 320,
          textScale: 2,
          status: 'Under Review',
          name: 'Ananya Venkatalakshmi Reddy',
          employeeId: 'SHERIZE12345678901234567890');
      await expectLater(
          find.byKey(const ValueKey('profile-preview')),
          matchesGoldenFile(
              '../../build/profile-previews/header-large-text.png'));
    });
  }
}
