import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:human_bpo/services/platform_settings_service.dart';

/// Self-check for the super-admin "Worker Earnings System" toggle.
///
/// The entire hide/show-earnings feature hinges on
/// [PlatformSettingsService.earningsSystemEnabled]: every worker-facing
/// earnings surface (Earnings tab, per-lead amount, wallet, history) is gated
/// on it. These tests verify the flag's default, its disabled state, and the
/// live "one-click restore" behaviour the client asked for.
void main() {
  test('settings follow login, logout and account changes', () async {
    final authEvents = StreamController<User?>();
    final fake = FakeFirebaseFirestore();
    final doc = fake.collection('platform_settings').doc('main');
    await doc.set({
      'earningsSystemEnabled': false,
      'maintenanceMode': true,
      'announcement': 'Scheduled maintenance',
      'minWithdrawalAmount': 250,
    });
    final service = PlatformSettingsService(auth: _TestAuth(authEvents.stream));
    addTearDown(service.dispose);
    addTearDown(authEvents.close);
    service.init(fake);
    service.init(fake);
    authEvents.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.isInitialized, isTrue);
    expect(service.earningsSystemEnabled, isTrue);
    expect(service.maintenanceMode, isFalse);

    authEvents.add(_TestUser('worker'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.earningsSystemEnabled, isFalse);
    expect(service.maintenanceMode, isTrue);
    expect(service.minWithdrawalAmount, 250);

    authEvents.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.earningsSystemEnabled, isTrue);
    expect(service.maintenanceMode, isFalse);
    expect(service.announcement, isEmpty);
    expect(service.minWithdrawalAmount, 100);
    await doc.update({'announcement': 'Changed while signed out'});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.announcement, isEmpty);

    authEvents.add(_TestUser('another-worker'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.announcement, 'Changed while signed out');
    expect(service.earningsSystemEnabled, isFalse);
    authEvents.add(_TestUser('third-worker'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await doc.update({'earningsSystemEnabled': true});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.earningsSystemEnabled, isTrue);
  });

  test('dispose cancels authentication and settings subscriptions', () async {
    final authEvents = StreamController<User?>();
    final fake = FakeFirebaseFirestore();
    final service = PlatformSettingsService(auth: _TestAuth(authEvents.stream));
    service.init(fake);
    authEvents.add(_TestUser('worker'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    service.dispose();
    expect(authEvents.hasListener, isFalse);
    await fake
        .collection('platform_settings')
        .doc('main')
        .set({'earningsSystemEnabled': false});
    authEvents.add(_TestUser('another-worker'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.earningsSystemEnabled, isTrue);
    await authEvents.close();
  });

  Future<PlatformSettingsService> startService(
      FakeFirebaseFirestore fake) async {
    final service = PlatformSettingsService(
      auth: _TestAuth(Stream<User?>.value(_TestUser('worker'))),
    )..init(fake);
    // Let the first snapshot arrive.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return service;
  }

  test('defaults to enabled when the flag is absent (safe default)', () async {
    final fake = FakeFirebaseFirestore();
    await fake
        .collection('platform_settings')
        .doc('main')
        .set({'minWithdrawalAmount': 100});

    final service = await startService(fake);
    addTearDown(service.dispose);

    expect(service.earningsSystemEnabled, isTrue);
  });

  test('is disabled when super admin turns it off', () async {
    final fake = FakeFirebaseFirestore();
    await fake
        .collection('platform_settings')
        .doc('main')
        .set({'earningsSystemEnabled': false});

    final service = await startService(fake);
    addTearDown(service.dispose);

    expect(service.earningsSystemEnabled, isFalse);
  });

  test('flips back to enabled live when re-enabled (one-click restore)',
      () async {
    final fake = FakeFirebaseFirestore();
    final doc = fake.collection('platform_settings').doc('main');
    await doc.set({'earningsSystemEnabled': false});

    final service = await startService(fake);
    addTearDown(service.dispose);
    expect(service.earningsSystemEnabled, isFalse);

    await doc.set({'earningsSystemEnabled': true}, SetOptions(merge: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.earningsSystemEnabled, isTrue);
  });
}

class _TestAuth implements FirebaseAuth {
  _TestAuth(this.events);
  final Stream<User?> events;

  @override
  Stream<User?> authStateChanges() => events;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestUser implements User {
  _TestUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
