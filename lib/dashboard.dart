import 'dart:async';
import 'dart:math';

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
  bool _weatherCardHovered = false;

  @override
  void initState() {
    super.initState();
    _weatherFuture = _loadWeather();
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
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set your location'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'City or village name'),
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
                  child: Container(color: Colors.black.withValues(alpha: 0.10)),
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
    if (weather.weatherCode == 0 || weather.temperatureC >= 32) {
      return _WeatherVisual.sunny;
    }
    return _WeatherVisual.cloudy;
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

  Future<void> _openWeeklyDashboard(SmartHydrationWeather weather) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _WeeklyForecastPage(
              weather: weather,
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF9FFF5)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _weatherCardHovered ? 0.22 : 0.12,
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
              final statusColor = _statusColor(weather.irrigationLevel);
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openWeeklyDashboard(weather),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _AnimatedWeatherIcon(
                          weatherCode: weather.weatherCode,
                          size: 44,
                          reduceMotion: reduceMotion,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather.locationName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${weather.temperatureC.toStringAsFixed(1)}C - ${weather.conditionLabel}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
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
                    Text(
                      'Humidity ${weather.humidityPct.toStringAsFixed(0)}% - Rain ${weather.rainProbabilityPct.toStringAsFixed(0)}% - Wind ${weather.windSpeedKph.toStringAsFixed(1)} km/h',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                      ),
                    ),
                    if (_soilMoisturePct != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Soil moisture ${_soilMoisturePct!.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.black54,
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
                        key: ValueKey<String>(weather.irrigationDecision),
                        statusColor: statusColor,
                        text:
                            '${_statusEmoji(weather.irrigationLevel)} Recommendation: ${weather.irrigationDecision}',
                        reduceMotion: reduceMotion,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      weather.fromCache
                          ? 'Showing saved forecast (offline mode).'
                          : 'Live data updated ${weather.updatedAt.hour.toString().padLeft(2, '0')}:${weather.updatedAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
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

enum _WeatherVisual { rainy, sunny, cloudy, windy, night }

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
      case _WeatherVisual.cloudy:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF97A9B8), Color(0xFF6E7F90)],
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
  });

  final int weatherCode;
  final double size;
  final bool reduceMotion;

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
  bool get _isCloudy => widget.weatherCode >= 1 && widget.weatherCode <= 3;
  bool get _isStorm => widget.weatherCode >= 95;

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size;
    final baseColor = _isSunny
        ? const Color(0xFFFF9800)
        : _isRainy
        ? const Color(0xFF4FC3F7)
        : const Color(0xFF607D8B);

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
                if (_isCloudy)
                  Positioned(
                    right: -4,
                    child: Icon(
                      Icons.blur_on,
                      color: Colors.white.withValues(alpha: 0.5),
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
    required this.weatherIconForCode,
  });

  final SmartHydrationWeather weather;
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
              recommendation: widget.weather.recommendationForDay(
                widget.weather.dailyForecast[i],
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
