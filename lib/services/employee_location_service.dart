import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Active-shift-only location sharing. Location data is sent to a callable so
/// Firestore clients cannot forge employee locations or bypass shift checks.
class EmployeeLocationService {
  static final EmployeeLocationService instance = EmployeeLocationService._();

  EmployeeLocationService._() : _functions = FirebaseFunctions.instance;

  EmployeeLocationService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;
  StreamSubscription<Position>? _subscription;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  Timer? _leaseTimer;
  DateTime? _lastSentAt;
  Position? _lastSentPosition;
  bool _stopped = true;
  String? _consentToken;
  String? lastPermissionIssue;
  bool get isTracking => !_stopped;

  Future<bool> requestPermission() async {
    debugPrint('[LocationTracking] Permission request started; platform=$defaultTargetPlatform');
    lastPermissionIssue = null;
    if (kIsWeb) {
      lastPermissionIssue = 'Background employee location is supported on Android and iOS only.';
      debugPrint('[LocationTracking] Permission request unavailable on web.');
      return false;
    }
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[LocationTracking] Device location services enabled=$gpsEnabled');
    if (!gpsEnabled) {
      lastPermissionIssue = 'Turn on device Location, then try sharing again.';
      return false;
    }
    var permission = await Geolocator.checkPermission();
    debugPrint('[LocationTracking] Permission before request=$permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[LocationTracking] Permission after request=$permission');
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      lastPermissionIssue = permission == LocationPermission.deniedForever
          ? 'Location permission is blocked. Allow location in Sherize app settings.'
          : 'Location permission was denied.';
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Tracking starts from the visible shift screen and is promoted to an
      // Android foreground location service with its persistent notification.
      // Requiring ACCESS_BACKGROUND_LOCATION here rejected valid whileInUse
      // grants before that foreground service could start.
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        debugPrint('[LocationTracking] Android permission accepted=$permission; foreground service notification will remain visible.');
        return true;
      }
      lastPermissionIssue = 'Allow location while using Sherize to start shift tracking.';
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        permission != LocationPermission.always) {
      permission = await Geolocator.requestPermission();
      debugPrint('[LocationTracking] iOS background permission result=$permission');
      if (permission != LocationPermission.always) {
        lastPermissionIssue = 'Set Sherize location access to Always in app settings for background shift tracking.';
        return false;
      }
    }
    debugPrint('[LocationTracking] Permission ready=$permission');
    return true;
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> enableConsent() async {
    debugPrint('[LocationTracking] Enabling server consent for active shift.');
    try {
      final result = await _functions.httpsCallable('setLocationConsent').call({'enabled': true, 'date': _today()});
      _consentToken = (result.data as Map?)?['token'] as String?;
      if (_consentToken == null) throw StateError('Could not confirm location consent.');
      debugPrint('[LocationTracking] Server consent enabled; token received.');
    } catch (error, stackTrace) {
      debugPrint('[LocationTracking] Consent call failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> start() async {
    final token = _consentToken;
    await stopLocal();
    _consentToken = token;
    if (_consentToken == null) throw StateError('Location consent is not active.');
    debugPrint('[LocationTracking] Starting position stream; distanceFilter=50m, Android interval=45s, foreground notification enabled.');
    _stopped = false;
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50,
            intervalDuration: const Duration(seconds: 45),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Sherize location sharing is on',
              notificationText: 'Your location is shared with Sherize admins during this work session.',
              enableWakeLock: false,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 50,
            activityType: ActivityType.otherNavigation,
            allowBackgroundLocationUpdates: true,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          );
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_send, onError: (Object error, StackTrace stackTrace) {
      debugPrint('[LocationTracking] Position stream error: $error\n$stackTrace');
      stop();
    }, onDone: () {
      debugPrint('[LocationTracking] Position stream closed.');
    });
    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
      (status) {
        debugPrint('[LocationTracking] Device location service status=$status.');
        if (status == ServiceStatus.disabled) {
          debugPrint('[LocationTracking] GPS/location service disabled; stopping tracking.');
          stop();
        }
      },
      onError: (Object error) => debugPrint('[LocationTracking] GPS status stream error: $error'),
    );
    unawaited(_requestInitialPosition(settings));
    // A short server lease makes an offline withdrawal expire even when the
    // device cannot deliver its explicit stop request.
    _leaseTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_stopped) return;
      try {
        await _functions.httpsCallable('renewLocationConsent').call({'date': _today(), 'token': _consentToken});
        debugPrint('[LocationTracking] Consent lease renewed.');
      } catch (error) {
        // Server rejects future points when the two-minute consent lease expires.
        debugPrint('[LocationTracking] Consent lease renewal failed: $error');
      }
    });
  }

  Future<void> _requestInitialPosition(LocationSettings settings) async {
    debugPrint('[LocationTracking] Requesting initial fix after shift check-in.');
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      ).timeout(const Duration(seconds: 20));
      if (!_stopped) await _send(position);
    } catch (error, stackTrace) {
      debugPrint('[LocationTracking] Initial position fix failed or timed out: $error\n$stackTrace');
    }
  }

  Future<void> _send(Position position) async {
    if (_stopped) return;
    debugPrint('[LocationTracking] Position received; accuracy=${position.accuracy.toStringAsFixed(1)}m.');
    if (position.accuracy <= 0 || position.accuracy > 100) {
      debugPrint('[LocationTracking] Position ignored: accuracy outside 0-100m.');
      return;
    }
    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!) < const Duration(seconds: 30)) {
      debugPrint('[LocationTracking] Position filtered: minimum 30-second upload interval.');
      return;
    }
    if (_lastSentPosition != null &&
        Geolocator.distanceBetween(
              _lastSentPosition!.latitude,
              _lastSentPosition!.longitude,
              position.latitude,
              position.longitude,
            ) < 50) {
      debugPrint('[LocationTracking] Position filtered: movement below 50m.');
      return;
    }
    try {
      await _functions.httpsCallable('renewLocationConsent').call({'date': _today(), 'token': _consentToken});
      if (_stopped) return;
      await _functions.httpsCallable('recordEmployeeLocation').call({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'date': _today(),
        'token': _consentToken,
      });
      _lastSentAt = now;
      _lastSentPosition = position;
      debugPrint('[LocationTracking] Location accepted by Firebase for shift date=${_today()}.');
    } catch (error, stackTrace) {
      // Do not retain or queue offline points; the next fresh point is tried.
      debugPrint('[LocationTracking] Firebase location write failed: $error\n$stackTrace');
    }
  }

  Future<void> stop() async {
    debugPrint('[LocationTracking] Stopping location stream and revoking server consent.');
    await stopLocal();
    try {
      await _functions.httpsCallable('setLocationConsent').call({'enabled': false, 'date': _today()});
      debugPrint('[LocationTracking] Server consent revoked.');
    } catch (error, stackTrace) {
      // Checkout also makes the server reject any subsequent point.
      debugPrint('[LocationTracking] Server consent revocation failed: $error\n$stackTrace');
    }
  }

  Future<void> stopLocal() async {
    _stopped = true;
    _leaseTimer?.cancel();
    _leaseTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
    _lastSentAt = null;
    _lastSentPosition = null;
    _consentToken = null;
    debugPrint('[LocationTracking] Local location tracking stopped.');
  }
}
