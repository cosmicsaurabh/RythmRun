import 'package:path/path.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  static const String _databaseName = 'rythmrun_workouts.db';
  static const int _databaseVersion = 1;

  // Table names
  static const String _workoutsTable = 'workouts';
  static const String _trackingPointsTable = 'tracking_points';

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create workouts table
    await db.execute('''
      CREATE TABLE $_workoutsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        paused_duration INTEGER,
        total_distance REAL DEFAULT 0,
        average_speed REAL DEFAULT 0,
        max_speed REAL DEFAULT 0,
        average_pace REAL,
        calories INTEGER,
        elevation_gain REAL,
        elevation_loss REAL,
        user_id INTEGER NOT NULL,
        name TEXT,
        notes TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Create tracking points table
    await db.execute('''
      CREATE TABLE $_trackingPointsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (workout_id) REFERENCES $_workoutsTable (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Save a completed workout session
  Future<int> saveWorkoutInLocalDatabase(WorkoutSessionEntity workout) async {
    final db = await database;

    return await db.transaction((txn) async {
      // Insert workout
      final workoutId = await txn.insert(_workoutsTable, {
        'type': workout.type.name,
        'status': workout.status.name,
        'start_time': workout.startTime?.toIso8601String(),
        'end_time': workout.endTime?.toIso8601String(),
        'paused_duration': workout.pausedDuration?.inSeconds,
        'total_distance': workout.totalDistance,
        'average_speed': workout.averageSpeed,
        'max_speed': workout.maxSpeed,
        'average_pace': workout.averagePace,
        'calories': workout.calories,
        'elevation_gain': workout.elevationGain,
        'elevation_loss': workout.elevationLoss,
        'user_id': workout.userId,
        'name': workout.name,
        'notes': workout.notes,
      });

      // Insert tracking points
      if (workout.trackingPoints.isNotEmpty) {
        final batch = txn.batch();
        for (final point in workout.trackingPoints) {
          batch.insert(_trackingPointsTable, {
            'workout_id': workoutId,
            'latitude': point.latitude,
            'longitude': point.longitude,
            'altitude': point.altitude,
            'accuracy': point.accuracy,
            'speed': point.speed,
            'heading': point.heading,
            'timestamp': point.timestamp.toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      }

      return workoutId;
    });
  }

  /// Get all workouts for a user
  Future<List<WorkoutSessionEntity>> getWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    final db = await database;

    final workouts = await db.query(
      _workoutsTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'start_time DESC',
    );

    List<WorkoutSessionEntity> result = [];

    for (final workoutMap in workouts) {
      final workoutId = workoutMap['id'] as int;

      // Get tracking points for this workout
      final points = await db.query(
        _trackingPointsTable,
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'timestamp ASC',
      );

      result.add(_mapToWorkoutEntity(workoutMap, points));
    }

    return result;
  }

  /// Get a single workout by ID
  Future<WorkoutSessionEntity?> getWorkoutFromLocalDatabase(
    int workoutId,
  ) async {
    final db = await database;

    final workouts = await db.query(
      _workoutsTable,
      where: 'id = ?',
      whereArgs: [workoutId],
      limit: 1,
    );

    if (workouts.isEmpty) return null;

    final points = await db.query(
      _trackingPointsTable,
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'timestamp ASC',
    );

    return _mapToWorkoutEntity(workouts.first, points);
  }

  /// Delete a workout
  Future<void> deleteWorkoutFromLocalDatabase(int workoutId) async {
    final db = await database;
    await db.delete(_workoutsTable, where: 'id = ?', whereArgs: [workoutId]);
  }

  /// Get unsynced workouts
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    final db = await database;

    final workouts = await db.query(
      _workoutsTable,
      where: 'user_id = ? AND synced = 0',
      whereArgs: [userId],
      orderBy: 'start_time ASC',
    );

    List<WorkoutSessionEntity> result = [];

    for (final workoutMap in workouts) {
      final workoutId = workoutMap['id'] as int;
      final points = await db.query(
        _trackingPointsTable,
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'timestamp ASC',
      );

      result.add(_mapToWorkoutEntity(workoutMap, points));
    }

    return result;
  }

  /// Mark workout as synced
  Future<void> markWorkoutAsSyncedInLocalDatabase(int workoutId) async {
    final db = await database;
    await db.update(
      _workoutsTable,
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [workoutId],
    );
  }

  /// Map database results to entity
  WorkoutSessionEntity _mapToWorkoutEntity(
    Map<String, dynamic> workoutMap,
    List<Map<String, dynamic>> pointsMap,
  ) {
    // Parse tracking points
    List<TrackingPointEntity> trackingPoints =
        pointsMap.map((point) {
          return TrackingPointEntity(
            latitude: point['latitude'] as double,
            longitude: point['longitude'] as double,
            altitude: point['altitude'] as double?,
            accuracy: point['accuracy'] as double?,
            speed: point['speed'] as double?,
            heading: point['heading'] as double?,
            timestamp: DateTime.parse(point['timestamp'] as String),
          );
        }).toList();

    // Parse workout type
    WorkoutType type = WorkoutType.values.firstWhere(
      (t) => t.name == workoutMap['type'],
      orElse: () => WorkoutType.running,
    );

    // Parse workout status
    WorkoutStatus status = WorkoutStatus.values.firstWhere(
      (s) => s.name == workoutMap['status'],
      orElse: () => WorkoutStatus.completed,
    );

    return WorkoutSessionEntity(
      id: workoutMap['id'].toString(),
      type: type,
      status: status,
      startTime:
          workoutMap['start_time'] != null
              ? DateTime.parse(workoutMap['start_time'] as String)
              : null,
      endTime:
          workoutMap['end_time'] != null
              ? DateTime.parse(workoutMap['end_time'] as String)
              : null,
      pausedDuration:
          workoutMap['paused_duration'] != null
              ? Duration(seconds: workoutMap['paused_duration'] as int)
              : null,
      totalDistance: (workoutMap['total_distance'] as num).toDouble(),
      averageSpeed: (workoutMap['average_speed'] as num).toDouble(),
      maxSpeed: (workoutMap['max_speed'] as num).toDouble(),
      averagePace: workoutMap['average_pace'] as double?,
      calories: workoutMap['calories'] as int?,
      elevationGain: workoutMap['elevation_gain'] as double?,
      elevationLoss: workoutMap['elevation_loss'] as double?,
      userId: workoutMap['user_id'] as int,
      name: workoutMap['name'] as String?,
      notes: workoutMap['notes'] as String?,
      trackingPoints: trackingPoints,
    );
  }

  /// Clear all data (useful for logout)
  Future<void> clearAllDataFromLocalDatabase() async {
    final db = await database;
    await db.delete(_trackingPointsTable);
    await db.delete(_workoutsTable);
  }
}
