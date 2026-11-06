import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generic local-storage helper built on shared_preferences alongside
/// Firebase Storage implementation for handling uploads (e.g KYC).
///
/// Call `StorageService.instance` anywhere after `init()`.
class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;
  FirebaseStorage get _firebaseStorage => FirebaseStorage.instance;

  StorageService._();

  static StorageService get instance {
    if (_instance == null) {
      throw StateError('StorageService not initialised. Call init() first.');
    }
    return _instance!;
  }

  static Future<void> init() async {
    _instance = StorageService._();
    _instance!._prefs = await SharedPreferences.getInstance();
  }

  // ─── Firebase Storage Integrations ──────────────────────────

  /// Upload KYC Document and returns the public download URL.
  /// Note: File-based uploads only work on mobile (Android/iOS).
  Future<String?> uploadKYCDocument(
      dynamic file, String userId, String documentType) async {
    if (kIsWeb) {
      // Web upload not supported via dart:io File
      return null;
    }
    try {
      final String filePath = file.path as String;
      final fileName = filePath.split('/').last;
      String extension = fileName.split('.').last;
      final ref = _firebaseStorage
          .ref()
          .child('kyc_documents/$userId/$documentType.$extension');

      final uploadTask = ref.putData(await file.readAsBytes());
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      return null;
    }
  }

  // ─── Strings ────────────────────────────────────────────────
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);
  String? getString(String key) => _prefs.getString(key);

  // ─── Booleans ───────────────────────────────────────────────
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);
  bool? getBool(String key) => _prefs.getBool(key);

  // ─── JSON Objects ───────────────────────────────────────────
  Future<bool> setJson(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // ─── Removal ────────────────────────────────────────────────
  Future<bool> remove(String key) => _prefs.remove(key);
  Future<bool> clear() => _prefs.clear();
}
