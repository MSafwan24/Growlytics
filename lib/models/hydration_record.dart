import 'package:growlytics/services/ai_hydration_service.dart';

import 'package:growlytics/services/weather_service.dart';
enum SoilType { sandy, loam, clay }

extension SoilTypeLabel on SoilType {
  String get label {
    switch (this) {
      case SoilType.sandy:
        return 'Sandy';
      case SoilType.loam:
        return 'Loam';
      case SoilType.clay:
        return 'Clay';
    }
  }

  /// Soil water holding capacity adjustment (relative to loam baseline = 1.0)
  double get waterHoldingCapacityFactor {
    switch (this) {
      case SoilType.sandy:
        return 0.6; // Lower water retention
      case SoilType.loam:
        return 1.0; // Baseline
      case SoilType.clay:
        return 1.4; // Higher water retention
    }
  }

  /// Infiltration rate factor (mm/hour) - lower = slower infiltration
  double get infiltrationRateFactor {
    switch (this) {
      case SoilType.sandy:
        return 2.5; // Fast infiltration
      case SoilType.loam:
        return 1.0; // Baseline
      case SoilType.clay:
        return 0.4; // Slow infiltration
    }
  }

  /// Irrigation frequency multiplier
  double get frequencyMultiplier {
    switch (this) {
      case SoilType.sandy:
        return 1.3; // More frequent watering
      case SoilType.loam:
        return 1.0; // Baseline
      case SoilType.clay:
        return 0.7; // Less frequent, deeper watering
    }
  }

  /// Recommended root depth (meters) adjustment
  double get rootDepthFactor {
    switch (this) {
      case SoilType.sandy:
        return 1.2; // Encourage deeper roots due to lower water hold
      case SoilType.loam:
        return 1.0; // Baseline
      case SoilType.clay:
        return 0.8; // Shallower roots due to higher water hold
    }
  }
}

/// Historical record of an irrigation recommendation and actual farmer action
class HydrationRecord {
  HydrationRecord({
    required this.timestamp,
    required this.location,
    required this.cropType,
    required this.growthStage,
    required this.soilType,
    required this.soilMoisturePct,
    required this.temperatureC,
    required this.humidityPct,
    required this.rainProbabilityPct,
    required this.recommendedLevel,
    required this.confidence,
    required this.recommendedLitersPerM2,
    required this.recommendedTiming,
    this.farmerFollowedRecommendation,
    this.actualWaterApplied,
    this.soilMoistureAfter6Hours,
    this.soilMoistureAfter24Hours,
    this.notes,
  });

  final DateTime timestamp;
  final String location;
  final CropType cropType;
  final GrowthStage growthStage;
  final SoilType soilType;
  final double soilMoisturePct;
  final double temperatureC;
  final double humidityPct;
  final double rainProbabilityPct;
  final IrrigationLevel recommendedLevel;
  final double confidence;
  final double recommendedLitersPerM2;
  final String recommendedTiming;

  /// User feedback: did they follow the recommendation?
  bool? farmerFollowedRecommendation;

  /// What they actually applied (if overridden)
  double? actualWaterApplied;

  /// Soil moisture measurement 6 hours after recommendation
  double? soilMoistureAfter6Hours;

  /// Soil moisture measurement 24 hours after recommendation
  double? soilMoistureAfter24Hours;

  /// User notes/comments
  String? notes;

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'location': location,
      'cropType': cropType.toString().split('.').last,
      'growthStage': growthStage.toString().split('.').last,
      'soilType': soilType.toString().split('.').last,
      'soilMoisturePct': soilMoisturePct,
      'temperatureC': temperatureC,
      'humidityPct': humidityPct,
      'rainProbabilityPct': rainProbabilityPct,
      'recommendedLevel': recommendedLevel.toString().split('.').last,
      'confidence': confidence,
      'recommendedLitersPerM2': recommendedLitersPerM2,
      'recommendedTiming': recommendedTiming,
      'farmerFollowedRecommendation': farmerFollowedRecommendation,
      'actualWaterApplied': actualWaterApplied,
      'soilMoistureAfter6Hours': soilMoistureAfter6Hours,
      'soilMoistureAfter24Hours': soilMoistureAfter24Hours,
      'notes': notes,
    };
  }

  /// Create from Map for database retrieval
  factory HydrationRecord.fromMap(Map<String, dynamic> map) {
    return HydrationRecord(
      timestamp: DateTime.parse(map['timestamp'] as String),
      location: map['location'] as String,
      cropType: CropType.values.firstWhere(
        (e) => e.toString().split('.').last == map['cropType'],
        orElse: () => CropType.generic,
      ),
      growthStage: GrowthStage.values.firstWhere(
        (e) => e.toString().split('.').last == map['growthStage'],
        orElse: () => GrowthStage.vegetative,
      ),
      soilType: SoilType.values.firstWhere(
        (e) => e.toString().split('.').last == map['soilType'],
        orElse: () => SoilType.loam,
      ),
      soilMoisturePct: map['soilMoisturePct'] as double,
      temperatureC: map['temperatureC'] as double,
      humidityPct: map['humidityPct'] as double,
      rainProbabilityPct: map['rainProbabilityPct'] as double,
      recommendedLevel: IrrigationLevel.values.firstWhere(
        (e) => e.toString().split('.').last == map['recommendedLevel'],
        orElse: () => IrrigationLevel.waterToday,
      ),
      confidence: (map['confidence'] as num).toDouble(),
      recommendedLitersPerM2: (map['recommendedLitersPerM2'] as num).toDouble(),
      recommendedTiming: map['recommendedTiming'] as String,
      farmerFollowedRecommendation: _boolFromDb(map['farmerFollowedRecommendation']),
      actualWaterApplied: (map['actualWaterApplied'] as num?)?.toDouble(),
      soilMoistureAfter6Hours: (map['soilMoistureAfter6Hours'] as num?)?.toDouble(),
      soilMoistureAfter24Hours: (map['soilMoistureAfter24Hours'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
    );
  }

  static bool? _boolFromDb(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return null;
  }
}

/// Summary statistics for historical recommendations
class HydrationPerformanceStats {
  HydrationPerformanceStats({
    required this.totalRecommendations,
    required this.followedCount,
    required this.followRate,
    required this.averageConfidence,
    required this.waterSavedLiters,
    required this.accuracyRate,
  });

  final int totalRecommendations;
  final int followedCount;
  final double followRate; // 0-1
  final double averageConfidence; // 0-1
  final double waterSavedLiters; // Cumulative
  final double accuracyRate; // 0-1 (recommendations that matched soil outcome)
}
