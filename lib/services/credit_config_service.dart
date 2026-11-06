import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/constants.dart';

/// Streams the developer-controlled branding / credit configuration from
/// Firestore (`app_config/branding`) and exposes it to the UI.
///
/// Falls back to the compiled-in [AppConstants] defaults when the document or
/// an individual field is missing, so the credit always renders (even offline
/// or before the first snapshot arrives).
///
/// Only the developer may write this document (enforced by Firestore rules),
/// which is what lets developer mode centrally toggle / edit the credit.
class CreditConfigService extends ChangeNotifier {
  bool _enabled = true;
  bool _locked = true;
  String _credit = AppConstants.developerCredit;
  String _company = AppConstants.developerCompany;
  String _website = AppConstants.developerWebsite;
  String _websiteUrl = AppConstants.developerWebsiteUrl;
  bool _isInitialized = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  bool get enabled => _enabled;
  bool get locked => _locked;
  String get credit => _credit;
  String get company => _company;
  String get website => _website;
  String get websiteUrl => _websiteUrl;
  bool get isInitialized => _isInitialized;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection(AppConstants.appConfigCollection)
          .doc(AppConstants.brandingConfigDoc);

  static String _orDefault(dynamic value, String fallback) {
    final s = value is String ? value.trim() : '';
    return s.isNotEmpty ? s : fallback;
  }

  // Prefer the per-surface (mobile) override, then the global value, then the
  // compiled-in default.
  static String _pick(dynamic surfaceVal, dynamic globalVal, String fallback) {
    final s = surfaceVal is String ? surfaceVal.trim() : '';
    if (s.isNotEmpty) return s;
    return _orDefault(globalVal, fallback);
  }

  void init() {
    _sub = _ref.snapshots().listen((doc) {
      final data = doc.data();
      if (data != null) {
        // Per-surface override for the mobile app, merged over global defaults.
        final surfaces = data['surfaces'];
        final Map<String, dynamic> mobile =
            (surfaces is Map && surfaces['mobile'] is Map)
                ? Map<String, dynamic>.from(surfaces['mobile'] as Map)
                : const {};

        _enabled = (mobile['enabled'] as bool?) ?? (data['enabled'] as bool? ?? true);
        _locked = data['locked'] as bool? ?? true;
        _credit = _pick(mobile['credit'], data['credit'], AppConstants.developerCredit);
        _company = _pick(mobile['company'], data['company'], AppConstants.developerCompany);
        _website = _pick(mobile['website'], data['website'], AppConstants.developerWebsite);
        _websiteUrl =
            _pick(mobile['websiteUrl'], data['websiteUrl'], AppConstants.developerWebsiteUrl);
      }
      _isInitialized = true;
      notifyListeners();
    }, onError: (err) {
      debugPrint('CreditConfigService: $err');
      // Never block the UI on config errors — keep the compiled defaults.
      if (!_isInitialized) {
        _isInitialized = true;
        notifyListeners();
      }
    });
  }

  /// Developer-only write. Firestore rules reject non-developers, so this
  /// will fail for any other role.
  Future<String?> updateConfig({
    bool? enabled,
    bool? locked,
    String? credit,
    String? company,
    String? website,
    String? websiteUrl,
  }) async {
    try {
      await _ref.set({
        if (enabled != null) 'enabled': enabled,
        if (locked != null) 'locked': locked,
        if (credit != null) 'credit': credit,
        if (company != null) 'company': company,
        if (website != null) 'website': website,
        if (websiteUrl != null) 'websiteUrl': websiteUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return null;
    } catch (e) {
      return 'Failed to save: $e';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
