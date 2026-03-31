import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum IrrigationLevel { waterMore, waterToday, waterLightly, skip }

class DailyForecast {
  DailyForecast({
    required this.date,
    required this.minTempC,
    required this.maxTempC,
    required this.weatherCode,
    required this.rainProbabilityPct,
    required this.humidityPct,
    required this.windSpeedKph,
    this.soilMoisturePct,
  });

  final DateTime date;
  final double minTempC;
  final double maxTempC;
  final int weatherCode;
  final double rainProbabilityPct;
  final double humidityPct;
  final double windSpeedKph;
  final double? soilMoisturePct;

  double get avgTempC => (minTempC + maxTempC) / 2;
}

class SmartHydrationWeather {
  SmartHydrationWeather({
    required this.temperatureC,
    required this.humidityPct,
    required this.windSpeedKph,
    required this.weatherCode,
    required this.rainProbabilityPct,
    required this.precipitationMm,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.dailyForecast,
    required this.updatedAt,
    this.fromCache = false,
    this.soilMoisturePct,
  });

  final double temperatureC;
  final double humidityPct;
  final double windSpeedKph;
  final int weatherCode;
  final double rainProbabilityPct;
  final double precipitationMm;
  final String locationName;
  final double latitude;
  final double longitude;
  final List<DailyForecast> dailyForecast;
  final DateTime updatedAt;
  final bool fromCache;
  final double? soilMoisturePct;

  IrrigationLevel get irrigationLevel {
    if (soilMoisturePct != null && soilMoisturePct! >= 70) {
      return IrrigationLevel.skip;
    }
    if (rainProbabilityPct > 70 || precipitationMm >= 1.5) {
      return IrrigationLevel.skip;
    }
    if (soilMoisturePct != null && soilMoisturePct! <= 30) {
      return IrrigationLevel.waterMore;
    }
    if (humidityPct > 80) {
      return IrrigationLevel.waterLightly;
    }
    if (temperatureC > 32 && rainProbabilityPct < 30) {
      return IrrigationLevel.waterMore;
    }
    return IrrigationLevel.waterToday;
  }

  String get irrigationDecision {
    switch (irrigationLevel) {
      case IrrigationLevel.skip:
        return 'Do NOT water - rain expected or soil already moist.';
      case IrrigationLevel.waterLightly:
        return 'Water lightly - high humidity reduces water loss.';
      case IrrigationLevel.waterMore:
        return 'Water more than usual - hot and dry conditions.';
      case IrrigationLevel.waterToday:
        return 'Water your crops today with normal schedule.';
    }
  }

  String recommendationForDay(DailyForecast day) {
    if (day.soilMoisturePct != null && day.soilMoisturePct! >= 70) {
      return 'No watering needed - soil moisture is already high.';
    }
    if (day.rainProbabilityPct > 70) {
      return 'No watering needed - rainfall expected.';
    }
    if (day.humidityPct > 80) {
      return 'Water lightly in the early morning.';
    }
    if (day.maxTempC > 32 && day.rainProbabilityPct < 30) {
      return 'Use drip irrigation due to heat.';
    }
    return 'Water crops early morning.';
  }

  String get conditionLabel {
    if (weatherCode == 0) {
      return 'Clear sky';
    }
    if (weatherCode >= 1 && weatherCode <= 3) {
      return 'Partly cloudy';
    }
    if (weatherCode == 45 || weatherCode == 48) {
      return 'Foggy';
    }
    if ((weatherCode >= 51 && weatherCode <= 67) ||
        (weatherCode >= 80 && weatherCode <= 82)) {
      return 'Rainy';
    }
    if (weatherCode >= 71 && weatherCode <= 77) {
      return 'Snowy';
    }
    if (weatherCode >= 95) {
      return 'Thunderstorm';
    }
    return 'Cloudy';
  }

  String get hydrationTip {
    if (rainProbabilityPct >= 60 || precipitationMm >= 1.5) {
      return 'Delay irrigation, rain is likely soon.';
    }
    if (humidityPct < 40 && windSpeedKph > 15) {
      return 'High evaporation risk, irrigate early morning or late evening.';
    }
    if (temperatureC >= 32 && humidityPct < 55) {
      return 'Hot and dry conditions, increase hydration volume slightly.';
    }
    return 'Stable condition, keep normal hydration schedule.';
  }
}

class WeatherService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';
  static const String _cachePrefix = 'weather_cache_v1';

  Future<SmartHydrationWeather> fetchCurrentWeather({
    required double latitude,
    required double longitude,
    required String locationName,
    double? soilMoisturePct,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,precipitation'
      '&hourly=precipitation_probability,relative_humidity_2m,temperature_2m'
      '&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,wind_speed_10m_max'
      '&forecast_days=7'
      '&timezone=auto',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Weather API failed with status ${response.statusCode}.');
      }

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;

      final weather = _fromApiBody(
        body,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        soilMoisturePct: soilMoisturePct,
      );

      await _writeCache(latitude: latitude, longitude: longitude, body: body);
      return weather;
    } catch (_) {
      final cachedBody = await _readCache(latitude: latitude, longitude: longitude);
      if (cachedBody == null) {
        rethrow;
      }
      return _fromApiBody(
        cachedBody,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        fromCache: true,
        soilMoisturePct: soilMoisturePct,
      );
    }
  }

  SmartHydrationWeather _fromApiBody(
    Map<String, dynamic> body, {
    required String locationName,
    required double latitude,
    required double longitude,
    bool fromCache = false,
    double? soilMoisturePct,
  }) {
    final Map<String, dynamic> current =
        body['current'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> hourly =
        body['hourly'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> daily =
        body['daily'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final List<dynamic> rainProbabilitySeries =
        hourly['precipitation_probability'] as List<dynamic>? ?? <dynamic>[];
    final double rainProbability = rainProbabilitySeries.isNotEmpty
        ? (rainProbabilitySeries.first as num).toDouble()
        : 0.0;

    final dailyForecast = _buildDailyForecast(
      daily: daily,
      hourly: hourly,
      soilMoisturePct: soilMoisturePct,
    );

    return SmartHydrationWeather(
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      humidityPct: (current['relative_humidity_2m'] as num?)?.toDouble() ?? 0,
      windSpeedKph: (current['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
      rainProbabilityPct: rainProbability,
      precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
      dailyForecast: dailyForecast,
      updatedAt: DateTime.now(),
      fromCache: fromCache,
      soilMoisturePct: soilMoisturePct,
    );
  }

  List<DailyForecast> _buildDailyForecast({
    required Map<String, dynamic> daily,
    required Map<String, dynamic> hourly,
    double? soilMoisturePct,
  }) {
    final List<dynamic> dates = daily['time'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> minTemps =
        daily['temperature_2m_min'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> maxTemps =
        daily['temperature_2m_max'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> weatherCodes =
        daily['weather_code'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> dailyRainProb =
        daily['precipitation_probability_max'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> dailyWind =
        daily['wind_speed_10m_max'] as List<dynamic>? ?? <dynamic>[];

    final List<dynamic> hourlyHumidity =
        hourly['relative_humidity_2m'] as List<dynamic>? ?? <dynamic>[];

    final List<DailyForecast> result = <DailyForecast>[];
    final totalDays = min(
      7,
      [
        dates.length,
        minTemps.length,
        maxTemps.length,
        weatherCodes.length,
        dailyRainProb.length,
        dailyWind.length,
      ].reduce(min),
    );

    for (var i = 0; i < totalDays; i++) {
      final dailyHumidity = _estimateDailyHumidity(hourlyHumidity, i);
      result.add(
        DailyForecast(
          date: DateTime.tryParse(dates[i].toString()) ?? DateTime.now(),
          minTempC: (minTemps[i] as num?)?.toDouble() ?? 0,
          maxTempC: (maxTemps[i] as num?)?.toDouble() ?? 0,
          weatherCode: (weatherCodes[i] as num?)?.toInt() ?? 0,
          rainProbabilityPct: (dailyRainProb[i] as num?)?.toDouble() ?? 0,
          humidityPct: dailyHumidity,
          windSpeedKph: (dailyWind[i] as num?)?.toDouble() ?? 0,
          soilMoisturePct: soilMoisturePct,
        ),
      );
    }
    return result;
  }

  double _estimateDailyHumidity(List<dynamic> hourlyHumidity, int dayIndex) {
    final start = dayIndex * 24;
    if (start >= hourlyHumidity.length) {
      return 0;
    }
    final end = min(start + 24, hourlyHumidity.length);
    var sum = 0.0;
    var count = 0;
    for (var i = start; i < end; i++) {
      final value = (hourlyHumidity[i] as num?)?.toDouble();
      if (value != null) {
        sum += value;
        count += 1;
      }
    }
    if (count == 0) {
      return 0;
    }
    return sum / count;
  }

  String _cacheKey(double latitude, double longitude) {
    final lat = latitude.toStringAsFixed(3);
    final lon = longitude.toStringAsFixed(3);
    return '$_cachePrefix:$lat:$lon';
  }

  Future<void> _writeCache({
    required double latitude,
    required double longitude,
    required Map<String, dynamic> body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'saved_at': DateTime.now().toIso8601String(),
      'data': body,
    };
    await prefs.setString(_cacheKey(latitude, longitude), jsonEncode(payload));
  }

  Future<Map<String, dynamic>?> _readCache({
    required double latitude,
    required double longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(latitude, longitude));
    if (raw == null) {
      return null;
    }
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    return payload['data'] as Map<String, dynamic>?;
  }
}
