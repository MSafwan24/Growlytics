import 'package:flutter/material.dart';
import 'package:growlytics/main.dart';
import 'package:growlytics/services/location_service.dart';
import 'package:growlytics/services/weather_service.dart';

class DashboardPage extends StatefulWidget {
    const DashboardPage({super.key});

    @override
    State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
    final WeatherService _weatherService = WeatherService();
    final LocationService _locationService = LocationService();
    late Future<SmartHydrationWeather> _weatherFuture;
    LocationResult? _location;
    double? _soilMoisturePct;

    @override
    void initState() {
        super.initState();
        _weatherFuture = _loadWeather();
    }

    Future<SmartHydrationWeather> _loadWeather({LocationResult? customLocation}) async {
        final location = customLocation ?? _location ?? await _locationService.detectCurrentLocation();
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
        final controller = TextEditingController();
        final query = await showDialog<String>(
            context: context,
            builder: (context) {
                return AlertDialog(
                    title: const Text('Set your location'),
                    content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            hintText: 'City or village name',
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) => Navigator.of(context).pop(value),
                    ),
                    actions: [
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                        ),
                        FilledButton(
                            onPressed: () => Navigator.of(context).pop(controller.text),
                            child: const Text('Apply'),
                        ),
                    ],
                );
            },
        );

        if (!mounted || query == null || query.trim().isEmpty) {
            return;
        }

        final result = await _locationService.searchLocationByName(query.trim());
        if (!mounted) {
            return;
        }
        if (result == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Location not found. Try another name.')),
            );
            return;
        }

        setState(() {
            _location = result;
            _weatherFuture = _loadWeather(customLocation: result);
        });
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

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: const Color(0xFFF1F8E9),
            body: SafeArea(
                child: Padding(
                    padding : const EdgeInsets.all(24.0),
                    child : SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                const Text("Growlytics", 
                                    style : TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
                                const Text("Your Personal AI Agronomist", 
                                    style: TextStyle (color: Colors.grey)),
                                const SizedBox(height: 24),

                                _buildWeatherCard(),

                                const SizedBox(height: 24),

                                //scan button 
                                _buildScanButton(context),
                                const SizedBox(height: 32),

                                //Crops showing section
                                const Text("Your Crops",
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),

                                //scanned crops displayed following logic that only unique will be display
                                _buildCropCard("Tomato", "3 Scans", Icons.agriculture),
                                _buildCropCard("Watermelon", "1 Scan", Icons.water_drop),

                            ],
                        ),
                    ),
                ),
            ),
        );
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
                return '❌';
            case IrrigationLevel.waterLightly:
                return '⚠️';
            case IrrigationLevel.waterMore:
                return '✅';
            case IrrigationLevel.waterToday:
                return '✅';
        }
    }

    Future<void> _openWeeklyDashboard(SmartHydrationWeather weather) async {
        await Navigator.of(context).push(
            PageRouteBuilder<void>(
                pageBuilder: (context, animation, secondaryAnimation) => _WeeklyForecastPage(
                    weather: weather,
                    weatherIconForCode: _weatherIconForCode,
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    final tween = Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                    );
                    return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: animation.drive(tween), child: child),
                    );
                },
            ),
        );
    }

    // This widget fetches live weather and produces hydration advice.
    Widget _buildWeatherCard() {
        return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)] ),
            child: FutureBuilder<SmartHydrationWeather>(
                future: _weatherFuture,
                builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Row(
                            children: [
                                SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Loading weather data...'),
                            ],
                        );
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                        return Row(
                            children: [
                                const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
                                const SizedBox(width: 12),
                                const Expanded(
                                    child: Text(
                                        'Unable to load weather data. Check your internet and try again.',
                                        softWrap: true,
                                    ),
                                ),
                                IconButton(
                                    onPressed: () {
                                        _refreshWeather();
                                    },
                                    icon: const Icon(Icons.refresh),
                                ),
                            ],
                        );
                    }

                    final weather = snapshot.data!;
                    final statusColor = _statusColor(weather.irrigationLevel);
                    return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openWeeklyDashboard(weather),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Row(
                                        children: [
                                            Icon(
                                                _weatherIconForCode(weather.weatherCode),
                                                color: Colors.orange,
                                                size: 40,
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                        Text(
                                                            weather.locationName,
                                                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                                        ),
                                                        Text(
                                                            '${weather.temperatureC.toStringAsFixed(1)}°C • ${weather.conditionLabel}',
                                                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
                                    Text(
                                        'Humidity ${weather.humidityPct.toStringAsFixed(0)}% • Rain ${weather.rainProbabilityPct.toStringAsFixed(0)}% • Wind ${weather.windSpeedKph.toStringAsFixed(1)} km/h',
                                        style: const TextStyle(color: Colors.black54, fontSize: 16),
                                    ),
                                    if (_soilMoisturePct != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                            'Soil moisture ${_soilMoisturePct!.toStringAsFixed(0)}%',
                                            style: const TextStyle(color: Colors.black54, fontSize: 16),
                                        ),
                                    ],
                                    const SizedBox(height: 10),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                                        ),
                                        child: Text(
                                            '${_statusEmoji(weather.irrigationLevel)} Recommendation: ${weather.irrigationDecision}',
                                            style: TextStyle(
                                                color: statusColor,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                            ),
                                        ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                        weather.fromCache
                                            ? 'Showing saved forecast (offline mode).'
                                            : 'Live data updated ${weather.updatedAt.hour.toString().padLeft(2, '0')}:${weather.updatedAt.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 13, color: Colors.black45),
                                    ),
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
                                                onPressed: _setSoilMoisture,
                                                icon: const Icon(Icons.water_drop),
                                                label: const Text('Soil moisture'),
                                            ),
                                            FilledButton.icon(
                                                onPressed: () => _openWeeklyDashboard(weather),
                                                icon: const Icon(Icons.open_in_full),
                                                label: const Text('7-day details'),
                                            ),
                                        ],
                                    ),
                                ],
                            ),
                        ),
                    );
                },
            ),
        );
    }

    //This is for the scan button will direct to visionscanner.dart
    Widget _buildScanButton(BuildContext context) {
        return SizedBox(

            width: double.infinity,
            height: 60,
            child:  ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),

                ),

                icon: const Icon(Icons.camera_alt),
                label: const Text("SCAN NOW", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: (){

                    // This logic tells main.dart  to change into visionscanner.dart when clicked
                    mainPageKey.currentState?.changeTab(1);
                },
            ),
        );
    }

    // Crops card template
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
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

class _WeeklyForecastPage extends StatelessWidget {
    const _WeeklyForecastPage({
        required this.weather,
        required this.weatherIconForCode,
    });

    final SmartHydrationWeather weather;
    final IconData Function(int weatherCode) weatherIconForCode;

    Color _dayColor(DailyForecast day) {
        if (day.rainProbabilityPct > 70) {
            return Colors.red.shade600;
        }
        if (day.humidityPct > 80) {
            return Colors.amber.shade700;
        }
        return Colors.green.shade700;
    }

    @override
    Widget build(BuildContext context) {
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
                        weather.locationName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Tap each day for expanded insight',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ...weather.dailyForecast.map((day) {
                        final color = _dayColor(day);
                        final recommendation = weather.recommendationForDay(day);
                        return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ExpansionTile(
                                leading: Icon(weatherIconForCode(day.weatherCode), color: Colors.blueGrey),
                                title: Text(
                                    '${_weekday(day.date.weekday)}, ${day.date.day}/${day.date.month}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                    '${day.minTempC.toStringAsFixed(0)}° - ${day.maxTempC.toStringAsFixed(0)}°C • Rain ${day.rainProbabilityPct.toStringAsFixed(0)}%',
                                    style: const TextStyle(fontSize: 15),
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                    Row(
                                        children: [
                                            _metricChip('Humidity', '${day.humidityPct.toStringAsFixed(0)}%'),
                                            const SizedBox(width: 8),
                                            _metricChip('Wind', '${day.windSpeedKph.toStringAsFixed(1)} km/h'),
                                        ],
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
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
                        );
                    }),
                ],
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

    String _weekday(int weekday) {
        const names = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return names[(weekday - 1).clamp(0, 6)];
    }
}