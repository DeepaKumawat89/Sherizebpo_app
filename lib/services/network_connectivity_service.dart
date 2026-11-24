import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum InternetStatus { checking, online, offline }

/// App-wide monitor for real internet access.
///
/// A network interface alone is not enough (for example, Wi-Fi can be joined
/// without upstream access), so each check validates a response from an
/// internet endpoint. One shared instance is provided above the whole app to
/// avoid per-screen subscriptions and duplicate requests.
class NetworkConnectivityService extends ChangeNotifier {
  NetworkConnectivityService({http.Client? client, Uri? probeUri})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _probeUri = probeUri ?? _firebaseProbeUri();

  static const _requestTimeout = Duration(seconds: 5);
  static const _onlineCheckInterval = Duration(seconds: 20);
  static const _offlineCheckInterval = Duration(seconds: 5);

  final http.Client _client;
  final bool _ownsClient;
  final Uri _probeUri;
  Timer? _nextCheck;
  Future<void>? _activeCheck;
  InternetStatus _status = InternetStatus.checking;
  bool _checking = false;
  bool _showProgress = false;
  bool _disposed = false;

  InternetStatus get status => _status;
  bool get isOnline => _status == InternetStatus.online;
  bool get isOffline => _status == InternetStatus.offline;
  bool get isChecking =>
      _status == InternetStatus.checking || (_checking && _showProgress);

  static Uri _firebaseProbeUri() {
    final projectId = Firebase.app().options.projectId;
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$projectId/databases/(default)/documents/'
          '__connectivity_probe__',
    );
  }

  void start() {
    if (_disposed || _activeCheck != null || _nextCheck != null) return;
    unawaited(_check(showProgress: false));
  }

  /// Performs an immediate check. Concurrent retry taps share the same work.
  Future<void> checkNow() => _check(showProgress: true);

  Future<void> _check({required bool showProgress}) {
    if (_disposed) return Future.value();
    final currentCheck = _activeCheck;
    if (currentCheck != null) {
      if (showProgress && !_showProgress) {
        _showProgress = true;
        if (!isOnline) notifyListeners();
      }
      return currentCheck;
    }

    _nextCheck?.cancel();
    _nextCheck = null;
    _checking = true;
    _showProgress = showProgress;
    if (showProgress && !isOnline) notifyListeners();
    final check = _performCheck();
    _activeCheck = check;
    check.whenComplete(() {
      if (_disposed) return;
      _activeCheck = null;
      _checking = false;
      final shouldNotify = _showProgress;
      _showProgress = false;
      if (shouldNotify && !isOnline) notifyListeners();
      _scheduleNextCheck();
    });
    return check;
  }

  Future<void> _performCheck() async {
    final reachable = await _probe(_probeUri);
    if (_disposed) return;
    _setStatus(reachable ? InternetStatus.online : InternetStatus.offline);
  }

  Future<bool> _probe(Uri uri) async {
    try {
      final probeUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response = await _client
          .get(probeUri)
          .timeout(_requestTimeout);

      // Any completed HTTPS response from Google's Firestore host proves that
      // DNS, TLS, and upstream internet access are working. The probe targets
      // an intentionally absent document, but its exact status can vary with
      // Firestore rules, quotas, and backend availability. Restricting success
      // to a few response codes causes connected Wi-Fi/mobile-data users to be
      // incorrectly held on the offline screen.
      return response.statusCode >= 100 && response.statusCode < 600;
    } catch (_) {
      return false;
    }
  }

  void _setStatus(InternetStatus value) {
    if (_status == value || _disposed) return;
    _status = value;
    notifyListeners();
  }

  void _scheduleNextCheck() {
    _nextCheck?.cancel();
    _nextCheck = Timer(
      isOnline ? _onlineCheckInterval : _offlineCheckInterval,
      () => unawaited(_check(showProgress: false)),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _nextCheck?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
