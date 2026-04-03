import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:growlytics/main.dart';
import 'package:growlytics/services/ai_hydration_service.dart';
import 'package:growlytics/services/location_service.dart';
import 'package:growlytics/services/weather_service.dart';
import 'package:growlytics/models/hydration_record.dart';
import 'package:growlytics/services/hydration_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class z_DashboardPageState extends State<DashboardPage> {
  static const String _fieldAreaM2PrefKey = 'field_area_m2';
  static const String _fieldAreaUnitPrefKey = 'field_area_unit';

  final WeatherService _weatherService = WeatherService();
  final LocationService _locationService = LocationService();
  final AiHydrationService _aiHydrationService = AiHydrationService();
  final HydrationHistoryService _historyService = HydrationHistoryService();
  late Future<SmartHydrationWeather> _weatherFuture;
  late Future<List<HydrationRecord>> _historyFuture;
  LocationResult? _location;
  double? _soilMoisturePct;
  CropType _selectedCropType = CropType.generic;
  GrowthStage _selectedGrowthStage = GrowthStage.vegetative;
  SoilType _selectedSoilType = SoilType.loam;
  CropType? _historyCropFilter;
  String? _historyLocationFilter;
  double _fieldAreaM2 = 100;
  _AreaUnit _fieldAreaUnit = _AreaUnit.squareMeter;
  bool _weatherCardHovered = false;
  bool _isSavingFeedback = false;
  bool _isSavingOutcome = false;
  bool? _lastFeedbackFollowed;
  DateTime? _lastFeedbackAt;
  String? _lastFeedbackMessage;
  List<HydrationRecord> _cachedHistoryRecords = const <HydrationRecord>[];
  double _adaptiveNeedBias = 0;

  @override
  void initState() {
    super.initState();
    _weatherFuture = _loadWeather();
    _historyFuture = _loadHistoryRecordsSafe();
    _initializeFieldAreaSettings();
  }

  Future<void> _initializeFieldAreaSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedArea = prefs.getDouble(_fieldAreaM2PrefKey);
    final savedUnitIndex = prefs.getInt(_fieldAreaUnitPrefKey);

    if (savedArea != null && savedArea > 0) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fieldAreaM2 = savedArea;
        if (savedUnitIndex != null &&
            savedUnitIndex >= 0 &&
            savedUnitIndex < _AreaUnit.values.length) {
          _fieldAreaUnit = _AreaUnit.values[savedUnitIndex];
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setFieldArea(isFirstTimeSetup: true);
    });
  }

  Future<void> _persistFieldAreaSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fieldAreaM2PrefKey, _fieldAreaM2);
    await prefs.setInt(_fieldAreaUnitPrefKey, _fieldAreaUnit.index);
  }

  String _fieldAreaDisplayLabel() {
    final converted = _fieldAreaUnit.fromSquareMeter(_fieldAreaM2);
    final decimals = converted >= 100 ? 0 : 2;
    return '${converted.toStringAsFixed(decimals)} ${_fieldAreaUnit.label}';
  }

  Future<List<HydrationRecord>> _loadHistoryRecordsSafe() async {
    try {
      final records = await _historyService.getRecentRecords(days: 30);
      if (mounted) {
        setState(() {
          _cachedHistoryRecords = records;
          _adaptiveNeedBias = _computeAdaptiveNeedBias(
            records,
            cropType: _selectedCropType,
            soilType: _selectedSoilType,
          );
        });
      }
      return records;
    } catch (_) {
      return const <HydrationRecord>[];
    }
  }

  double _computeAdaptiveNeedBias(
    List<HydrationRecord> records, {
    required CropType cropType,
    required SoilType soilType,
  }) {
    final learned = records
        .where((record) => record.cropType == cropType)
        .where((record) => record.soilType == soilType)
        .where((record) => record.farmerFollowedRecommendation == true)
        .where((record) => record.soilMoistureAfter24Hours != null)
        .toList();

    if (learned.length < 2) {
      return 0;
    }

    var score = 0.0;
    for (final record in learned) {
      final moisture24h = record.soilMoistureAfter24Hours!;
      if (moisture24h < 35) {
        score += 0.08;
      } else if (moisture24h < 45) {
        score += 0.04;
      } else if (moisture24h > 75) {
        score -= 0.08;
      } else if (moisture24h > 65) {
        score -= 0.04;
      }
    }

    final averaged = score / learned.length;
    final sampleWeight = (learned.length / 8).clamp(0.35, 1.0).toDouble();
    return (averaged * sampleWeight).clamp(-0.12, 0.12).toDouble();
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = _loadHistoryRecordsSafe();
    });
  }

  Future<SmartHydrationWeather> _loadWeather({
    LocationResult? customLocation,
  }) async {
    final location =
        customLocation ??
        _location ??
        await _locationService.detectCurrentLocation();
    _location = location;
    return _weatherService.fetchCurrentWeather(
      latitude: location.latitude,
      longitude: location.longitude,
      locationName: location.label,
      soilMoisturePct: _soilMoisturePct,
    );
  }

  Future<void> _refreshWeather() async {
    setState(() {
      _weatherFuture = _loadWeather(customLocation: _location);
    });
  }

  Future<void> _changeLocationManually() async {
    final malaysiaLocationsByState = _locationService.malaysiaLocationsByState;
    final states = malaysiaLocationsByState.keys.toList()..sort();

    var selectedState = _initialStateSelection(states);
    var selectedLocation =
        malaysiaLocationsByState[selectedState]!.first;

    final result = await showDialog<_MalaysiaLocationSelection>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select location in Malaysia'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              final locations = malaysiaLocationsByState[selectedState]!;
              if (!locations.contains(selectedLocation)) {
                selectedLocation = locations.first;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedState,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'State'),
                    items: states
                        .map(
                          (state) => DropdownMenuItem<String>(
                            value: state,
                            child: Text(state),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedState = value;
                        selectedLocation =
                            malaysiaLocationsByState[value]!.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedLocation,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Location'),
                    items: locations
                        .map(
                          (location) => DropdownMenuItem<String>(
                            value: location,
                            child: Text(location),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedLocation = value;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _MalaysiaLocationSelection(
                    state: selectedState,
                    location: selectedLocation,
                  ),
                );
              },
              child: const Text('Use location'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final matched = await _locationService.searchMalaysiaLocation(
      state: result.state,
      location: result.location,
    );
    if (!mounted) {
      return;
    }
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not found. Please try again.')),
      );
      return;
    }

    setState(() {
      _location = matched;
      _weatherFuture = _loadWeather(customLocation: matched);
    });
  }

  String _initialStateSelection(List<String> states) {
    if (_location == null) {
      return states.contains('Kuala Lumpur') ? 'Kuala Lumpur' : states.first;
    }

    final region = _location!.region.toLowerCase();
    for (final state in states) {
      if (region.contains(state.toLowerCase())) {
        return state;
      }
    }
    return states.contains('Kuala Lumpur') ? 'Kuala Lumpur' : states.first;
  }

  Future<void> _setSoilMoisture() async {
    var draftValue = _soilMoisturePct ?? 45;
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Soil moisture input'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What is soil moisture?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Soil moisture is how wet your soil is right now.\n'
                    'Lower value = drier soil, higher value = wetter soil.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Quick guide: 0-30% Dry, 31-70% Moderate, 71-100% Wet',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 10),
                  Text('${draftValue.toStringAsFixed(0)}%'),
                  Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: draftValue,
                    onChanged: (value) {
                      setDialogState(() {
                        draftValue = value;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use this value'),
            ),
          ],
        );
      },
    );

    if (shouldApply == true) {
      setState(() {
        _soilMoisturePct = draftValue;
        _weatherFuture = _loadWeather(customLocation: _location);
      });
    }
  }

  Future<void> _changeCropType() async {
    final result = await showDialog<CropType>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select crop profile'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: CropType.values
                  .map(
                    (crop) => ListTile(
                      leading: Icon(
                        crop == _selectedCropType
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: crop == _selectedCropType
                            ? Colors.green.shade700
                            : Colors.grey,
                      ),
                      title: Text(crop.label),
                      onTap: () => Navigator.of(context).pop(crop),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedCropType = result;
      _adaptiveNeedBias = _computeAdaptiveNeedBias(
        _cachedHistoryRecords,
        cropType: _selectedCropType,
        soilType: _selectedSoilType,
      );
      _weatherFuture = _loadWeather(customLocation: _location);
    });
  }

  Future<void> _changeGrowthStage() async {
    final result = await showDialog<GrowthStage>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select growth stage'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: GrowthStage.values
                  .map(
                    (stage) => ListTile(
                      leading: Icon(
                        stage == _selectedGrowthStage
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: stage == _selectedGrowthStage
                            ? Colors.green.shade700
                            : Colors.grey,
                      ),
                      title: Text(stage.label),
                      subtitle: Text(
                        'Water demand: ${(stage.waterDemandMultiplier * 100).toStringAsFixed(0)}% of baseline',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.of(context).pop(stage),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedGrowthStage = result;
      _weatherFuture = _loadWeather(customLocation: _location);
    });
  }

  Future<void> _changeSoilType() async {
    final result = await showDialog<SoilType>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select soil type'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: SoilType.values
                  .map(
                    (soil) => ListTile(
                      leading: Icon(
                        soil == _selectedSoilType
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: soil == _selectedSoilType ? Colors.green.shade700 : Colors.grey,
                      ),
                      title: Text(soil.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Water holding: ${(soil.waterHoldingCapacityFactor * 100).toStringAsFixed(0)}% of loam',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'Frequency: ${(soil.frequencyMultiplier).toStringAsFixed(1)}x baseline',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(soil),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _selectedSoilType = result;
      _adaptiveNeedBias = _computeAdaptiveNeedBias(
        _cachedHistoryRecords,
        cropType: _selectedCropType,
        soilType: _selectedSoilType,
      );
      _weatherFuture = _loadWeather(customLocation: _location);
    });
  }

  Future<void> _logOutcomeAfter24h() async {
    if (_isSavingOutcome) {
      return;
    }

    final locationLabel = _location?.label;
    final pending = _cachedHistoryRecords.firstWhere(
      (record) =>
          record.cropType == _selectedCropType &&
          record.soilType == _selectedSoilType &&
          (locationLabel == null || record.location == locationLabel) &&
          record.farmerFollowedRecommendation == true &&
          record.soilMoistureAfter24Hours == null,
      orElse: () => HydrationRecord(
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        location: '',
        cropType: _selectedCropType,
        growthStage: _selectedGrowthStage,
        soilType: _selectedSoilType,
        soilMoisturePct: 0,
        temperatureC: 0,
        humidityPct: 0,
        rainProbabilityPct: 0,
        recommendedLevel: IrrigationLevel.waterToday,
        confidence: 0,
        recommendedLitersPerM2: 0,
        recommendedTiming: '',
      ),
    );

    if (pending.timestamp.millisecondsSinceEpoch == 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending followed recommendation found for 24h outcome.'),
        ),
      );
      return;
    }

    var draft24h = pending.soilMoistureAfter24Hours ?? _soilMoisturePct ?? 50;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log 24-hour soil moisture'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Save soil moisture after 24 hours so AI can tune future recommendations.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  Text('${draft24h.toStringAsFixed(0)}%'),
                  Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: draft24h,
                    onChanged: (value) {
                      setDialogState(() {
                        draft24h = value;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save outcome'),
            ),
          ],
        );
      },
    );

    if (shouldSave != true) {
      return;
    }

    setState(() {
      _isSavingOutcome = true;
    });

    try {
      pending.soilMoistureAfter24Hours = draft24h;
      await _historyService.updateRecord(pending);
      _refreshHistory();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('24-hour outcome saved. AI adaptation updated.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save 24-hour outcome. Please try again.'),
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingOutcome = false;
      });
    }
  }

  Widget _buildIrrigationGauge({
    required double needScore,
    required double et0Mm,
    required double confidence,
    required double liters,
    required String timing,
    required CropType cropType,
    required GrowthStage growthStage,
  }) {
    final gaugeValue = needScore;
    final gaugeColor = gaugeValue >= 0.7
        ? Colors.red
        : gaugeValue >= 0.45
            ? Colors.orange
            : Colors.green;

    final levelText = gaugeValue >= 0.7
      ? 'High'
      : gaugeValue >= 0.45
        ? 'Medium'
        : 'Low';

    final levelHelpText = gaugeValue >= 0.7
      ? 'Your crops are likely to need water today.'
      : gaugeValue >= 0.45
        ? 'Water soon, but not urgent right now.'
        : 'Soil conditions are okay for now.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gaugeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gaugeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Watering Need Today',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: gaugeColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 20,
                    value: gaugeValue,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$levelText (${(gaugeValue * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: gaugeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            levelHelpText,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceStars(double confidence) {
    // Convert 0-1 confidence to 1-5 stars
    final stars = (confidence * 5).round().clamp(1, 5);
    return Row(
      children: List.generate(
        5,
        (index) => Icon(
          index < stars ? Icons.star : Icons.star_border,
          color: Colors.amber.shade600,
          size: 18,
        ),
      ),
    );
  }

  Widget _build3DayComparison(SmartHydrationWeather weather) {
    final forecastList = weather.dailyForecast;
    if (forecastList.length < 3) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '3-Day Recommendation Comparison',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Row(
          children: List.generate(3, (index) {
            final day = forecastList[index];
            final dayOfWeek = DateTime.now()
                .add(Duration(days: forecastList.indexOf(day)))
                .toLocal()
                .toString()
                .split(' ')[0];
            final recommendation = _aiHydrationService.recommendationForDay(
              day: day,
              cropType: _selectedCropType,
              growthStage: _selectedGrowthStage,
            );

            // Determine recommendation color
            final isSkip = day.rainProbabilityPct > 70 || (day.soilMoisturePct != null && day.soilMoisturePct! >= 70);
            final isLight = day.humidityPct > 80;
            final recommendationColor = isSkip
                ? Colors.green
                : isLight
                    ? Colors.orange
                    : Colors.red.shade300;
            final cardBackground = Colors.white.withValues(alpha: 0.92);
            final cardBorder = recommendationColor.withValues(alpha: 0.65);
            final titleColor = Colors.black87;
            final bodyColor = Colors.black87;
            final recommendationTextColor = recommendationColor.withValues(alpha: 0.95);

            return Expanded(
              child: Card(
                color: cardBackground,
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cardBorder, width: 1.2),
                ),
                margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayOfWeek,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.maxTempC.toStringAsFixed(0)}°C / ${day.minTempC.toStringAsFixed(0)}°C',
                        style: TextStyle(fontSize: 11, color: bodyColor.withValues(alpha: 0.75)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rain: ${day.rainProbabilityPct.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 11, color: bodyColor.withValues(alpha: 0.75)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: recommendationColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: cardBorder,
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          recommendation,
                          style: TextStyle(
                            fontSize: 10,
                            color: recommendationTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildFeedbackButtons(AiHydrationInsight aiInsight) {
    final canTap = !_isSavingFeedback;
    final followRecorded = _lastFeedbackFollowed == true && _lastFeedbackAt != null;
    final skipRecorded = _lastFeedbackFollowed == false && _lastFeedbackAt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Recommendation Feedback',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canTap ? () => _recordFeedback(aiInsight, true) : null,
                icon: _isSavingFeedback
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(followRecorded ? Icons.check_circle : Icons.thumb_up),
                label: Text(
                  _isSavingFeedback
                      ? 'Saving...'
                      : followRecorded
                          ? 'Recorded'
                          : 'I will follow',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canTap ? () => _recordFeedback(aiInsight, false) : null,
                icon: _isSavingFeedback
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(skipRecorded ? Icons.check_circle : Icons.thumb_down),
                label: Text(
                  _isSavingFeedback
                      ? 'Saving...'
                      : skipRecorded
                          ? 'Recorded'
                          : 'I will skip',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSavingOutcome ? null : _logOutcomeAfter24h,
            icon: _isSavingOutcome
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.monitor_heart_outlined),
            label: Text(
              _isSavingOutcome
                  ? 'Saving outcome...'
                  : 'Log 24h soil outcome (for AI learning)',
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _lastFeedbackMessage == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey<String>(_lastFeedbackMessage!),
                  margin: const EdgeInsets.only(top: 8),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_lastFeedbackFollowed == true
                            ? Colors.green
                            : _lastFeedbackFollowed == false
                                ? Colors.orange
                                : Colors.blueGrey)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (_lastFeedbackFollowed == true
                              ? Colors.green
                              : _lastFeedbackFollowed == false
                                  ? Colors.orange
                                  : Colors.blueGrey)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _lastFeedbackMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _recordFeedback(AiHydrationInsight aiInsight, bool followed) async {
    if (_location == null || _isSavingFeedback) return;

    setState(() {
      _isSavingFeedback = true;
      _lastFeedbackMessage = 'Saving your feedback...';
    });

    try {
      final weather = await _weatherFuture.timeout(const Duration(seconds: 8));
      final now = DateTime.now();
      final record = HydrationRecord(
        timestamp: now,
        location: _location!.label,
        cropType: _selectedCropType,
        growthStage: _selectedGrowthStage,
        soilType: _selectedSoilType,
        soilMoisturePct: _soilMoisturePct ?? 50,
        temperatureC: weather.temperatureC,
        humidityPct: weather.humidityPct,
        rainProbabilityPct: weather.rainProbabilityPct,
        recommendedLevel: aiInsight.recommendedLevel,
        confidence: aiInsight.confidence,
        recommendedLitersPerM2: aiInsight.litersPerSquareMeter,
        recommendedTiming: aiInsight.timingWindow,
        farmerFollowedRecommendation: followed,
      );

      await _historyService.saveRecord(record);
      _refreshHistory();

      if (!mounted) {
        return;
      }

      final formattedTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      setState(() {
        _isSavingFeedback = false;
        _lastFeedbackFollowed = followed;
        _lastFeedbackAt = now;
        _lastFeedbackMessage = followed
            ? 'Recorded at $formattedTime: You chose to follow the recommendation.'
            : 'Recorded at $formattedTime: You chose to skip this recommendation.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: followed ? Colors.green.shade700 : Colors.orange.shade700,
          content: Text(
            followed
                ? 'Recorded successfully: feedback saved.'
                : 'Recorded successfully: skip choice saved.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingFeedback = false;
        _lastFeedbackMessage = 'Could not save feedback. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Failed to save feedback. Check connection and try again.'),
        ),
      );
    }
  }

  List<HydrationRecord> _filteredHistoryRecords(List<HydrationRecord> records) {
    return records.where((record) {
      final cropMatches = _historyCropFilter == null || record.cropType == _historyCropFilter;
      final locationMatches =
          _historyLocationFilter == null || record.location == _historyLocationFilter;
      return cropMatches && locationMatches;
    }).toList();
  }

  _HistorySummary _summarizeRecords(List<HydrationRecord> records) {
    if (records.isEmpty) {
      return const _HistorySummary(
        totalRecommendations: 0,
        followedCount: 0,
        followRate: 0,
        averageConfidence: 0,
        estimatedWaterSavedLiters: 0,
      );
    }

    final feedbackRecords =
        records.where((record) => record.farmerFollowedRecommendation != null).toList();
    final followedCount =
        feedbackRecords.where((record) => record.farmerFollowedRecommendation == true).length;
    final avgConfidence =
        records.map((record) => record.confidence).reduce((a, b) => a + b) / records.length;

    var estimatedWaterSaved = 0.0;
    for (final record in records) {
      if (record.farmerFollowedRecommendation == true &&
          record.recommendedLevel == IrrigationLevel.skip) {
        estimatedWaterSaved += record.recommendedLitersPerM2 * 100;
      }
    }

    return _HistorySummary(
      totalRecommendations: records.length,
      followedCount: followedCount,
      followRate: feedbackRecords.isEmpty ? 0 : followedCount / feedbackRecords.length,
      averageConfidence: avgConfidence,
      estimatedWaterSavedLiters: estimatedWaterSaved,
    );
  }

  Future<void> _exportHistoryCsv(List<HydrationRecord> records) async {
    if (records.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No history data to export for selected filters.')),
      );
      return;
    }

    String escapeCsv(String value) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'timestamp,location,cropType,growthStage,soilType,temperatureC,humidityPct,rainProbabilityPct,recommendedLevel,confidence,recommendedLitersPerM2,recommendedTiming,followed',
    );
    for (final record in records) {
      buffer.writeln(
        [
          escapeCsv(record.timestamp.toIso8601String()),
          escapeCsv(record.location),
          escapeCsv(record.cropType.label),
          escapeCsv(record.growthStage.label),
          escapeCsv(record.soilType.label),
          record.temperatureC.toStringAsFixed(1),
          record.humidityPct.toStringAsFixed(0),
          record.rainProbabilityPct.toStringAsFixed(0),
          escapeCsv(record.recommendedLevel.name),
          record.confidence.toStringAsFixed(2),
          record.recommendedLitersPerM2.toStringAsFixed(2),
          escapeCsv(record.recommendedTiming),
          escapeCsv(record.farmerFollowedRecommendation?.toString() ?? 'unknown'),
        ].join(','),
      );
    }

    final csv = buffer.toString();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('CSV exported'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'History CSV has been copied to clipboard. Preview:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 220,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      const LineSplitter().convert(csv).take(12).join('\n'),
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setFieldArea({bool isFirstTimeSetup = false}) async {
    var draftUnit = _fieldAreaUnit;
    final controller = TextEditingController(
      text: draftUnit.fromSquareMeter(_fieldAreaM2).toStringAsFixed(2),
    );
    final shouldApply = await showDialog<bool>(
      context: context,
      barrierDismissible: !isFirstTimeSetup,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isFirstTimeSetup ? 'Farm size setup' : 'Set field area',
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFirstTimeSetup) ...[
                    const Text(
                      'Enter your farm size once so water savings are accurate.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<_AreaUnit>(
                    initialValue: draftUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: _AreaUnit.values
                        .map(
                          (unit) => DropdownMenuItem<_AreaUnit>(
                            value: unit,
                            child: Text(unit.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        final currentM2 = draftUnit.toSquareMeter(
                          double.tryParse(controller.text.trim()) ?? 0,
                        );
                        draftUnit = value;
                        final converted = draftUnit.fromSquareMeter(currentM2);
                        controller.text = converted.toStringAsFixed(2);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Area (${draftUnit.label})',
                      hintText: 'Example: ${draftUnit.exampleValue}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: 1 hectare = 10,000 m², 1 acre = 4,046.86 m²',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              );
            },
          ),
          actions: [
            if (!isFirstTimeSetup)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(isFirstTimeSetup ? 'Save' : 'Apply'),
            ),
          ],
        );
      },
    );

    if (shouldApply != true) {
      return;
    }
    final parsedInput = double.tryParse(controller.text.trim());
    final parsedM2 =
        parsedInput == null ? null : draftUnit.toSquareMeter(parsedInput);
    if (parsedM2 == null || parsedM2 <= 0) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid farm size.')),
      );
      if (isFirstTimeSetup) {
        _setFieldArea(isFirstTimeSetup: true);
      }
      return;
    }

    setState(() {
      _fieldAreaM2 = parsedM2;
      _fieldAreaUnit = draftUnit;
    });
    await _persistFieldAreaSettings();
  }

  _WaterSavingsMetrics _waterSavingsForPeriod(
    List<HydrationRecord> records,
    Duration period,
  ) {
    final cutoff = DateTime.now().subtract(period);
    final scoped = records.where((record) => record.timestamp.isAfter(cutoff));

    var savedLiters = 0.0;
    var followedSmartActions = 0;
    for (final record in scoped) {
      if (record.farmerFollowedRecommendation != true) {
        continue;
      }
      if (record.recommendedLevel == IrrigationLevel.skip) {
        followedSmartActions++;
        savedLiters += record.recommendedLitersPerM2 * _fieldAreaM2;
      } else if (record.recommendedLevel == IrrigationLevel.waterLightly) {
        followedSmartActions++;
        savedLiters += (record.recommendedLitersPerM2 * _fieldAreaM2) * 0.35;
      }
    }

    const rmPer1000L = 1.8;
    return _WaterSavingsMetrics(
      savedLiters: savedLiters,
      savedCostRm: (savedLiters / 1000) * rmPer1000L,
      smartActionsCount: followedSmartActions,
    );
  }

  Widget _buildWaterSavingsTracker(List<HydrationRecord> records) {
    final today = _waterSavingsForPeriod(records, const Duration(days: 1));
    final week = _waterSavingsForPeriod(records, const Duration(days: 7));
    final month = _waterSavingsForPeriod(records, const Duration(days: 30));
    const monthlyGoalLiters = 5000.0;
    final progress = (month.savedLiters / monthlyGoalLiters).clamp(0, 1).toDouble();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.lightBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.lightBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Water Savings Tracker',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: _setFieldArea,
                icon: const Icon(Icons.straighten, size: 16),
                label: Text(_fieldAreaDisplayLabel()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _historyMetricTile('Today', '${today.savedLiters.toStringAsFixed(0)} L'),
              _historyMetricTile('7 days', '${week.savedLiters.toStringAsFixed(0)} L'),
              _historyMetricTile('30 days', '${month.savedLiters.toStringAsFixed(0)} L'),
              _historyMetricTile('Saved cost', 'RM ${month.savedCostRm.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Monthly goal progress (${month.savedLiters.toStringAsFixed(0)}L / ${monthlyGoalLiters.toStringAsFixed(0)}L)',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: Colors.lightBlue.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.lightBlue.shade700),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Smart actions followed (30 days): ${month.smartActionsCount}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryInsights() {
    return FutureBuilder<List<HydrationRecord>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'History unavailable right now.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          );
        }

        final allRecords = snapshot.data ?? const <HydrationRecord>[];
        final filtered = _filteredHistoryRecords(allRecords);
        final summary = _summarizeRecords(filtered);
        final locations = allRecords.map((record) => record.location).toSet().toList()..sort();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'History Insights (30 days)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh history',
                    onPressed: _refreshHistory,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<CropType?>(
                      initialValue: _historyCropFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filter crop',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<CropType?>(
                          value: null,
                          child: Text('All crops'),
                        ),
                        ...CropType.values.map(
                          (crop) => DropdownMenuItem<CropType?>(
                            value: crop,
                            child: Text(crop.label),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _historyCropFilter = value;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _historyLocationFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filter location',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All locations'),
                        ),
                        ...locations.map(
                          (location) => DropdownMenuItem<String?>(
                            value: location,
                            child: Text(location, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _historyLocationFilter = value;
                        });
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: filtered.isEmpty ? null : () => _exportHistoryCsv(filtered),
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _historyMetricTile('Recommendations', '${summary.totalRecommendations}'),
                  _historyMetricTile(
                    'Follow rate',
                    '${(summary.followRate * 100).toStringAsFixed(0)}%',
                  ),
                  _historyMetricTile(
                    'Avg confidence',
                    '${(summary.averageConfidence * 100).toStringAsFixed(0)}%',
                  ),
                  _historyMetricTile(
                    'Estimated saved',
                    '${summary.estimatedWaterSavedLiters.toStringAsFixed(0)} L',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Confidence trend',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ConfidenceTrendPainter(records: filtered),
                ),
              ),
              _buildWaterSavingsTracker(filtered),
            ],
          ),
        );
      },
    );
  }

  Widget _historyMetricTile(String label, String value) {
    return Container(
      width: 132,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<SmartHydrationWeather>(
          future: _weatherFuture,
          builder: (context, snapshot) {
            final weather = snapshot.data;
            final reduceMotion = _reduceMotion(context);
            final visual = weather == null
                ? _WeatherVisual.cloudy
                : _resolveVisual(weather);
            return Stack(
              children: [
                Positioned.fill(
                  child: _AnimatedWeatherBackdrop(
                    visual: visual,
                    reduceMotion: reduceMotion,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _appBackgroundTintForVisual(visual),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: _appBackgroundWashForVisual(visual),
                  ),
                ),
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Growlytics',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'Your Personal AI Agronomist',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Smart Hydration',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Weather-based watering guidance for your farm',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        _buildWeatherCard(snapshot),
                        const SizedBox(height: 24),
                        _buildScanButton(context),
                        const SizedBox(height: 32),
                        const Text(
                          'Your Crops',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildCropCard('Tomato', '3 Scans', Icons.agriculture),
                        _buildCropCard(
                          'Watermelon',
                          '1 Scan',
                          Icons.water_drop,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _reduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return false;
    }
    return mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
  }

  _WeatherVisual _resolveVisual(SmartHydrationWeather weather) {
    final hour = weather.updatedAt.hour;
    final isNight = hour < 6 || hour >= 19;
    if (isNight) {
      return _WeatherVisual.night;
    }

    final rainyCode =
        (weather.weatherCode >= 51 && weather.weatherCode <= 67) ||
        (weather.weatherCode >= 80 && weather.weatherCode <= 82) ||
        weather.weatherCode >= 95;
    if (rainyCode ||
        weather.rainProbabilityPct > 60 ||
        weather.precipitationMm > 0.5) {
      return _WeatherVisual.rainy;
    }
    if (weather.windSpeedKph >= 22) {
      return _WeatherVisual.windy;
    }
    if (weather.weatherCode == 1 || weather.weatherCode == 2) {
      return _WeatherVisual.partlyCloudy;
    }
    if (weather.weatherCode == 3) {
      return _WeatherVisual.cloudy;
    }
    if (weather.weatherCode == 0 || weather.temperatureC >= 32) {
      return _WeatherVisual.sunny;
    }
    return _WeatherVisual.cloudy;
  }

  _WidgetPalette _paletteForVisual(_WeatherVisual visual) {
    switch (visual) {
      case _WeatherVisual.rainy:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFE6F2FF), Color(0xFFD5E8FF)],
          surface: Color(0xFFF0F7FF),
          border: Color(0xFF5B88C7),
          primaryText: Color(0xFF1D3A60),
          secondaryText: Color(0xFF3B5F8C),
          shadow: Color(0xFF4A78B0),
        );
      case _WeatherVisual.sunny:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFFFF8D9), Color(0xFFFFEBB8)],
          surface: Color(0xFFFFF9E8),
          border: Color(0xFFD7A53D),
          primaryText: Color(0xFF684600),
          secondaryText: Color(0xFF835F09),
          shadow: Color(0xFFC08C21),
        );
      case _WeatherVisual.partlyCloudy:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFE8EEF6), Color(0xFFD8E1EB)],
          surface: Color(0xFFF2F6FB),
          border: Color(0xFF7C90A5),
          primaryText: Color(0xFF24364A),
          secondaryText: Color(0xFF4C6175),
          shadow: Color(0xFF6E8499),
        );
      case _WeatherVisual.cloudy:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFDDE4ED), Color(0xFFC8D2DD)],
          surface: Color(0xFFEAF0F6),
          border: Color(0xFF667A8D),
          primaryText: Color(0xFF1E2E3F),
          secondaryText: Color(0xFF425365),
          shadow: Color(0xFF5D7184),
        );
      case _WeatherVisual.windy:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFE8FBF5), Color(0xFFD5F4E9)],
          surface: Color(0xFFEFFDF7),
          border: Color(0xFF4BA38A),
          primaryText: Color(0xFF1D5A4B),
          secondaryText: Color(0xFF317968),
          shadow: Color(0xFF469B84),
        );
      case _WeatherVisual.night:
        return const _WidgetPalette(
          backgroundGradient: [Color(0xFFE8EDFF), Color(0xFFDCE3FF)],
          surface: Color(0xFFEEF2FF),
          border: Color(0xFF6A78B6),
          primaryText: Color(0xFF2E3768),
          secondaryText: Color(0xFF495390),
          shadow: Color(0xFF6170AD),
        );
    }
  }

  List<Color> _appBackgroundTintForVisual(_WeatherVisual visual) {
    switch (visual) {
      case _WeatherVisual.sunny:
        return [
          const Color(0x33FFF2B8),
          const Color(0x22FFD36E),
        ];
      case _WeatherVisual.rainy:
        return [
          const Color(0x334A79B6),
          const Color(0x221E3C63),
        ];
      case _WeatherVisual.cloudy:
        return [
          const Color(0x44798996),
          const Color(0x335A6878),
        ];
      case _WeatherVisual.partlyCloudy:
        return [
          const Color(0x446E7E8E),
          const Color(0x335D6A79),
        ];
      case _WeatherVisual.windy:
        return [
          const Color(0x3349A98F),
          const Color(0x2245A085),
        ];
      case _WeatherVisual.night:
        return [
          const Color(0x442B3768),
          const Color(0x66111A33),
        ];
    }
  }

  Color _appBackgroundWashForVisual(_WeatherVisual visual) {
    switch (visual) {
      case _WeatherVisual.sunny:
        return const Color(0x14FFF8D9);
      case _WeatherVisual.rainy:
        return const Color(0x1A0F2740);
      case _WeatherVisual.cloudy:
        return const Color(0x2630404F);
      case _WeatherVisual.partlyCloudy:
        return const Color(0x22354454);
      case _WeatherVisual.windy:
        return const Color(0x120E5B4C);
      case _WeatherVisual.night:
        return const Color(0x33111224);
    }
  }

  IconData _weatherIconForCode(int weatherCode) {
    if (weatherCode == 0) {
      return Icons.wb_sunny;
    }
    if (weatherCode >= 1 && weatherCode <= 3) {
      return Icons.cloud;
    }
    if ((weatherCode >= 51 && weatherCode <= 67) ||
        (weatherCode >= 80 && weatherCode <= 82)) {
      return Icons.grain;
    }
    if (weatherCode >= 95) {
      return Icons.thunderstorm;
    }
    return Icons.cloud_queue;
  }

  Color _statusColor(IrrigationLevel level) {
    switch (level) {
      case IrrigationLevel.skip:
        return Colors.red.shade600;
      case IrrigationLevel.waterLightly:
        return Colors.amber.shade700;
      case IrrigationLevel.waterMore:
        return Colors.lightBlue.shade700;
      case IrrigationLevel.waterToday:
        return Colors.green.shade700;
    }
  }

  String _statusEmoji(IrrigationLevel level) {
    switch (level) {
      case IrrigationLevel.skip:
        return 'No';
      case IrrigationLevel.waterLightly:
        return 'Careful';
      case IrrigationLevel.waterMore:
        return 'Yes';
      case IrrigationLevel.waterToday:
        return 'Yes';
    }
  }

  String _beginnerActionText(IrrigationLevel level) {
    switch (level) {
      case IrrigationLevel.skip:
        return 'Do not water today.';
      case IrrigationLevel.waterLightly:
        return 'Water a little today.';
      case IrrigationLevel.waterMore:
        return 'Water more than usual today.';
      case IrrigationLevel.waterToday:
        return 'Water today as normal.';
    }
  }

  String _confidenceLabel(double confidence) {
    if (confidence >= 0.8) {
      return 'High confidence';
    }
    if (confidence >= 0.6) {
      return 'Medium confidence';
    }
    return 'Low confidence';
  }

  Future<void> _openWeeklyDashboard(SmartHydrationWeather weather) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _WeeklyForecastPage(
              weather: weather,
              aiHydrationService: _aiHydrationService,
              cropType: _selectedCropType,
              growthStage: _selectedGrowthStage,
              weatherIconForCode: _weatherIconForCode,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          final scale = Tween<double>(begin: 0.96, end: 1).animate(fade);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeatherCard(AsyncSnapshot<SmartHydrationWeather> snapshot) {
    final reduceMotion = _reduceMotion(context);
    final weatherVisual = snapshot.hasData
        ? _resolveVisual(snapshot.data!)
        : _WeatherVisual.cloudy;
    final palette = _paletteForVisual(weatherVisual);
    return MouseRegion(
      onEnter: (_) => setState(() {
        _weatherCardHovered = true;
      }),
      onExit: (_) => setState(() {
        _weatherCardHovered = false;
      }),
      child: AnimatedScale(
        scale: _weatherCardHovered && !reduceMotion ? 1.015 : 1,
        duration: Duration(milliseconds: reduceMotion ? 0 : 180),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduceMotion ? 0 : 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette.backgroundGradient,
            ),
            border: Border.all(color: palette.border.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(
                  alpha: _weatherCardHovered ? 0.34 : 0.20,
                ),
                blurRadius: _weatherCardHovered ? 20 : 10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Builder(
            builder: (context) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('Loading weather data...')),
                  ],
                );
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Unable to load weather data. Check your internet and try again.',
                        softWrap: true,
                      ),
                    ),
                    IconButton(
                      onPressed: _refreshWeather,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                );
              }

              final weather = snapshot.data!;
              final aiInsight = _aiHydrationService.analyzeCurrent(
                soilType: _selectedSoilType,
                weather: weather,
                cropType: _selectedCropType,
                growthStage: _selectedGrowthStage,
                adaptiveNeedBias: _adaptiveNeedBias,
              );
              final statusColor = _statusColor(aiInsight.recommendedLevel);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _AnimatedWeatherIcon(
                          weatherCode: weather.weatherCode,
                          size: 44,
                          reduceMotion: reduceMotion,
                          accentColor: palette.border,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather.locationName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: palette.primaryText,
                                ),
                              ),
                              Text(
                                '${weather.temperatureC.toStringAsFixed(1)}C - ${weather.conditionLabel}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: palette.primaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh weather',
                          onPressed: _refreshWeather,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _openWeeklyDashboard(weather),
                        icon: const Icon(Icons.open_in_full),
                        label: const Text('7-day details'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Temperature ${weather.temperatureC.toStringAsFixed(0)}°C  |  Humidity ${weather.humidityPct.toStringAsFixed(0)}%  |  Rain chance ${weather.rainProbabilityPct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: palette.secondaryText,
                        fontSize: 15,
                      ),
                    ),
                    if (_soilMoisturePct != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Soil moisture ${_soilMoisturePct!.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: palette.secondaryText,
                          fontSize: 16,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 320),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.98,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _RecommendationBadge(
                        key: ValueKey<String>(
                          '${aiInsight.primaryMessage}:${aiInsight.confidence.toStringAsFixed(2)}',
                        ),
                        statusColor: statusColor,
                        text: '${_statusEmoji(aiInsight.recommendedLevel)} ${_beginnerActionText(aiInsight.recommendedLevel)}',
                        reduceMotion: reduceMotion,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildIrrigationGauge(
                      needScore: aiInsight.needScore,
                      et0Mm: aiInsight.et0Mm,
                      confidence: aiInsight.confidence,
                      liters: aiInsight.litersPerSquareMeter,
                      timing: aiInsight.timingWindow,
                      cropType: _selectedCropType,
                      growthStage: _selectedGrowthStage,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.border.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'What should I do?',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _beginnerActionText(aiInsight.recommendedLevel),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Crop: ${_selectedCropType.label}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: palette.primaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Stage: ${_selectedGrowthStage.label}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: palette.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _buildConfidenceStars(aiInsight.confidence),
                                  const SizedBox(height: 2),
                                  Text(
                                    _confidenceLabel(aiInsight.confidence),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: palette.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'How much: ${aiInsight.litersPerSquareMeter.toStringAsFixed(1)} L per m²',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (_adaptiveNeedBias.abs() > 0.005) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Adaptive tuning: ${_adaptiveNeedBias > 0 ? '+' : ''}${(_adaptiveNeedBias * 100).toStringAsFixed(1)}% based on past 24h outcomes',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.secondaryText,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            'Best time: ${aiInsight.timingWindow}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Why this suggestion:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          ...aiInsight.reasons.map(
                            (reason) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      reason,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: palette.secondaryText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      weather.fromCache
                          ? 'Showing saved forecast (offline mode).'
                          : 'Live data updated ${weather.updatedAt.hour.toString().padLeft(2, '0')}:${weather.updatedAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.secondaryText,
                      ),
                    ),
                    _build3DayComparison(weather),
                    _buildFeedbackButtons(aiInsight),
                    _buildHistoryInsights(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _changeLocationManually,
                          icon: const Icon(Icons.edit_location_alt),
                          label: const Text('Change location'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _changeCropType,
                          icon: const Icon(Icons.grass),
                          label: const Text('Crop type'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _changeGrowthStage,
                          icon: const Icon(Icons.eco),
                          label: const Text('Growth stage'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _changeSoilType,
                          icon: const Icon(Icons.terrain),
                          label: const Text('Soil type'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _setSoilMoisture,
                          icon: const Icon(Icons.water_drop),
                          label: const Text('Soil moisture'),
                        ),
                      ],
                    ),
                  ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: const Icon(Icons.camera_alt),
        label: const Text(
          'SCAN NOW',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          mainPageKey.currentState?.changeTab(1);
        },
      ),
    );
  }

  Widget _buildCropCard(String name, String count, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.shade100,
            child: Icon(icon, color: Colors.green.shade700),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(count, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

class _MalaysiaLocationSelection {
  const _MalaysiaLocationSelection({required this.state, required this.location});

  final String state;
  final String location;
}

enum _AreaUnit { squareMeter, acre, hectare }

extension _AreaUnitX on _AreaUnit {
  String get label {
    switch (this) {
      case _AreaUnit.squareMeter:
        return 'm²';
      case _AreaUnit.acre:
        return 'acre';
      case _AreaUnit.hectare:
        return 'hectare';
    }
  }

  String get exampleValue {
    switch (this) {
      case _AreaUnit.squareMeter:
        return '250';
      case _AreaUnit.acre:
        return '1.2';
      case _AreaUnit.hectare:
        return '0.5';
    }
  }

  double toSquareMeter(double value) {
    switch (this) {
      case _AreaUnit.squareMeter:
        return value;
      case _AreaUnit.acre:
        return value * 4046.86;
      case _AreaUnit.hectare:
        return value * 10000;
    }
  }

  double fromSquareMeter(double value) {
    switch (this) {
      case _AreaUnit.squareMeter:
        return value;
      case _AreaUnit.acre:
        return value / 4046.86;
      case _AreaUnit.hectare:
        return value / 10000;
    }
  }
}

class _HistorySummary {
  const _HistorySummary({
    required this.totalRecommendations,
    required this.followedCount,
    required this.followRate,
    required this.averageConfidence,
    required this.estimatedWaterSavedLiters,
  });

  final int totalRecommendations;
  final int followedCount;
  final double followRate;
  final double averageConfidence;
  final double estimatedWaterSavedLiters;
}

class _WaterSavingsMetrics {
  const _WaterSavingsMetrics({
    required this.savedLiters,
    required this.savedCostRm,
    required this.smartActionsCount,
  });

  final double savedLiters;
  final double savedCostRm;
  final int smartActionsCount;
}

class _WidgetPalette {
  const _WidgetPalette({
    required this.backgroundGradient,
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.shadow,
  });

  final List<Color> backgroundGradient;
  final Color surface;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color shadow;
}

class _ConfidenceTrendPainter extends CustomPainter {
  _ConfidenceTrendPainter({required this.records});

  final List<HydrationRecord> records;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.black.withValues(alpha: 0.05);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      bg,
    );

    if (records.length < 2) {
      final labelPainter = TextPainter(
        text: const TextSpan(
          text: 'Need at least 2 feedback points',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      labelPainter.paint(canvas, const Offset(8, 25));
      return;
    }

    final sorted = [...records]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final data = sorted
        .map((record) => record.confidence.clamp(0.0, 1.0).toDouble())
        .toList();

    const horizontalPadding = 10.0;
    const verticalPadding = 8.0;
    final chartWidth = size.width - (horizontalPadding * 2);
    final chartHeight = size.height - (verticalPadding * 2);
    final xStep = chartWidth / (data.length - 1);

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = horizontalPadding + (xStep * i);
      final y = verticalPadding + ((1 - data[i]) * chartHeight);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(horizontalPadding + chartWidth, verticalPadding + chartHeight)
      ..lineTo(horizontalPadding, verticalPadding + chartHeight)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.teal.withValues(alpha: 0.24),
            Colors.teal.withValues(alpha: 0.03),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.teal.shade700,
    );

    final latest = data.last;
    final latestX = horizontalPadding + chartWidth;
    final latestY = verticalPadding + ((1 - latest) * chartHeight);
    canvas.drawCircle(
      Offset(latestX, latestY),
      3,
      Paint()..color = Colors.teal.shade800,
    );
  }

  @override
  bool shouldRepaint(covariant _ConfidenceTrendPainter oldDelegate) {
    return oldDelegate.records != records;
  }
}

class _RecommendationBadge extends StatefulWidget {
  const _RecommendationBadge({
    super.key,
    required this.statusColor,
    required this.text,
    required this.reduceMotion,
  });

  final Color statusColor;
  final String text;
  final bool reduceMotion;

  @override
  State<_RecommendationBadge> createState() => _RecommendationBadgeState();
}

class _RecommendationBadgeState extends State<_RecommendationBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (!widget.reduceMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _RecommendationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.reduceMotion && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) {
      return _base(1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 1 + (0.015 * sin(_controller.value * pi * 2));
        return Transform.scale(
          scale: pulse,
          alignment: Alignment.centerLeft,
          child: child,
        );
      },
      child: _base(0.18),
    );
  }

  Widget _base(double glowAlpha) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.statusColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: widget.statusColor.withValues(alpha: glowAlpha),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.statusColor,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

enum _WeatherVisual { rainy, sunny, partlyCloudy, cloudy, windy, night }

class _AnimatedWeatherBackdrop extends StatefulWidget {
  const _AnimatedWeatherBackdrop({
    required this.visual,
    required this.reduceMotion,
  });

  final _WeatherVisual visual;
  final bool reduceMotion;

  @override
  State<_AnimatedWeatherBackdrop> createState() =>
      _AnimatedWeatherBackdropState();
}

class _AnimatedWeatherBackdropState extends State<_AnimatedWeatherBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
    if (!widget.reduceMotion) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedWeatherBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: widget.reduceMotion ? 0 : 700);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: AnimatedBuilder(
        key: ValueKey<_WeatherVisual>(widget.visual),
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _WeatherPainter(
              visual: widget.visual,
              progress: widget.reduceMotion ? 0 : _controller.value,
            ),
            child: child,
          );
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter({required this.visual, required this.progress});

  final _WeatherVisual visual;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = _gradientFor(visual);
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    switch (visual) {
      case _WeatherVisual.rainy:
        _drawRain(canvas, size);
        _drawRipple(canvas, size);
      case _WeatherVisual.sunny:
        _drawSun(canvas, size);
        _drawHeatParticles(canvas, size);
      case _WeatherVisual.partlyCloudy:
        _drawSun(canvas, size);
        _drawCloudLayers(canvas, size, Colors.white.withValues(alpha: 0.22));
      case _WeatherVisual.cloudy:
        _drawCloudLayers(canvas, size, Colors.white.withValues(alpha: 0.25));
      case _WeatherVisual.windy:
        _drawCloudLayers(canvas, size, Colors.white.withValues(alpha: 0.18));
        _drawWindStreaks(canvas, size);
      case _WeatherVisual.night:
        _drawStars(canvas, size);
        _drawMoon(canvas, size);
    }
  }

  LinearGradient _gradientFor(_WeatherVisual visual) {
    switch (visual) {
      case _WeatherVisual.rainy:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF34495E), Color(0xFF1E2F3D)],
        );
      case _WeatherVisual.sunny:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6B73C), Color(0xFFF9D976), Color(0xFFFFF3C7)],
        );
      case _WeatherVisual.partlyCloudy:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCBD6E1), Color(0xFF94A4B5)],
        );
      case _WeatherVisual.cloudy:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7D8C9B), Color(0xFF5D6D7D)],
        );
      case _WeatherVisual.windy:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF89A9B8), Color(0xFF5E7B8A)],
        );
      case _WeatherVisual.night:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1A37), Color(0xFF182848)],
        );
    }
  }

  void _drawRain(Canvas canvas, Size size) {
    final rainPaint = Paint()
      ..color = Colors.lightBlue.shade100.withValues(alpha: 0.45)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 80; i++) {
      final x = (i * 37.0) % size.width;
      final y =
          ((i * 53.0) + progress * size.height * 1.6) % (size.height + 30) - 30;
      canvas.drawLine(Offset(x, y), Offset(x - 4, y + 12), rainPaint);
    }

    final flash = sin(progress * pi * 6);
    if (flash > 0.97) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.10),
      );
    }
  }

  void _drawRipple(Canvas canvas, Size size) {
    final p = (progress * 2) % 1;
    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.12 * (1 - p));
    final center = Offset(size.width * 0.78, size.height * 0.82);
    canvas.drawCircle(center, 18 + (40 * p), ripplePaint);
  }

  void _drawSun(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.84, size.height * 0.18);
    final pulse = 1 + 0.08 * sin(progress * pi * 2);
    final glow = Paint()
      ..color = const Color(0xFFFFF4A3).withValues(alpha: 0.35);
    canvas.drawCircle(center, 54 * pulse, glow);
    canvas.drawCircle(
      center,
      25 * pulse,
      Paint()..color = const Color(0xFFFFE05A),
    );
  }

  void _drawHeatParticles(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    for (var i = 0; i < 18; i++) {
      final x = ((i * 43.0) + progress * 38) % size.width;
      final y = size.height * (0.12 + ((i % 6) * 0.14));
      final radius = 1.2 + (i % 3) * 0.8;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  void _drawCloudLayers(Canvas canvas, Size size, Color color) {
    final cloudPaint = Paint()..color = color;
    for (var i = 0; i < 4; i++) {
      final drift = (progress * (22 + i * 8)) % (size.width + 160);
      final x = drift - 120;
      final y = size.height * (0.16 + i * 0.16);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 150, 42),
        const Radius.circular(28),
      );
      canvas.drawRRect(rect, cloudPaint);
    }
  }

  void _drawWindStreaks(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 12; i++) {
      final y = size.height * (0.2 + i * 0.06);
      final start = ((i * 40.0) + progress * 110) % (size.width + 80) - 80;
      canvas.drawLine(Offset(start, y), Offset(start + 45, y), paint);
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    for (var i = 0; i < 42; i++) {
      final twinkle = 0.25 + 0.35 * (0.5 + 0.5 * sin(progress * pi * 2 + i));
      final paint = Paint()..color = Colors.white.withValues(alpha: twinkle);
      final x = (i * 61.0) % size.width;
      final y = (i * 37.0) % (size.height * 0.55);
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 1.4 : 1, paint);
    }
  }

  void _drawMoon(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.82, size.height * 0.2);
    canvas.drawCircle(
      center,
      28,
      Paint()..color = const Color(0xFFE4E7FF).withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      Offset(center.dx + 9, center.dy - 5),
      22,
      Paint()..color = const Color(0xFF1A2A4E),
    );
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.visual != visual;
  }
}

class _AnimatedWeatherIcon extends StatefulWidget {
  const _AnimatedWeatherIcon({
    required this.weatherCode,
    required this.size,
    required this.reduceMotion,
    this.accentColor,
  });

  final int weatherCode;
  final double size;
  final bool reduceMotion;
  final Color? accentColor;

  @override
  State<_AnimatedWeatherIcon> createState() => _AnimatedWeatherIconState();
}

class _AnimatedWeatherIconState extends State<_AnimatedWeatherIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (!widget.reduceMotion) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedWeatherIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isRainy {
    return (widget.weatherCode >= 51 && widget.weatherCode <= 67) ||
        (widget.weatherCode >= 80 && widget.weatherCode <= 82);
  }

  bool get _isSunny => widget.weatherCode == 0;
  bool get _isPartlyCloudy => widget.weatherCode == 1 || widget.weatherCode == 2;
  bool get _isCloudy => widget.weatherCode == 3;
  bool get _isStorm => widget.weatherCode >= 95;

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size;
    final fallbackColor = _isSunny
        ? const Color(0xFFFF9800)
        : _isRainy
        ? const Color(0xFF4FC3F7)
        : const Color(0xFF607D8B);
    final baseColor = widget.accentColor ?? fallbackColor;

    if (widget.reduceMotion) {
      return Icon(_baseIcon(), color: baseColor, size: iconSize);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final bob = sin(t * pi * 2) * 1.8;
        final rotate = _isSunny
            ? t * pi * 2
            : (_isStorm ? sin(t * pi * 2) * 0.04 : 0.0);
        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(
            angle: rotate,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(_baseIcon(), color: baseColor, size: iconSize),
                if (_isRainy)
                  Positioned(
                    bottom: -5,
                    child: SizedBox(
                      width: iconSize * 0.8,
                      height: 10,
                      child: CustomPaint(
                        painter: _MiniRainPainter(progress: t),
                      ),
                    ),
                  ),
                if (_isPartlyCloudy)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Icon(
                      Icons.wb_sunny,
                      color: baseColor.withValues(alpha: 0.5),
                      size: 14,
                    ),
                  ),
                if (_isCloudy)
                  Positioned(
                    right: -4,
                    child: Icon(
                      Icons.blur_on,
                      color: baseColor.withValues(alpha: 0.5),
                      size: 12,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _baseIcon() {
    if (_isSunny) {
      return Icons.wb_sunny;
    }
    if (_isRainy) {
      return Icons.grain;
    }
    if (_isPartlyCloudy) {
      return Icons.wb_cloudy;
    }
    if (_isStorm) {
      return Icons.thunderstorm;
    }
    return Icons.cloud;
  }
}

class _MiniRainPainter extends CustomPainter {
  _MiniRainPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlue.shade100
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final x = (i * 8.0 + progress * 18) % (size.width + 6) - 3;
      canvas.drawLine(Offset(x, 0), Offset(x - 1.2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniRainPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _WeeklyForecastPage extends StatefulWidget {
  const _WeeklyForecastPage({
    required this.weather,
    required this.aiHydrationService,
    required this.cropType,
    required this.growthStage,
    required this.weatherIconForCode,
  });

  final SmartHydrationWeather weather;
  final AiHydrationService aiHydrationService;
  final CropType cropType;
  final GrowthStage growthStage;
  final IconData Function(int weatherCode) weatherIconForCode;

  @override
  State<_WeeklyForecastPage> createState() => _WeeklyForecastPageState();
}

class _WeeklyForecastPageState extends State<_WeeklyForecastPage> {
  int _visibleCards = 0;
  final List<Timer> _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) {
      _visibleCards = widget.weather.dailyForecast.length;
      return;
    }

    for (var i = 0; i < widget.weather.dailyForecast.length; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 100 + (i * 130)), () {
          if (!mounted) {
            return;
          }
          setState(() {
            _visibleCards = i + 1;
          });
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  Color _dayColor(DailyForecast day) {
    if (day.rainProbabilityPct > 70) {
      return Colors.red.shade600;
    }
    if (day.humidityPct > 80) {
      return Colors.amber.shade700;
    }
    return Colors.green.shade700;
  }

  bool _reduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return false;
    }
    return mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Farming Dashboard'),
        backgroundColor: const Color(0xFFF1F8E9),
      ),
      backgroundColor: const Color(0xFFF1F8E9),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.weather.locationName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap each day for expanded insight',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.weather.dailyForecast.length; i++)
            _AnimatedForecastTile(
              day: widget.weather.dailyForecast[i],
              color: _dayColor(widget.weather.dailyForecast[i]),
              recommendation: widget.aiHydrationService.recommendationForDay(
                day: widget.weather.dailyForecast[i],
                cropType: widget.cropType,
                growthStage: widget.growthStage,
              ),
              weatherIconForCode: widget.weatherIconForCode,
              visible: _visibleCards > i,
              reduceMotion: reduceMotion,
              weekday: _weekday(widget.weather.dailyForecast[i].date.weekday),
            ),
        ],
      ),
    );
  }

  String _weekday(int weekday) {
    const names = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(weekday - 1).clamp(0, 6)];
  }
}

class _AnimatedForecastTile extends StatelessWidget {
  const _AnimatedForecastTile({
    required this.day,
    required this.color,
    required this.recommendation,
    required this.weatherIconForCode,
    required this.visible,
    required this.reduceMotion,
    required this.weekday,
  });

  final DailyForecast day;
  final Color color;
  final String recommendation;
  final IconData Function(int weatherCode) weatherIconForCode;
  final bool visible;
  final bool reduceMotion;
  final String weekday;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: reduceMotion ? 0 : 350);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.06),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: _AnimatedWeatherIcon(
                weatherCode: day.weatherCode,
                size: 30,
                reduceMotion: reduceMotion,
              ),
              title: Text(
                '$weekday, ${day.date.day}/${day.date.month}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${day.minTempC.toStringAsFixed(0)} - ${day.maxTempC.toStringAsFixed(0)}C - Rain ${day.rainProbabilityPct.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 15),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip(
                      'Humidity',
                      '${day.humidityPct.toStringAsFixed(0)}%',
                    ),
                    _metricChip(
                      'Wind',
                      '${day.windSpeedKph.toStringAsFixed(1)} km/h',
                    ),
                    _metricChip(
                      'Max temp',
                      '${day.maxTempC.toStringAsFixed(1)}C',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: duration,
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    recommendation,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 14)),
    );
  }
}
