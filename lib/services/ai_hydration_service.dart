import 'dart:math';

import 'package:growlytics/services/weather_service.dart';

enum CropType { generic, rice, chili, corn }

extension CropTypeLabel on CropType {
  String get label {
    switch (this) {
      case CropType.generic:
        return 'General crop';
      case CropType.rice:
        return 'Rice';
      case CropType.chili:
        return 'Chili';
      case CropType.corn:
        return 'Corn';
    }
  }
}

class AiHydrationInsight {
  AiHydrationInsight({
    required this.recommendedLevel,
    required this.needScore,
    required this.confidence,
    required this.litersPerSquareMeter,
    required this.timingWindow,
    required this.reasons,
    required this.primaryMessage,
  });

  final IrrigationLevel recommendedLevel;
  final double needScore;
  final double confidence;
  final double litersPerSquareMeter;
  final String timingWindow;
  final List<String> reasons;
  final String primaryMessage;
}

class AiHydrationService {
  AiHydrationInsight analyzeCurrent({
    required SmartHydrationWeather weather,
    CropType cropType = CropType.generic,
  }) {
    final dryness = _clamp01(1 - (weather.humidityPct / 100));
    final heat = _clamp01((weather.temperatureC - 18) / 18);
    final wind = _clamp01(weather.windSpeedKph / 30);
    final rainRisk = _clamp01(weather.rainProbabilityPct / 100);
    final moistureGuard = _soilGuard(weather.soilMoisturePct);

    var needScore =
        (0.34 * dryness) +
        (0.27 * heat) +
        (0.16 * wind) +
        (0.23 * (1 - rainRisk));

    needScore += _cropNeedModifier(cropType);
    needScore -= moistureGuard;
    needScore = _clamp01(needScore);

    final level = _resolveLevel(
      score: needScore,
      rainProbabilityPct: weather.rainProbabilityPct,
      humidityPct: weather.humidityPct,
      temperatureC: weather.temperatureC,
      soilMoisturePct: weather.soilMoisturePct,
    );

    final confidence = _confidenceFor(weather: weather, score: needScore);
    final litersPerSquareMeter = _litersFor(score: needScore, cropType: cropType);

    return AiHydrationInsight(
      recommendedLevel: level,
      needScore: needScore,
      confidence: confidence,
      litersPerSquareMeter: litersPerSquareMeter,
      timingWindow: _timingWindow(weather),
      reasons: _reasoning(weather),
      primaryMessage: _primaryMessage(level),
    );
  }

  String recommendationForDay({
    required DailyForecast day,
    CropType cropType = CropType.generic,
  }) {
    final humidity = day.humidityPct;
    final rain = day.rainProbabilityPct;
    final heat = day.maxTempC;
    final soil = day.soilMoisturePct;

    if (soil != null && soil >= 70) {
      return 'Skip watering - soil moisture is already high.';
    }
    if (rain > 70) {
      return 'Do not water - rainfall likely.';
    }
    if (humidity > 80) {
      return 'Water lightly before sunrise.';
    }
    if (heat > 32 && rain < 30) {
      if (cropType == CropType.rice) {
        return 'Keep shallow standing water due to heat.';
      }
      return 'Use drip irrigation due to heat stress risk.';
    }
    return 'Normal irrigation in early morning.';
  }

  String _primaryMessage(IrrigationLevel level) {
    switch (level) {
      case IrrigationLevel.skip:
        return 'AI: Skip watering for now.';
      case IrrigationLevel.waterLightly:
        return 'AI: Water lightly today.';
      case IrrigationLevel.waterMore:
        return 'AI: Increase watering volume.';
      case IrrigationLevel.waterToday:
        return 'AI: Water with normal schedule.';
    }
  }

  List<String> _reasoning(SmartHydrationWeather weather) {
    final reasons = <String>[];

    if (weather.rainProbabilityPct > 70) {
      reasons.add('High rain probability in forecast.');
    }
    if (weather.temperatureC > 32) {
      reasons.add('High temperature increases crop water loss.');
    }
    if (weather.humidityPct > 80) {
      reasons.add('High humidity lowers transpiration demand.');
    }
    if (weather.windSpeedKph > 18) {
      reasons.add('Strong wind increases evapotranspiration.');
    }
    if (weather.soilMoisturePct != null) {
      if (weather.soilMoisturePct! < 30) {
        reasons.add('Soil moisture is low.');
      } else if (weather.soilMoisturePct! > 70) {
        reasons.add('Soil moisture is already high.');
      }
    }

    if (reasons.isEmpty) {
      reasons.add('Weather is stable with moderate hydration demand.');
    }

    return reasons.take(3).toList();
  }

  String _timingWindow(SmartHydrationWeather weather) {
    if (weather.rainProbabilityPct > 70) {
      return 'Monitor only';
    }
    if (weather.windSpeedKph > 18) {
      return '18:00-20:00';
    }
    if (weather.temperatureC >= 32) {
      return '06:00-08:00 and 18:00-19:00';
    }
    return '06:30-08:30';
  }

  double _litersFor({required double score, required CropType cropType}) {
    final base = switch (cropType) {
      CropType.generic => 4.8,
      CropType.rice => 7.0,
      CropType.chili => 4.2,
      CropType.corn => 5.3,
    };
    return max(1.4, base * (0.55 + score));
  }

  double _confidenceFor({
    required SmartHydrationWeather weather,
    required double score,
  }) {
    final decisiveness = (score - 0.5).abs();
    final forecastSpread = weather.dailyForecast.isEmpty
        ? 0
        : weather.dailyForecast
                  .map((d) => d.rainProbabilityPct)
                  .reduce(max) -
              weather.dailyForecast
                  .map((d) => d.rainProbabilityPct)
                  .reduce(min);
    final stability = 1 - _clamp01(forecastSpread / 100);
    final confidence = 0.50 + (decisiveness * 0.8) + (stability * 0.18);
    return confidence.clamp(0.45, 0.98);
  }

  IrrigationLevel _resolveLevel({
    required double score,
    required double rainProbabilityPct,
    required double humidityPct,
    required double temperatureC,
    required double? soilMoisturePct,
  }) {
    if (soilMoisturePct != null && soilMoisturePct >= 70) {
      return IrrigationLevel.skip;
    }
    if (rainProbabilityPct > 70) {
      return IrrigationLevel.skip;
    }
    if (humidityPct > 80 && score < 0.70) {
      return IrrigationLevel.waterLightly;
    }
    if (temperatureC > 32 && rainProbabilityPct < 30 && score >= 0.55) {
      return IrrigationLevel.waterMore;
    }

    if (score >= 0.72) {
      return IrrigationLevel.waterMore;
    }
    if (score <= 0.33) {
      return IrrigationLevel.skip;
    }
    if (score <= 0.50) {
      return IrrigationLevel.waterLightly;
    }
    return IrrigationLevel.waterToday;
  }

  double _soilGuard(double? soilMoisturePct) {
    if (soilMoisturePct == null) {
      return 0;
    }
    if (soilMoisturePct >= 70) {
      return 0.55;
    }
    if (soilMoisturePct <= 30) {
      return -0.18;
    }
    return 0;
  }

  double _cropNeedModifier(CropType cropType) {
    return switch (cropType) {
      CropType.generic => 0,
      CropType.rice => 0.10,
      CropType.chili => -0.04,
      CropType.corn => 0.03,
    };
  }

  double _clamp01(double value) => value.clamp(0.0, 1.0);
}
