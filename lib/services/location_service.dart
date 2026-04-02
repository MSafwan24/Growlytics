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

  static const Map<String, List<String>> _malaysiaLocationsByState =
      <String, List<String>>{
        'Johor': <String>[
          'Johor Bahru',
          'Muar',
          'Batu Pahat',
          'Kluang',
          'Pontian',
          'Kota Tinggi',
          'Segamat',
          'Mersing',
          'Kulai',
          'Tangkak',
        ],
        'Kedah': <String>[
          'Alor Setar',
          'Sungai Petani',
          'Kulim',
          'Langkawi',
          'Baling',
          'Yan',
          'Pendang',
          'Kuala Muda',
          'Kubang Pasu',
          'Sik',
        ],
        'Kelantan': <String>[
          'Kota Bharu',
          'Pasir Mas',
          'Tumpat',
          'Tanah Merah',
          'Machang',
          'Kuala Krai',
          'Gua Musang',
          'Bachok',
          'Pasir Puteh',
          'Jeli',
        ],
        'Melaka': <String>[
          'Melaka City',
          'Alor Gajah',
          'Jasin',
          'Ayer Keroh',
          'Masjid Tanah',
          'Merlimau',
          'Durian Tunggal',
        ],
        'Negeri Sembilan': <String>[
          'Seremban',
          'Port Dickson',
          'Jempol',
          'Kuala Pilah',
          'Rembau',
          'Tampin',
          'Jelebu',
        ],
        'Pahang': <String>[
          'Kuantan',
          'Temerloh',
          'Bentong',
          'Jerantut',
          'Raub',
          'Pekan',
          'Maran',
          'Rompin',
          'Cameron Highlands',
          'Bera',
          'Lipis',
        ],
        'Perak': <String>[
          'Ipoh',
          'Taiping',
          'Teluk Intan',
          'Manjung',
          'Batu Gajah',
          'Kampar',
          'Kuala Kangsar',
          'Tapah',
          'Gerik',
          'Sitiawan',
        ],
        'Perlis': <String>['Kangar', 'Arau', 'Padang Besar'],
        'Pulau Pinang': <String>[
          'George Town',
          'Seberang Perai',
          'Bukit Mertajam',
          'Nibong Tebal',
          'Balik Pulau',
          'Butterworth',
        ],
        'Sabah': <String>[
          'Kota Kinabalu',
          'Sandakan',
          'Tawau',
          'Lahad Datu',
          'Keningau',
          'Kudat',
          'Ranau',
          'Papar',
          'Beaufort',
          'Semporna',
        ],
        'Sarawak': <String>[
          'Kuching',
          'Miri',
          'Sibu',
          'Bintulu',
          'Limbang',
          'Sri Aman',
          'Sarikei',
          'Kapit',
          'Samarahan',
          'Mukah',
        ],
        'Selangor': <String>[
          'Shah Alam',
          'Petaling Jaya',
          'Klang',
          'Kajang',
          'Selayang',
          'Subang Jaya',
          'Kuala Selangor',
          'Sabak Bernam',
          'Sepang',
          'Hulu Langat',
          'Kuala Langat',
          'Gombak',
          'Hulu Selangor',
        ],
        'Terengganu': <String>[
          'Kuala Terengganu',
          'Kemaman',
          'Dungun',
          'Besut',
          'Setiu',
          'Marang',
          'Hulu Terengganu',
        ],
        'Kuala Lumpur': <String>[
          'Kuala Lumpur',
          'Bangsar',
          'Cheras',
          'Setapak',
          'Wangsa Maju',
        ],
        'Putrajaya': <String>['Putrajaya'],
        'Labuan': <String>['Labuan'],
      };

  Map<String, List<String>> get malaysiaLocationsByState =>
      _malaysiaLocationsByState;

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
    return _searchLocation(query);
  }

  Future<LocationResult?> searchMalaysiaLocation({
    required String state,
    required String location,
  }) async {
    final cleanedLocation = location.replaceAll(RegExp(r'\s+City$'), '').trim();
    final candidates = <String>{
      location,
      cleanedLocation,
      '$location $state',
      '$cleanedLocation $state',
      '$location Malaysia',
      '$cleanedLocation Malaysia',
    }..removeWhere((query) => query.trim().isEmpty);

    for (final query in candidates) {
      final result = await _searchLocation(
        query,
        countryCode: 'MY',
        expectedState: state,
      );
      if (result != null) {
        return result;
      }
    }

    for (final query in candidates.where(
      (q) =>
          q.toLowerCase().contains('malaysia') ||
          q.toLowerCase().contains(state.toLowerCase()),
    )) {
      final result = await _searchLocation(query, expectedState: state);
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  Future<LocationResult?> _searchLocation(
    String query, {
    String? countryCode,
    String? expectedState,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final countrySegment = countryCode == null
          ? ''
          : '&country_code=${Uri.encodeQueryComponent(countryCode)}';
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeQueryComponent(trimmed)}&count=10&language=en&format=json$countrySegment',
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

      Map<String, dynamic>? top;
      if (expectedState != null && expectedState.trim().isNotEmpty) {
        for (final row in results) {
          final item = row as Map<String, dynamic>;
          final admin1 = ((item['admin1'] as String?) ?? '').trim();
          final country = ((item['country'] as String?) ?? '').trim();
          if (_stateMatches(expectedState, admin1) &&
              (country.isEmpty || country.toLowerCase() == 'malaysia')) {
            top = item;
            break;
          }
        }
      }

      top ??= results.first as Map<String, dynamic>;
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

  bool _stateMatches(String expectedState, String admin1) {
    final expected = _normalizeState(expectedState);
    final actual = _normalizeState(admin1);
    if (expected.isEmpty || actual.isEmpty) {
      return false;
    }
    return expected == actual ||
        expected.contains(actual) ||
        actual.contains(expected);
  }

  String _normalizeState(String value) {
    final lower = value.toLowerCase().trim();
    const aliases = <String, String>{
      'pulau pinang': 'penang',
      'wilayah persekutuan kuala lumpur': 'kuala lumpur',
      'wilayah persekutuan putrajaya': 'putrajaya',
      'wilayah persekutuan labuan': 'labuan',
      'malacca': 'melaka',
      'federal territory of kuala lumpur': 'kuala lumpur',
      'federal territory of putrajaya': 'putrajaya',
      'federal territory of labuan': 'labuan',
    };

    var normalized = lower;
    aliases.forEach((key, replacement) {
      if (normalized == key) {
        normalized = replacement;
      }
    });

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
