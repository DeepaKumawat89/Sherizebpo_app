import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to stream and provide global platform settings to the app.
class PlatformSettingsService extends ChangeNotifier {
  PlatformSettingsService({FirebaseAuth? auth}) : _auth = auth;

  final FirebaseAuth? _auth;
  StreamSubscription<String?>? _authSub;
  int _session = 0;
  double _minWithdrawalAmount = 100.0;
  double _platformCommission = 10.0;
  double _maxTaskPayout = 500.0;
  bool _maintenanceMode = false;
  bool _earningsSystemEnabled = true;
  String _announcement = '';

  bool _isInitialized = false;
  StreamSubscription<DocumentSnapshot>? _sub;

  double get minWithdrawalAmount => _minWithdrawalAmount;
  double get platformCommission => _platformCommission;
  double get maxTaskPayout => _maxTaskPayout;
  bool get maintenanceMode => _maintenanceMode;

  /// Global switch (super-admin controlled) for the worker earnings system.
  /// When `false`, all per-lead amounts, wallet balances, earnings screens and
  /// the Earnings tab are hidden from workers. Backend accrual keeps running,
  /// so flipping this back to `true` restores everything with history intact.
  bool get earningsSystemEnabled => _earningsSystemEnabled;
  String get announcement => _announcement;
  bool get isInitialized => _isInitialized;

  void init([FirebaseFirestore? firestore]) {
    if (_authSub != null) return;
    final db = firestore ?? FirebaseFirestore.instance;
    _authSub = (_auth ?? FirebaseAuth.instance)
        .authStateChanges()
        .map((user) => user?.uid)
        .distinct()
        .listen((userId) {
      final session = ++_session;
      _sub?.cancel();
      _sub = null;
      _minWithdrawalAmount = 100.0;
      _platformCommission = 10.0;
      _maxTaskPayout = 500.0;
      _maintenanceMode = false;
      _earningsSystemEnabled = true;
      _announcement = '';
      _isInitialized = userId == null;
      notifyListeners();
      if (userId == null) return;
      _listenToSettings(db, session);
    });
  }

  void _listenToSettings(FirebaseFirestore db, int session) {
    _sub = db.collection('platform_settings').doc('main').snapshots().listen(
        (doc) {
      if (session != _session) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _minWithdrawalAmount =
            (data['minWithdrawalAmount'] ?? 100.0).toDouble();
        _platformCommission = (data['platformCommission'] ?? 10.0).toDouble();
        _maxTaskPayout = (data['maxTaskPayout'] ?? 500.0).toDouble();
        _maintenanceMode = data['maintenanceMode'] ?? false;
        _earningsSystemEnabled = data['earningsSystemEnabled'] ?? true;
        _announcement = data['announcement'] ?? '';
      }
      _isInitialized = true;
      notifyListeners();
    }, onError: (err) {
      if (session != _session) return;
      debugPrint('Error listening to platform_settings: $err');
      // On permission denied or error, we still consider it "initialized" so it doesn't block the app.
      if (!_isInitialized) {
        _isInitialized = true;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    ++_session;
    _authSub?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
