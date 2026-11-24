import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/work_session.dart';

class AttendanceLocationException implements Exception {
  const AttendanceLocationException(
    this.message, {
    this.settingsAvailable = false,
    this.openDeviceSettings = false,
  });

  final String message;
  final bool settingsAvailable;
  final bool openDeviceSettings;

  @override
  String toString() => message;
}

/// Obtains one new position for an employee-initiated attendance event.
/// It never reads a cached/previous attendance location.
class AttendanceLocationService {
  AttendanceLocationService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Checks only the GPS service and foreground permission. This is safe to
  /// call when the employee dashboard is restored because it does not obtain
  /// or persist a position.
  Future<void> ensureForegroundReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AttendanceLocationException(
        'Turn on device Location to record this attendance location.',
        settingsAvailable: true,
        openDeviceSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AttendanceLocationException(
        'Location permission is blocked. Allow it in Sherize app settings.',
        settingsAvailable: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const AttendanceLocationException(
        'Foreground location permission was denied.',
      );
    }
    // On browsers without the Permissions API, the actual foreground prompt
    // occurs when getCurrentPosition is called. Mobile platforms must already
    // report while-in-use or always permission here.
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always &&
        !(kIsWeb && permission == LocationPermission.unableToDetermine)) {
      throw const AttendanceLocationException(
        'Foreground location permission is unavailable.',
      );
    }
  }

  Future<AttendanceLocation> capture() async {
    // Recheck on every attendance action; do not rely on startup state because
    // permission or GPS can change while the app remains open.
    await ensureForegroundReady();

    late final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw const AttendanceLocationException(
        'A fresh location could not be obtained in time.',
      );
    } catch (_) {
      throw const AttendanceLocationException(
        'A fresh location could not be obtained. Check your GPS and try again.',
      );
    }

    final address = await _reverseGeocode(position.latitude, position.longitude);
    return AttendanceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      capturedAt: position.timestamp,
      address: address.address,
      street: address.street,
      locality: address.locality,
      city: address.city,
      state: address.state,
      postalCode: address.postalCode,
      country: address.country,
      addressUnavailable: address.unavailable,
    );
  }

  Future<_AddressResult> _reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      });
      final headers = kIsWeb
          ? const {'Accept': 'application/json'}
          : const {
              'Accept': 'application/json',
              'Accept-Language': 'en',
              'User-Agent':
                  'Sherize-Attendance/2.1 (https://sherize.in; info@sherize.in)',
            };
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const _AddressResult.unavailable();

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const _AddressResult.unavailable();
      final body = Map<String, dynamic>.from(decoded);
      final displayName = (body['display_name'] ?? '').toString().trim();
      final raw = body['address'];
      final address = raw is Map
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{};
      String value(String key) => (address[key] ?? '').toString().trim();
      String first(List<String> keys) {
        for (final key in keys) {
          final candidate = value(key);
          if (candidate.isNotEmpty) return candidate;
        }
        return '';
      }

      final road = first([
        'road',
        'pedestrian',
        'living_street',
        'residential',
        'footway',
        'path',
      ]);
      final houseNumber = value('house_number');
      final street = [houseNumber, road]
          .where((part) => part.isNotEmpty)
          .join(' ');
      final locality = first([
        'locality',
        'suburb',
        'neighbourhood',
        'quarter',
        'borough',
        'subdivision',
        'city_district',
        'district',
        'hamlet',
      ]);
      final city =
          first(['city', 'town', 'village', 'municipality', 'city_district']);
      final state = first(['state', 'state_district', 'region']);
      final postalCode = value('postcode');
      final country = value('country');
      final parts = <String>[];
      for (final part in [street, locality, city, state, postalCode, country]) {
        if (part.isNotEmpty && !parts.contains(part)) parts.add(part);
      }
      final formattedAddress =
          displayName.isNotEmpty ? displayName : parts.join(', ');
      if (formattedAddress.isEmpty) return const _AddressResult.unavailable();
      return _AddressResult(
        address: formattedAddress,
        street: street,
        locality: locality,
        city: city,
        state: state,
        postalCode: postalCode,
        country: country,
      );
    } catch (_) {
      return const _AddressResult.unavailable();
    }
  }
}

class _AddressResult {
  const _AddressResult({
    required this.address,
    required this.street,
    required this.locality,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    this.unavailable = false,
  });

  const _AddressResult.unavailable()
      : address = '',
        street = '',
        locality = '',
        city = '',
        state = '',
        postalCode = '',
        country = '',
        unavailable = true;

  final String address;
  final String street;
  final String locality;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final bool unavailable;
}
