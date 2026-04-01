import 'package:growlytics/models/hydration_record.dart';
import 'package:growlytics/services/weather_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class HydrationHistoryService {
  static final HydrationHistoryService _instance = HydrationHistoryService._internal();
  
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
    final db = await database;
    return db.insert('hydration_records', record.toMap());
  }
  
  /// Update an existing record with farmer feedback
  Future<void> updateRecord(HydrationRecord record) async {
    final db = await database;
    await db.update(
      'hydration_records',
      record.toMap(),
      where: 'timestamp = ?',
      whereArgs: [record.timestamp.toIso8601String()],
    );
  }
  
  /// Get all records
  Future<List<HydrationRecord>> getAllRecords() async {
    final db = await database;
    final maps = await db.query('hydration_records', orderBy: 'timestamp DESC');
    return [for (final map in maps) HydrationRecord.fromMap(map)];
  }
  
  /// Get recent records (last N days)
  Future<List<HydrationRecord>> getRecentRecords({int days = 30}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    
    final maps = await db.query(
      'hydration_records',
      where: 'timestamp > ?',
      whereArgs: [cutoffDate.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return [for (final map in maps) HydrationRecord.fromMap(map)];
  }
  
  /// Get records for a specific location
  Future<List<HydrationRecord>> getRecordsForLocation(String location) async {
    final db = await database;
    final maps = await db.query(
      'hydration_records',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'timestamp DESC',
    );
    return [for (final map in maps) HydrationRecord.fromMap(map)];
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
    
    // Calculate water saved (when farmer skipped unnecessary watering)
    double waterSaved = 0;
    for (final record in allRecords) {
      if (record.farmerFollowedRecommendation == false && 
          record.recommendedLevel == IrrigationLevel.skip) {
        waterSaved += record.recommendedLitersPerM2 * 100; // Assume 100m²
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
