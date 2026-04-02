import 'dart:convert';

import 'package:growlytics/models/hydration_record.dart';
import 'package:growlytics/services/weather_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HydrationHistoryService {
  static final HydrationHistoryService _instance = HydrationHistoryService._internal();
  static const String _fallbackStorageKey = 'hydration_records_fallback';
  
  factory HydrationHistoryService() {
    return _instance;
  }
  
  HydrationHistoryService._internal();
  
  static Database? _database;
  
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'hydration_history.db');
    
    return openDatabase(
      path,
      version: 1,
      onCreate: _createDb,
    );
  }
  
  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hydration_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        location TEXT NOT NULL,
        cropType TEXT NOT NULL,
        growthStage TEXT NOT NULL,
        soilType TEXT NOT NULL,
        soilMoisturePct REAL NOT NULL,
        temperatureC REAL NOT NULL,
        humidityPct REAL NOT NULL,
        rainProbabilityPct REAL NOT NULL,
        recommendedLevel TEXT NOT NULL,
        confidence REAL NOT NULL,
        recommendedLitersPerM2 REAL NOT NULL,
        recommendedTiming TEXT NOT NULL,
        farmerFollowedRecommendation INTEGER,
        actualWaterApplied REAL,
        soilMoistureAfter6Hours REAL,
        soilMoistureAfter24Hours REAL,
        notes TEXT
      )
    ''');
  }
  
  /// Save a new hydration record
  Future<int> saveRecord(HydrationRecord record) async {
    try {
      final db = await database;
      return db.insert('hydration_records', record.toMap());
    } catch (_) {
      final records = await _readFallbackRecords();
      records.add(record);
      await _writeFallbackRecords(records);
      return records.length;
    }
  }
  
  /// Update an existing record with farmer feedback
  Future<void> updateRecord(HydrationRecord record) async {
    try {
      final db = await database;
      await db.update(
        'hydration_records',
        record.toMap(),
        where: 'timestamp = ?',
        whereArgs: [record.timestamp.toIso8601String()],
      );
    } catch (_) {
      final records = await _readFallbackRecords();
      final index = records.indexWhere(
        (r) => r.timestamp.toIso8601String() == record.timestamp.toIso8601String(),
      );
      if (index >= 0) {
        records[index] = record;
      } else {
        records.add(record);
      }
      await _writeFallbackRecords(records);
    }
  }
  
  /// Get all records
  Future<List<HydrationRecord>> getAllRecords() async {
    try {
      final db = await database;
      final maps = await db.query('hydration_records', orderBy: 'timestamp DESC');
      return [for (final map in maps) HydrationRecord.fromMap(map)];
    } catch (_) {
      final fallback = await _readFallbackRecords();
      fallback.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return fallback;
    }
  }
  
  /// Get recent records (last N days)
  Future<List<HydrationRecord>> getRecentRecords({int days = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    try {
      final db = await database;
      final maps = await db.query(
        'hydration_records',
        where: 'timestamp > ?',
        whereArgs: [cutoffDate.toIso8601String()],
        orderBy: 'timestamp DESC',
      );
      return [for (final map in maps) HydrationRecord.fromMap(map)];
    } catch (_) {
      final fallback = await _readFallbackRecords();
      final filtered = fallback
          .where((record) => record.timestamp.isAfter(cutoffDate))
          .toList();
      filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return filtered;
    }
  }
  
  /// Get records for a specific location
  Future<List<HydrationRecord>> getRecordsForLocation(String location) async {
    try {
      final db = await database;
      final maps = await db.query(
        'hydration_records',
        where: 'location = ?',
        whereArgs: [location],
        orderBy: 'timestamp DESC',
      );
      return [for (final map in maps) HydrationRecord.fromMap(map)];
    } catch (_) {
      final fallback = await _readFallbackRecords();
      final filtered = fallback.where((record) => record.location == location).toList();
      filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return filtered;
    }
  }

  Future<List<HydrationRecord>> _readFallbackRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fallbackStorageKey);
    if (raw == null || raw.isEmpty) {
      return <HydrationRecord>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <HydrationRecord>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => HydrationRecord.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <HydrationRecord>[];
    }
  }

  Future<void> _writeFallbackRecords(List<HydrationRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final record in records) record.toMap()]);
    await prefs.setString(_fallbackStorageKey, encoded);
  }
  
  /// Calculate performance statistics
  Future<HydrationPerformanceStats> getPerformanceStats() async {
    final allRecords = await getAllRecords();
    
    if (allRecords.isEmpty) {
      return HydrationPerformanceStats(
        totalRecommendations: 0,
        followedCount: 0,
        followRate: 0,
        averageConfidence: 0,
        waterSavedLiters: 0,
        accuracyRate: 0,
      );
    }
    
    final recordsWithFeedback = allRecords.where((r) => r.farmerFollowedRecommendation != null).toList();
    final followedRecords = recordsWithFeedback.where((r) => r.farmerFollowedRecommendation == true).toList();
    
    // Calculate water saved from followed smart actions.
    double waterSaved = 0;
    for (final record in allRecords) {
      if (record.farmerFollowedRecommendation == true &&
          record.recommendedLevel == IrrigationLevel.skip) {
        waterSaved += record.recommendedLitersPerM2 * 100; // Assume 100m²
      } else if (record.farmerFollowedRecommendation == true &&
          record.recommendedLevel == IrrigationLevel.waterLightly) {
        waterSaved += (record.recommendedLitersPerM2 * 100) * 0.35;
      }
    }
    
    // Calculate accuracy (recommendations that matched soil outcomes)
    double accuracyScore = 0;
    int accuracyCount = 0;
    for (final record in allRecords) {
      if (record.soilMoistureAfter24Hours != null) {
        accuracyCount++;
        // If recommendation was to water and soil improved, or skip and didn't dry further
        if (record.recommendedLevel != IrrigationLevel.skip && 
            record.soilMoistureAfter24Hours! > record.soilMoisturePct) {
          accuracyScore += 1.0;
        } else if (record.recommendedLevel == IrrigationLevel.skip && 
                   record.soilMoistureAfter24Hours! <= record.soilMoisturePct + 5) {
          accuracyScore += 1.0;
        }
      }
    }
    
    return HydrationPerformanceStats(
      totalRecommendations: allRecords.length,
      followedCount: followedRecords.length,
      followRate: recordsWithFeedback.isEmpty ? 0 : followedRecords.length / recordsWithFeedback.length,
      averageConfidence: allRecords.map((r) => r.confidence).reduce((a, b) => a + b) / allRecords.length,
      waterSavedLiters: waterSaved,
      accuracyRate: accuracyCount == 0 ? 0 : accuracyScore / accuracyCount,
    );
  }
}
