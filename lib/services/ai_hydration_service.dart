import 'dart:math';

import 'package:growlytics/services/weather_service.dart';

enum CropType { generic, rice, chili, corn }

enum GrowthStage { seedling, vegetative, flowering, fruitingOrGrainFill }

// Note: SoilType is imported from models/hydration_record.dart when used in dashboard

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

extension GrowthStageLabel on GrowthStage {
  String get label {
    switch (this) {
      case GrowthStage.seedling:
        return 'Seedling';
      case GrowthStage.vegetative:
        return 'Vegetative';
      case GrowthStage.flowering:
        return 'Flowering';
      case GrowthStage.fruitingOrGrainFill:
        return 'Fruiting/Grain Fill';
    }
  }

  /// Crop water requirement multiplier based on growth stage
  /// Value 0.4-1.6 relative to baseline
  double get waterDemandMultiplier {
    switch (this) {
      case GrowthStage.seedling:
        return 0.5; // Low water requirement
      case GrowthStage.vegetative:
        return 0.8; // Moderate water
      case GrowthStage.flowering:
        return 1.2; // High water demand
      case GrowthStage.fruitingOrGrainFill:
        return 1.0; // Full water
    }
  }
}

class AiHydrationInsight {
  AiHydrationInsight({
    required this.recommendedLevel,
    required this.needScore,
    required this.et0Mm,
    required this.confidence,
    required this.litersPerSquareMeter,
    required this.timingWindow,
    required this.reasons,
    required this.primaryMessage,
    required this.growthStage,
  });

  final IrrigationLevel recommendedLevel;
  final double needScore;
  final double et0Mm; // Reference evapotranspiration in mm
  final double confidence;
  final double litersPerSquareMeter;
  final String timingWindow;
  final List<String> reasons;
  final String primaryMessage;
  final GrowthStage growthStage;
}

class AiHydrationService {
  AiHydrationInsight analyzeCurrent({
    required SmartHydrationWeather weather,
    CropType cropType = CropType.generic,
    GrowthStage growthStage = GrowthStage.vegetative,
    dynamic soilType, // SoilType from models/hydration_record.dart
  }) {
    // Apply soil type adjustments if provided.
    // Dynamic typing keeps this service decoupled from model imports.
    var soilWaterHoldingFactor = 1.0;
    if (soilType != null) {
      try {
        soilWaterHoldingFactor = soilType.waterHoldingCapacityFactor as double;
      } catch (_) {
        // Keep default loam baseline when soil metadata is unavailable.
      }
    }

    // Calculate ET0 (Reference Evapotranspiration) using simplified Hargreaves method
    final et0Mm = _calculateET0(
      temperatureC: weather.temperatureC,
      humidityPct: weather.humidityPct,
      windSpeedKph: weather.windSpeedKph,
      latitude: weather.latitude,
    );

    // Apply crop coefficient (Kc) based on growth stage
    final kcValue = _getCropCoefficient(cropType, growthStage);
    final etcMm = et0Mm * kcValue; // Crop evapotranspiration

    // Normalize signals 0..1
    final dryness = _clamp01(1 - (weather.humidityPct / 100));
    final heat = _clamp01((weather.temperatureC - 18) / 18);
    final wind = _clamp01(weather.windSpeedKph / 30);
    final rainRisk = _clamp01(weather.rainProbabilityPct / 100);
    final moistureGuard = _soilGuard(weather.soilMoisturePct);
    final etcNorm = _clamp01(etcMm / 8.0); // Normalize ET to typical max 8mm/day

    // Weighted score including ET0/ETC
    var needScore =
        (0.25 * dryness) +
        (0.30 * etcNorm) + // Higher weight for ET0-based calculation
        (0.16 * wind) +
        (0.18 * heat) +
        (0.11 * (1 - rainRisk));

    needScore += _cropNeedModifier(cropType);
    needScore *= growthStage.waterDemandMultiplier; // Apply growth stage multiplier
    needScore -= moistureGuard;

    // Sandy soil tends to require more frequent irrigation than clay.
    needScore *= (1.0 / (soilWaterHoldingFactor + 0.2));

    needScore = _clamp01(needScore);

    final level = _resolveLevel(
      score: needScore,
      rainProbabilityPct: weather.rainProbabilityPct,
      humidityPct: weather.humidityPct,
      temperatureC: weather.temperatureC,
      soilMoisturePct: weather.soilMoisturePct,
    );

    final confidence = _confidenceFor(weather: weather, score: needScore);
    final litersPerSquareMeter =
        _litersFor(score: needScore, cropType: cropType, etcMm: etcMm);

    return AiHydrationInsight(
      recommendedLevel: level,
      needScore: needScore,
      et0Mm: et0Mm,
      confidence: confidence,
      litersPerSquareMeter: litersPerSquareMeter,
      timingWindow: _timingWindow(weather),
      reasons: _reasoning(weather, et0Mm: et0Mm, growthStage: growthStage),
      primaryMessage: _primaryMessage(level),
      growthStage: growthStage,
    );
  }

  /// Calculate Reference Evapotranspiration (ET0) using Hargreaves equation
  /// ET0 = 0.0023 × (T_mean + 17.8) × (T_max - T_min)^0.5 × RA
  /// Simplified for available data
  double _calculateET0({
    required double temperatureC,
    required double humidityPct,
    required double windSpeedKph,
    required double latitude,
  }) {
    // Simplified ET0 based on temperature, humidity, and wind
    // Typical range: 2-8 mm/day for tropical regions

    // Base ET0 from temperature (higher temp = more evapotranspiration)
    final tempEffect = (temperatureC / 25.0) * 2.5; // Normalized to ~2.5 at 25°C

    // Humidity adjustment (lower humidity = more evapotranspiration)
    final humidityEffect = (1 - (humidityPct / 100)) * 1.5;

    // Wind adjustment (higher wind = more evapotranspiration)
    final windEffect = (windSpeedKph / 20.0) * 1.0; // Normalized to ~1.0 at 20 kph

    // Combined ET0 estimate (mm/day)
    final et0 = 2.0 + tempEffect + humidityEffect + windEffect;

    return _clamp01(et0 / 10.0) * 8.0; // Clamp to 0-8 mm/day range (typical for tropics)
  }

  /// Get crop coefficient (Kc) based on crop type and growth stage
  double _getCropCoefficient(CropType cropType, GrowthStage growthStage) {
    // Typical Kc values for different crops and stages
    return switch ((cropType, growthStage)) {
      (CropType.rice, GrowthStage.seedling) => 1.0,
      (CropType.rice, GrowthStage.vegetative) => 1.1,
      (CropType.rice, GrowthStage.flowering) => 1.2,
      (CropType.rice, GrowthStage.fruitingOrGrainFill) => 0.9,
      (CropType.chili, GrowthStage.seedling) => 0.4,
      (CropType.chili, GrowthStage.vegetative) => 0.7,
      (CropType.chili, GrowthStage.flowering) => 0.9,
      (CropType.chili, GrowthStage.fruitingOrGrainFill) => 0.85,
      (CropType.corn, GrowthStage.seedling) => 0.5,
      (CropType.corn, GrowthStage.vegetative) => 0.8,
      (CropType.corn, GrowthStage.flowering) => 1.15,
      (CropType.corn, GrowthStage.fruitingOrGrainFill) => 1.0,
      _ => 0.85, // Default for generic crop
    };
  }


  String recommendationForDay({
    required DailyForecast day,
    CropType cropType = CropType.generic,
    GrowthStage growthStage = GrowthStage.vegetative,
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

    if (growthStage == GrowthStage.flowering || growthStage == GrowthStage.fruitingOrGrainFill) {
      return 'Increase water for ${growthStage.label} stage in early morning.';
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

  List<String> _reasoning(
    SmartHydrationWeather weather, {
    required double et0Mm,
    required GrowthStage growthStage,
  }) {
    final reasons = <String>[];

    if (et0Mm > 6.0) {
      reasons.add('High evapotranspiration demand (${et0Mm.toStringAsFixed(1)} mm).');
    }

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

    if (growthStage == GrowthStage.flowering) {
      reasons.add('${growthStage.label} stage needs more water.');
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

  double _litersFor({
    required double score,
    required CropType cropType,
    required double etcMm,
  }) {
    final base = switch (cropType) {
      CropType.generic => 4.8,
      CropType.rice => 7.0,
      CropType.chili => 4.2,
      CropType.corn => 5.3,
    };

    // Adjust liters based on ETC calculation
    // ETC in mm needs to be converted to liters per m²
    // 1 mm over 1 m² = 1 liter
    final et0BasedLiters = etcMm * 0.8; // Apply efficiency factor
    final scoredLiters = base * (0.55 + score);

    // Blend ET0-based and score-based calculations
    final blended = (et0BasedLiters * 0.4) + (scoredLiters * 0.6);
    return max(1.4, blended);
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
