import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum AppUpdateRequirement { none, optional, required }

class AppUpdatePolicy {
  const AppUpdatePolicy(
      {this.enabled = false,
      this.latestBuild = 0,
      this.minimumBuild = 0,
      this.message = ''});

  final bool enabled;
  final int latestBuild;
  final int minimumBuild;
  final String message;

  factory AppUpdatePolicy.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const AppUpdatePolicy();
    final latest = data['latestBuild'];
    final minimum = data['minimumBuild'];
    if (latest is! int ||
        minimum is! int ||
        latest < 0 ||
        latest > 2100000000 ||
        minimum < 0 ||
        minimum > latest) {
      return const AppUpdatePolicy();
    }
    final message = data['message'];
    return AppUpdatePolicy(
      enabled: data['enabled'] == true,
      latestBuild: latest,
      minimumBuild: minimum,
      message: message is String && message.length <= 300 ? message : '',
    );
  }

  AppUpdateRequirement requirementFor(int installedBuild) {
    if (!enabled || installedBuild <= 0) return AppUpdateRequirement.none;
    if (installedBuild < minimumBuild) return AppUpdateRequirement.required;
    if (installedBuild < latestBuild) return AppUpdateRequirement.optional;
    return AppUpdateRequirement.none;
  }
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService(
      {FirebaseFirestore? firestore,
      Future<int> Function()? loadBuild,
      bool? supported})
      : _firestore = firestore,
        _loadBuild = loadBuild ?? _installedBuild,
        _supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final FirebaseFirestore? _firestore;
  final Future<int> Function() _loadBuild;
  final bool _supported;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  AppUpdatePolicy _policy = const AppUpdatePolicy();
  int _build = 0;
  int? _dismissedBuild;
  bool _started = false;
  bool _disposed = false;
  bool _ready = false;
  bool _checking = false;
  String _error = '';

  bool get ready => _ready;
  bool get checking => _checking;
  String get error => _error;
  String get message => _policy.message;
  AppUpdateRequirement get requirement {
    final value = _policy.requirementFor(_build);
    return value == AppUpdateRequirement.optional &&
            _dismissedBuild == _policy.latestBuild
        ? AppUpdateRequirement.none
        : value;
  }

  DocumentReference<Map<String, dynamic>> get _document =>
      (_firestore ?? FirebaseFirestore.instance)
          .collection('app_config')
          .doc('android_update');

  static Future<int> _installedBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  Future<void> init() async {
    if (_started || _disposed) return;
    _started = true;
    if (!_supported) {
      _ready = true;
      return;
    }
    try {
      _build = await _loadBuild().timeout(const Duration(seconds: 5));
      if (_disposed) return;
      await refresh();
    } catch (error) {
      debugPrint('App update check unavailable: $error');
    } finally {
      if (!_disposed) {
        _ready = true;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (!_supported || _disposed || _checking || _build <= 0) return;
    _checking = true;
    _error = '';
    notifyListeners();
    final firstSnapshot = Completer<void>();
    await _subscription?.cancel();
    if (_disposed) return;
    _subscription = _document.snapshots().listen((snapshot) {
      if (_disposed) return;
      _policy = AppUpdatePolicy.fromMap(snapshot.data());
      _error = '';
      if (!firstSnapshot.isCompleted) firstSnapshot.complete();
      notifyListeners();
    }, onError: (Object error) {
      if (_disposed) return;
      _error = 'Could not check for updates. Please try again.';
      if (!firstSnapshot.isCompleted) firstSnapshot.complete();
      notifyListeners();
      debugPrint('App update policy unavailable: $error');
    });
    try {
      await firstSnapshot.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _error = 'Could not check for updates. Please try again.';
    } finally {
      if (!_disposed) {
        _checking = false;
        notifyListeners();
      }
    }
  }

  void dismissOptional() {
    if (requirement != AppUpdateRequirement.optional) return;
    _dismissedBuild = _policy.latestBuild;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
