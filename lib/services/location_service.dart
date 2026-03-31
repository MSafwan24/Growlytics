import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.region,
    required this.source,
  });

  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String source;

  String get label {
    if (city.isNotEmpty && region.isNotEmpty) {
      return '$city, $region';
    }
    if (city.isNotEmpty) {
      return city;
    }
    if (region.isNotEmpty) {
      return region;
    }
    return 'Unknown location';
  }
}

class LocationService {
  static const double defaultLatitude = 3.1390;
  static const double defaultLongitude = 101.6869;
  static const String defaultCity = 'Kuala Lumpur';
  static const String defaultRegion = 'Malaysia';

  Future<LocationResult> detectCurrentLocation() async {
    try {
      final gpsResult = await _detectViaGps();
      if (gpsResult != null) {
        return gpsResult;
      }
    } catch (_) {
      // Continue to fallback strategies.
    }

    if (kIsWeb) {
      final ipResult = await _detectViaIp();
      if (ipResult != null) {
        return ipResult;
      }
    }

    return const LocationResult(
      latitude: defaultLatitude,
      longitude: defaultLongitude,
      city: defaultCity,
      region: defaultRegion,
      source: 'default',
    );
  }

  Future<LocationResult?> _detectViaGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final reverse = await _reverseGeocode(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      city: reverse['city'] ?? '',
      region: reverse['region'] ?? '',
      source: 'gps',
    );
  }

  Future<LocationResult?> _detectViaIp() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode != 200) {
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final latitude = (body['latitude'] as num?)?.toDouble();
      final longitude = (body['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        return null;
      }

      return LocationResult(
        latitude: latitude,
        longitude: longitude,
        city: (body['city'] as String?) ?? '',
        region: (body['region'] as String?) ?? '',
        source: 'ip',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/reverse'
        '?latitude=$latitude&longitude=$longitude&language=en&count=1',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return <String, String>{};
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? <dynamic>[];
      if (results.isEmpty) {
        return <String, String>{};
      }
      final top = results.first as Map<String, dynamic>;
      return <String, String>{
        'city': (top['name'] as String?) ?? '',
        'region': (top['admin1'] as String?) ?? (top['country'] as String?) ?? '',
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<LocationResult?> searchLocationByName(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeQueryComponent(trimmed)}&count=1&language=en&format=json',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? <dynamic>[];
      if (results.isEmpty) {
        return null;
      }
      final top = results.first as Map<String, dynamic>;
      return LocationResult(
        latitude: (top['latitude'] as num?)?.toDouble() ?? defaultLatitude,
        longitude: (top['longitude'] as num?)?.toDouble() ?? defaultLongitude,
        city: (top['name'] as String?) ?? '',
        region: (top['admin1'] as String?) ?? (top['country'] as String?) ?? '',
        source: 'manual',
      );
    } catch (_) {
      return null;
    }
  }
}
