import 'package:path/path.dart';
import 'package:rythmrun_frontend_flutter/core/utils/client_sync_id_generator.dart';
import 'package:rythmrun_frontend_flutter/core/utils/ensure_type_helper.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/activity_image_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/tracking_point_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/workout_session_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/status_change_event_entity.dart';
import 'package:sqflite/sqflite.dart';

class LocalDbService {
  static const String _databaseName = 'rythmrun_workouts.db';
  static const int _databaseVersion = 5;

  static const String _activeDurationSecondsSql = '''
    CASE
      WHEN julianday(start_time) IS NULL OR julianday(end_time) IS NULL THEN 0
      ELSE MAX(
        0,
        CAST(
          ROUND(
            (julianday(end_time) - julianday(start_time)) * 86400.0,
            3
          ) AS INTEGER
        ) - MAX(CAST(COALESCE(paused_duration, 0) AS INTEGER), 0)
      )
    END
  ''';

  // Table names
  static const String _workoutsTable = 'workouts';
  static const String _trackingPointsTable = 'tracking_points';
  static const String _statusChangesTable = 'status_changes';
  static const String _workoutDeleteQueueTable = 'workout_delete_queue';
  static const String _workoutImagesTable = 'workout_images';

  final DatabaseFactory? _databaseFactoryOverride;
  final String? _databasePathOverride;

  Database? _database;

  LocalDbService({DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactoryOverride = databaseFactory,
      _databasePathOverride = databasePath;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final factory = _databaseFactoryOverride ?? databaseFactory;
    final path =
        _databasePathOverride ??
        join(await factory.getDatabasesPath(), _databaseName);
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    await _ensureSyncColumns(db);
    await _ensureWorkoutDeleteSupport(db);
    await _ensureWorkoutImageSupport(db);
    await _ensureMetricsVersionColumn(db);
    await _ensureClientSyncIdsOnDatabase(db);

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add status changes table
      await db.execute('''
        CREATE TABLE $_statusChangesTable (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          workout_id INTEGER NOT NULL,
          status TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          FOREIGN KEY (workout_id) REFERENCES $_workoutsTable (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 3) {
      await _ensureSyncColumns(db);
      await _ensureClientSyncIdsOnDatabase(db);
    }

    if (oldVersion < 4) {
      await _ensureWorkoutDeleteSupport(db);
      await _ensureWorkoutImageSupport(db);
    }

    if (oldVersion < 5) {
      await _ensureMetricsVersionColumn(db);
    }
  }

  Future<void> _createTables(Database db) async {
    // Create workouts table
    await db.execute('''
      CREATE TABLE $_workoutsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        paused_duration INTEGER,
        metrics_version INTEGER NOT NULL DEFAULT 1
          CHECK(metrics_version IN (1, 2)),
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
        remote_activity_id INTEGER,
        client_sync_id TEXT NOT NULL,
        deleted_locally INTEGER DEFAULT 0,
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

    // Create status changes table
    await db.execute('''
      CREATE TABLE $_statusChangesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (workout_id) REFERENCES $_workoutsTable (id) ON DELETE CASCADE
      )
    ''');

    await _createWorkoutDeleteQueueTable(db);
    await _createWorkoutImagesTable(db);
  }

  /// Save a completed workout session
  Future<int> saveWorkoutInLocalDatabase(WorkoutSessionEntity workout) async {
    if (!WorkoutSessionEntity.isSupportedMetricsVersion(
      workout.metricsVersion,
    )) {
      throw ArgumentError.value(
        workout.metricsVersion,
        'workout.metricsVersion',
        'Only metrics versions 1 and 2 are supported',
      );
    }

    final db = await database;

    return await db.transaction((txn) async {
      // Insert workout
      final clientSyncId =
          workout.clientSyncId.trim().isNotEmpty
              ? workout.clientSyncId
              : ClientSyncIdGenerator.generate(
                startTime: workout.startTime,
                userId: workout.userId,
              );

      final workoutId = await txn.insert(_workoutsTable, {
        'type': workout.type.name,
        'status': workout.status.name,
        'start_time': workout.startTime?.toIso8601String(),
        'end_time': workout.endTime?.toIso8601String(),
        'paused_duration':
            workout.pausedDuration == null
                ? null
                : workout.effectivePausedDuration.inSeconds,
        'metrics_version': workout.metricsVersion,
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
        'remote_activity_id': workout.remoteActivityId,
        'client_sync_id': clientSyncId,
        'synced': workout.remoteActivityId != null ? 1 : 0,
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

      // Insert status changes
      if (workout.statusChanges.isNotEmpty) {
        final batch = txn.batch();
        for (final statusChange in workout.statusChanges) {
          batch.insert(_statusChangesTable, {
            'workout_id': workoutId,
            'status': statusChange.status.name,
            'timestamp': statusChange.timestamp.toIso8601String(),
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
      where: 'user_id = ? AND deleted_locally = 0',
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

      // Get status changes for this workout
      final statusChanges = await db.query(
        _statusChangesTable,
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'timestamp ASC',
      );

      result.add(_mapToWorkoutEntity(workoutMap, points, statusChanges));
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
      where: 'id = ? AND deleted_locally = 0',
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

    final statusChanges = await db.query(
      _statusChangesTable,
      where: 'workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'timestamp ASC',
    );

    return _mapToWorkoutEntity(workouts.first, points, statusChanges);
  }

  /// Delete a workout
  Future<void> deleteWorkoutFromLocalDatabase(int workoutId) async {
    final db = await database;
    await db.transaction((txn) async {
      final workouts = await txn.query(
        _workoutsTable,
        columns: ['id', 'remote_activity_id', 'user_id'],
        where: 'id = ?',
        whereArgs: [workoutId],
        limit: 1,
      );

      if (workouts.isEmpty) {
        return;
      }

      final workout = workouts.first;
      final remoteActivityId = workout['remote_activity_id'];

      if (remoteActivityId == null) {
        await txn.delete(
          _workoutsTable,
          where: 'id = ?',
          whereArgs: [workoutId],
        );
        return;
      }

      final now = DateTime.now().toIso8601String();
      await txn.insert(_workoutDeleteQueueTable, {
        'local_workout_id': workoutId,
        'remote_activity_id': EnsureTypeHelper.ensureInt(remoteActivityId),
        'user_id': EnsureTypeHelper.ensureInt(workout['user_id']),
        'status': WorkoutDeleteQueueStatus.queued.name,
        'retry_count': 0,
        'last_error': null,
        'next_retry_at': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.update(
        _workoutsTable,
        {'deleted_locally': 1, 'synced': 1},
        where: 'id = ?',
        whereArgs: [workoutId],
      );
    });
  }

  /// Get unsynced workouts
  Future<List<WorkoutSessionEntity>> getUnsyncedWorkoutsFromLocalDatabase(
    int userId,
  ) async {
    final db = await database;

    final workouts = await db.query(
      _workoutsTable,
      where: 'user_id = ? AND synced = 0 AND deleted_locally = 0',
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

      final statusChanges = await db.query(
        _statusChangesTable,
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'timestamp ASC',
      );

      result.add(_mapToWorkoutEntity(workoutMap, points, statusChanges));
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

  /// Update remote activity ID after successful push
  Future<void> updateRemoteActivityId(int localId, int remoteId) async {
    final db = await database;
    await db.update(
      _workoutsTable,
      {'remote_activity_id': remoteId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<WorkoutDeleteQueueEntry>> getWorkoutDeletesReadyForSync(
    int userId,
    DateTime now,
  ) async {
    final db = await database;
    final rows = await db.query(
      _workoutDeleteQueueTable,
      where: '''
        user_id = ?
        AND status IN (?, ?)
        AND (next_retry_at IS NULL OR next_retry_at <= ?)
      ''',
      whereArgs: [
        userId,
        WorkoutDeleteQueueStatus.queued.name,
        WorkoutDeleteQueueStatus.retrying.name,
        now.toIso8601String(),
      ],
      orderBy: 'created_at ASC',
    );

    return rows.map(WorkoutDeleteQueueEntry.fromMap).toList();
  }

  Future<void> markWorkoutDeleteDeleting(int queueId) async {
    final db = await database;
    await db.update(
      _workoutDeleteQueueTable,
      {
        'status': WorkoutDeleteQueueStatus.deleting.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> markWorkoutDeleteRetrying({
    required int queueId,
    required int retryCount,
    required String error,
    required DateTime nextRetryAt,
  }) async {
    final db = await database;
    await db.update(
      _workoutDeleteQueueTable,
      {
        'status': WorkoutDeleteQueueStatus.retrying.name,
        'retry_count': retryCount,
        'last_error': error,
        'next_retry_at': nextRetryAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> completeWorkoutDelete({
    required int queueId,
    required int localWorkoutId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        _workoutsTable,
        where: 'id = ?',
        whereArgs: [localWorkoutId],
      );
      await txn.delete(
        _workoutDeleteQueueTable,
        where: 'id = ?',
        whereArgs: [queueId],
      );
    });
  }

  Future<void> resetStaleWorkoutDeletes(DateTime staleBefore) async {
    final db = await database;
    await db.update(
      _workoutDeleteQueueTable,
      {
        'status': WorkoutDeleteQueueStatus.queued.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'status = ? AND updated_at < ?',
      whereArgs: [
        WorkoutDeleteQueueStatus.deleting.name,
        staleBefore.toIso8601String(),
      ],
    );
  }

  Future<int> insertWorkoutImage(ActivityImageEntity image) async {
    final db = await database;
    return await db.insert(_workoutImagesTable, _activityImageToMap(image));
  }

  Future<List<ActivityImageEntity>> getWorkoutImages(int workoutId) async {
    final db = await database;
    final rows = await db.query(
      _workoutImagesTable,
      where: 'workout_id = ? AND status != ?',
      whereArgs: [workoutId, ActivityImageSyncStatus.deleted.name],
      orderBy: 'sort_order ASC, created_at ASC',
    );

    return rows.map(_mapToActivityImageEntity).toList();
  }

  Future<ActivityImageEntity?> getWorkoutImage(int localImageId) async {
    final db = await database;
    final rows = await db.query(
      _workoutImagesTable,
      where: 'id = ?',
      whereArgs: [localImageId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _mapToActivityImageEntity(rows.first);
  }

  Future<List<ActivityImageEntity>> getImagesReadyForSync(
    int userId,
    DateTime now,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT wi.*
      FROM $_workoutImagesTable wi
      JOIN $_workoutsTable w ON w.id = wi.workout_id
      WHERE w.user_id = ?
      AND wi.status IN (?, ?, ?, ?)
      AND (wi.next_retry_at IS NULL OR wi.next_retry_at <= ?)
      ORDER BY wi.created_at ASC
    ''',
      [
        userId,
        ActivityImageSyncStatus.queued.name,
        ActivityImageSyncStatus.waitingForActivitySync.name,
        ActivityImageSyncStatus.retrying.name,
        ActivityImageSyncStatus.deleteQueued.name,
        now.toIso8601String(),
      ],
    );

    return rows.map(_mapToActivityImageEntity).toList();
  }

  Future<List<ActivityImageEntity>> getActiveImagesForJanitor(
    int userId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT wi.*
      FROM $_workoutImagesTable wi
      JOIN $_workoutsTable w ON w.id = wi.workout_id
      WHERE w.user_id = ?
      AND wi.status IN (?, ?, ?, ?, ?, ?, ?)
      ORDER BY wi.created_at ASC
    ''',
      [
        userId,
        ActivityImageSyncStatus.queued.name,
        ActivityImageSyncStatus.waitingForActivitySync.name,
        ActivityImageSyncStatus.uploading.name,
        ActivityImageSyncStatus.retrying.name,
        ActivityImageSyncStatus.deleteQueued.name,
        ActivityImageSyncStatus.deleting.name,
        ActivityImageSyncStatus.replaceQueued.name,
      ],
    );

    return rows.map(_mapToActivityImageEntity).toList();
  }

  Future<bool> markImageUploadingIfReady(int localImageId) async {
    final db = await database;
    final updated = await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.uploading.name,
        'retry_count': 0,
        'last_error': null,
        'next_retry_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status IN (?, ?, ?)',
      whereArgs: [
        localImageId,
        ActivityImageSyncStatus.queued.name,
        ActivityImageSyncStatus.waitingForActivitySync.name,
        ActivityImageSyncStatus.retrying.name,
      ],
    );

    return updated > 0;
  }

  Future<bool> markImageWaitingForActivitySyncIfReady(int localImageId) async {
    final db = await database;
    final updated = await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.waitingForActivitySync.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status IN (?, ?, ?)',
      whereArgs: [
        localImageId,
        ActivityImageSyncStatus.queued.name,
        ActivityImageSyncStatus.waitingForActivitySync.name,
        ActivityImageSyncStatus.retrying.name,
      ],
    );

    return updated > 0;
  }

  Future<ActivityImageSyncStatus?> recordImageUploadResult({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) async {
    final db = await database;
    return db.transaction<ActivityImageSyncStatus?>((txn) async {
      final rows = await txn.query(
        _workoutImagesTable,
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [localImageId],
        limit: 1,
      );

      if (rows.isEmpty) {
        return null;
      }

      final currentStatus = activityImageSyncStatusFromName(
        rows.first['status'] as String?,
      );
      final finalStatus =
          _shouldKeepUploadedImageAfterRemoteConfirm(currentStatus)
              ? ActivityImageSyncStatus.uploaded
              : ActivityImageSyncStatus.deleteQueued;

      await txn.update(
        _workoutImagesTable,
        {
          'remote_activity_id': remoteActivityId,
          'remote_image_id': remoteImageId,
          'remote_url': remoteUrl,
          'remote_url_expires_at': remoteUrlExpiresAt?.toIso8601String(),
          's3_key': s3Key,
          'status': finalStatus.name,
          'retry_count': 0,
          'last_error': null,
          'next_retry_at': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [localImageId],
      );

      return finalStatus;
    });
  }

  Future<void> markImageRetrying({
    required int localImageId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.retrying.name,
        'retry_count': retryCount,
        'last_error': error,
        'next_retry_at': nextRetryAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localImageId],
    );
  }

  Future<void> markImageDeleteQueuedRetrying({
    required int localImageId,
    required String error,
    required DateTime nextRetryAt,
    required int retryCount,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.deleteQueued.name,
        'retry_count': retryCount,
        'last_error': error,
        'next_retry_at': nextRetryAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localImageId],
    );
  }

  Future<void> markImageFailed({
    required int localImageId,
    required String error,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.failed.name,
        'last_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localImageId],
    );
  }

  Future<void> markImageDeleteQueued(int localImageId) async {
    await _updateWorkoutImageStatus(
      localImageId,
      ActivityImageSyncStatus.deleteQueued,
    );
  }

  Future<void> markImageReplaceQueued(int localImageId) async {
    await _updateWorkoutImageStatus(
      localImageId,
      ActivityImageSyncStatus.replaceQueued,
    );
  }

  Future<void> markReplaceQueuedImagesDeleteQueued(int workoutId) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.deleteQueued.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'workout_id = ? AND status = ?',
      whereArgs: [workoutId, ActivityImageSyncStatus.replaceQueued.name],
    );
  }

  Future<void> markImageDeleting(int localImageId) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': ActivityImageSyncStatus.deleting.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [localImageId, ActivityImageSyncStatus.deleteQueued.name],
    );
  }

  Future<void> markImageDeleted(int localImageId) async {
    await _updateWorkoutImageStatus(
      localImageId,
      ActivityImageSyncStatus.deleted,
      clearRetryState: true,
    );
  }

  Future<void> resetStaleUploadingImages(DateTime staleBefore) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE $_workoutImagesTable
      SET status = CASE
        WHEN status = ? THEN ?
        ELSE ?
      END,
      updated_at = ?
      WHERE status IN (?, ?)
      AND updated_at < ?
    ''',
      [
        ActivityImageSyncStatus.deleting.name,
        ActivityImageSyncStatus.deleteQueued.name,
        ActivityImageSyncStatus.queued.name,
        DateTime.now().toIso8601String(),
        ActivityImageSyncStatus.uploading.name,
        ActivityImageSyncStatus.deleting.name,
        staleBefore.toIso8601String(),
      ],
    );
  }

  bool _shouldKeepUploadedImageAfterRemoteConfirm(
    ActivityImageSyncStatus status,
  ) {
    return status == ActivityImageSyncStatus.uploading ||
        status == ActivityImageSyncStatus.queued ||
        status == ActivityImageSyncStatus.waitingForActivitySync ||
        status == ActivityImageSyncStatus.retrying ||
        status == ActivityImageSyncStatus.uploaded;
  }

  Future<void> updateRemoteImageUrl({
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'remote_url': remoteUrl,
        'remote_url_expires_at': remoteUrlExpiresAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'remote_image_id = ?',
      whereArgs: [remoteImageId],
    );
  }

  Future<void> updateRemoteImageMetadata({
    required int localImageId,
    required int remoteActivityId,
    required int remoteImageId,
    required String remoteUrl,
    required DateTime? remoteUrlExpiresAt,
    required String s3Key,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'remote_activity_id': remoteActivityId,
        'remote_image_id': remoteImageId,
        'remote_url': remoteUrl,
        'remote_url_expires_at': remoteUrlExpiresAt?.toIso8601String(),
        's3_key': s3Key,
        'status': ActivityImageSyncStatus.uploaded.name,
        'retry_count': 0,
        'last_error': null,
        'next_retry_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localImageId],
    );
  }

  /// Backfill missing client sync IDs for older local rows
  Future<void> ensureClientSyncIds() async {
    final db = await database;
    await _ensureClientSyncIdsOnDatabase(db);
  }

  /// Map database results to entity
  WorkoutSessionEntity _mapToWorkoutEntity(
    Map<String, dynamic> workoutMap,
    List<Map<String, dynamic>> pointsMap,
    List<Map<String, dynamic>> statusChangesMap,
  ) {
    // Parse tracking points
    List<TrackingPointEntity> trackingPoints =
        pointsMap.map((point) {
          return TrackingPointEntity(
            latitude: _toRequiredDouble(point['latitude']),
            longitude: _toRequiredDouble(point['longitude']),
            altitude: _toNullableDouble(point['altitude']),
            accuracy: _toNullableDouble(point['accuracy']),
            speed: _toNullableDouble(point['speed']),
            heading: _toNullableDouble(point['heading']),
            timestamp: DateTime.parse(point['timestamp'] as String),
          );
        }).toList();

    // Parse status changes
    List<StatusChangeEvent> statusChanges =
        statusChangesMap.map((statusChange) {
          return StatusChangeEvent(
            status: WorkoutStatus.values.firstWhere(
              (s) => s.name == statusChange['status'],
              orElse: () => WorkoutStatus.active,
            ),
            timestamp: DateTime.parse(statusChange['timestamp'] as String),
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

    final userId = EnsureTypeHelper.ensureInt(workoutMap['user_id']);
    final localWorkoutId = EnsureTypeHelper.ensureInt(workoutMap['id']);
    final startTime =
        workoutMap['start_time'] != null
            ? DateTime.parse(workoutMap['start_time'] as String)
            : null;
    final clientSyncIdValue = (workoutMap['client_sync_id'] as String?)?.trim();
    final remoteActivityIdValue = workoutMap['remote_activity_id'];

    return WorkoutSessionEntity(
      id: localWorkoutId.toString(),
      clientSyncId:
          clientSyncIdValue != null && clientSyncIdValue.isNotEmpty
              ? clientSyncIdValue
              : ClientSyncIdGenerator.legacyFromLocalRow(
                localWorkoutId: localWorkoutId,
                userId: userId,
                startTime: startTime,
              ),
      remoteActivityId:
          remoteActivityIdValue != null
              ? EnsureTypeHelper.ensureInt(remoteActivityIdValue)
              : null,
      metricsVersion: _normalizeMetricsVersion(workoutMap['metrics_version']),
      type: type,
      status: status,
      startTime: startTime,
      endTime:
          workoutMap['end_time'] != null
              ? DateTime.parse(workoutMap['end_time'] as String)
              : null,
      pausedDuration:
          workoutMap['paused_duration'] != null
              ? Duration(seconds: workoutMap['paused_duration'] as int)
              : null,
      totalDistance: _toRequiredDouble(workoutMap['total_distance']),
      averageSpeed: _toRequiredDouble(workoutMap['average_speed']),
      maxSpeed: _toRequiredDouble(workoutMap['max_speed']),
      averagePace: _toNullableDouble(workoutMap['average_pace']),
      calories: workoutMap['calories'] as int?,
      elevationGain: _toNullableDouble(workoutMap['elevation_gain']),
      elevationLoss: _toNullableDouble(workoutMap['elevation_loss']),
      userId: userId,
      name: workoutMap['name'] as String?,
      notes: workoutMap['notes'] as String?,
      trackingPoints: trackingPoints,
      statusChanges: statusChanges,
    );
  }

  Map<String, Object?> _activityImageToMap(ActivityImageEntity image) {
    return {
      'workout_id': image.localWorkoutId,
      'remote_activity_id': image.remoteActivityId,
      'remote_image_id': image.remoteImageId,
      'client_image_id': image.clientImageId,
      'local_path': image.localPath,
      'thumbnail_path': image.thumbnailPath,
      'remote_url': image.remoteUrl,
      'remote_url_expires_at': image.remoteUrlExpiresAt?.toIso8601String(),
      's3_key': image.s3Key,
      'content_type': image.contentType,
      'size_bytes': image.sizeBytes,
      'checksum_sha256': image.checksumSha256,
      'width': image.width,
      'height': image.height,
      'sort_order': image.sortOrder,
      'caption': image.caption,
      'status': image.status.name,
      'retry_count': image.retryCount,
      'last_error': image.lastError,
      'next_retry_at': image.nextRetryAt?.toIso8601String(),
      'created_at': image.createdAt.toIso8601String(),
      'updated_at': image.updatedAt.toIso8601String(),
    };
  }

  ActivityImageEntity _mapToActivityImageEntity(Map<String, dynamic> map) {
    return ActivityImageEntity(
      localId: _toNullableInt(map['id']),
      localWorkoutId: EnsureTypeHelper.ensureInt(map['workout_id']),
      remoteActivityId: _toNullableInt(map['remote_activity_id']),
      remoteImageId: _toNullableInt(map['remote_image_id']),
      clientImageId: map['client_image_id'] as String,
      localPath: map['local_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String?,
      remoteUrl: map['remote_url'] as String?,
      remoteUrlExpiresAt: _toNullableDateTime(map['remote_url_expires_at']),
      s3Key: map['s3_key'] as String?,
      contentType: map['content_type'] as String,
      sizeBytes: EnsureTypeHelper.ensureInt(map['size_bytes']),
      checksumSha256: map['checksum_sha256'] as String?,
      width: _toNullableInt(map['width']),
      height: _toNullableInt(map['height']),
      sortOrder: EnsureTypeHelper.ensureInt(map['sort_order']),
      caption: map['caption'] as String?,
      status: activityImageSyncStatusFromName(map['status'] as String?),
      retryCount: EnsureTypeHelper.ensureInt(map['retry_count']),
      lastError: map['last_error'] as String?,
      nextRetryAt: _toNullableDateTime(map['next_retry_at']),
      createdAt: _toRequiredDateTime(map['created_at']),
      updatedAt: _toRequiredDateTime(map['updated_at']),
    );
  }

  /// Clear all data (useful for logout)
  Future<void> clearAllDataFromLocalDatabase() async {
    final db = await database;
    await db.delete(_workoutImagesTable);
    await db.delete(_workoutDeleteQueueTable);
    await db.delete(_statusChangesTable);
    await db.delete(_trackingPointsTable);
    await db.delete(_workoutsTable);
  }

  Future<void> close() async {
    final db = _database;
    _database = null;

    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  Future<void> _ensureSyncColumns(Database db) async {
    if (!await _hasColumn(db, _workoutsTable, 'remote_activity_id')) {
      await db.execute(
        'ALTER TABLE $_workoutsTable ADD COLUMN remote_activity_id INTEGER',
      );
    }

    if (!await _hasColumn(db, _workoutsTable, 'client_sync_id')) {
      await db.execute(
        'ALTER TABLE $_workoutsTable ADD COLUMN client_sync_id TEXT',
      );
    }
  }

  Future<void> _ensureWorkoutDeleteSupport(Database db) async {
    if (!await _hasColumn(db, _workoutsTable, 'deleted_locally')) {
      await db.execute(
        'ALTER TABLE $_workoutsTable ADD COLUMN deleted_locally INTEGER DEFAULT 0',
      );
    }

    await _createWorkoutDeleteQueueTable(db);
  }

  Future<void> _ensureWorkoutImageSupport(Database db) async {
    await _createWorkoutImagesTable(db);
  }

  Future<void> _ensureMetricsVersionColumn(Database db) async {
    if (!await _hasColumn(db, _workoutsTable, 'metrics_version')) {
      await db.execute('''
        ALTER TABLE $_workoutsTable
        ADD COLUMN metrics_version INTEGER NOT NULL DEFAULT 1
          CHECK(metrics_version IN (1, 2))
      ''');
    }
  }

  Future<void> _createWorkoutDeleteQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutDeleteQueueTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_workout_id INTEGER NOT NULL,
        remote_activity_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        next_retry_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(remote_activity_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workout_delete_queue_user_status
      ON $_workoutDeleteQueueTable(user_id, status, next_retry_at)
      ''');
  }

  Future<void> _createWorkoutImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutImagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id INTEGER NOT NULL,
        remote_activity_id INTEGER,
        remote_image_id INTEGER,
        client_image_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        thumbnail_path TEXT,
        remote_url TEXT,
        remote_url_expires_at TEXT,
        s3_key TEXT,
        content_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        checksum_sha256 TEXT,
        width INTEGER,
        height INTEGER,
        sort_order INTEGER DEFAULT 0,
        caption TEXT,
        status TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        next_retry_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (workout_id) REFERENCES $_workoutsTable (id) ON DELETE CASCADE,
        UNIQUE(workout_id, client_image_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workout_images_workout_id
      ON $_workoutImagesTable(workout_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workout_images_status_next_retry
      ON $_workoutImagesTable(status, next_retry_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_workout_images_remote_activity_id
      ON $_workoutImagesTable(remote_activity_id)
    ''');
  }

  Future<void> _ensureClientSyncIdsOnDatabase(Database db) async {
    final workoutsMissingClientSyncId = await db.query(
      _workoutsTable,
      columns: ['id', 'user_id', 'start_time'],
      where: 'client_sync_id IS NULL OR TRIM(client_sync_id) = ?',
      whereArgs: [''],
    );

    if (workoutsMissingClientSyncId.isEmpty) {
      return;
    }

    final batch = db.batch();

    for (final workout in workoutsMissingClientSyncId) {
      final localWorkoutId = EnsureTypeHelper.ensureInt(workout['id']);
      final userId = EnsureTypeHelper.ensureInt(workout['user_id']);
      final startTime =
          workout['start_time'] != null
              ? DateTime.tryParse(workout['start_time'] as String)
              : null;

      batch.update(
        _workoutsTable,
        {
          'client_sync_id': ClientSyncIdGenerator.legacyFromLocalRow(
            localWorkoutId: localWorkoutId,
            userId: userId,
            startTime: startTime,
          ),
        },
        where: 'id = ?',
        whereArgs: [localWorkoutId],
      );
    }

    await batch.commit(noResult: true);
  }

  Future<bool> _hasColumn(
    Database db,
    String tableName,
    String columnName,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($tableName)');

    return result.any((column) => column['name'] == columnName);
  }

  double _toRequiredDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return EnsureTypeHelper.formatAndEnsureDouble(value);
  }

  double? _toNullableDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return EnsureTypeHelper.formatAndEnsureDouble(value);
  }

  int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    return EnsureTypeHelper.ensureInt(value);
  }

  int _normalizeMetricsVersion(dynamic value) {
    final version = EnsureTypeHelper.ensureInt(value);
    return WorkoutSessionEntity.isSupportedMetricsVersion(version)
        ? version
        : WorkoutSessionEntity.legacyMetricsVersion;
  }

  DateTime? _toNullableDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value as String);
  }

  DateTime _toRequiredDateTime(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }

    return DateTime.now();
  }

  Future<void> _updateWorkoutImageStatus(
    int localImageId,
    ActivityImageSyncStatus status, {
    bool clearRetryState = false,
  }) async {
    final db = await database;
    await db.update(
      _workoutImagesTable,
      {
        'status': status.name,
        if (clearRetryState) 'retry_count': 0,
        if (clearRetryState) 'last_error': null,
        if (clearRetryState) 'next_retry_at': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localImageId],
    );
  }

  // ==================== SQL-BASED TOTALS & PAGINATION ====================

  /// Get workout statistics using SQL aggregation
  Future<WorkoutStatistics> getWorkoutStatistics(
    int userId, {
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    // Build where clause
    final whereConditions = <String>['user_id = ?', 'deleted_locally = 0'];
    final whereArgs = <dynamic>[userId];

    if (workoutType != null) {
      whereConditions.add('type = ?');
      whereArgs.add(workoutType);
    }

    if (startDate != null) {
      whereConditions.add('start_time >= ?');
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereConditions.add('start_time <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    final whereClause = whereConditions.join(' AND ');

    // Execute aggregation query
    final result = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_workouts,
        SUM(total_distance) as total_distance,
        AVG(total_distance) as avg_distance,
        SUM(calories) as total_calories,
        AVG(calories) as avg_calories,
        MAX(total_distance) as max_distance,
        MIN(start_time) as first_workout_date,
        MAX(start_time) as last_workout_date,
        SUM($_activeDurationSecondsSql) as total_duration_seconds,
        AVG($_activeDurationSecondsSql) as avg_duration_seconds
      FROM $_workoutsTable 
      WHERE $whereClause
    ''', whereArgs);

    if (result.isEmpty) {
      return WorkoutStatistics.empty();
    }

    final row = result.first;
    return WorkoutStatistics(
      totalWorkouts: EnsureTypeHelper.ensureInt(row['total_workouts']),
      totalDistance: EnsureTypeHelper.formatAndEnsureDouble(
        row['total_distance'],
      ),
      averageDistance: EnsureTypeHelper.formatAndEnsureDouble(
        row['avg_distance'],
      ),
      totalCalories: EnsureTypeHelper.ensureInt(row['total_calories']),
      averageCalories: EnsureTypeHelper.formatAndEnsureDouble(
        row['avg_calories'],
      ),
      maxDistance: EnsureTypeHelper.formatAndEnsureDouble(row['max_distance']),
      totalDuration: Duration(
        seconds: EnsureTypeHelper.ensureInt(row['total_duration_seconds']),
      ),
      averageDuration: Duration(
        seconds: EnsureTypeHelper.ensureInt(row['avg_duration_seconds']),
      ),
      firstWorkoutDate:
          row['first_workout_date'] != null
              ? DateTime.tryParse(row['first_workout_date'] as String)
              : null,
      lastWorkoutDate:
          row['last_workout_date'] != null
              ? DateTime.tryParse(row['last_workout_date'] as String)
              : null,
    );
  }

  /// Get workout statistics grouped by type
  Future<Map<String, WorkoutStatistics>> getWorkoutStatisticsByType(
    int userId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT 
        type,
        COUNT(*) as total_workouts,
        SUM(total_distance) as total_distance,
        AVG(total_distance) as avg_distance,
        SUM(calories) as total_calories,
        AVG(calories) as avg_calories,
        MAX(total_distance) as max_distance,
        MIN(start_time) as first_workout_date,
        MAX(start_time) as last_workout_date,
        SUM($_activeDurationSecondsSql) as total_duration_seconds,
        AVG($_activeDurationSecondsSql) as avg_duration_seconds
      FROM $_workoutsTable 
      WHERE user_id = ? AND deleted_locally = 0
      GROUP BY type
    ''',
      [userId],
    );

    final Map<String, WorkoutStatistics> statistics = {};

    for (final row in result) {
      final type = row['type'] as String;
      statistics[type] = WorkoutStatistics(
        totalWorkouts: EnsureTypeHelper.ensureInt(row['total_workouts']),
        totalDistance: EnsureTypeHelper.formatAndEnsureDouble(
          row['total_distance'],
        ),
        averageDistance: EnsureTypeHelper.formatAndEnsureDouble(
          row['avg_distance'],
        ),
        totalCalories: EnsureTypeHelper.ensureInt(row['total_calories']),
        averageCalories: EnsureTypeHelper.formatAndEnsureDouble(
          row['avg_calories'],
        ),
        maxDistance: EnsureTypeHelper.formatAndEnsureDouble(
          row['max_distance'],
        ),
        totalDuration: Duration(
          seconds: EnsureTypeHelper.ensureInt(row['total_duration_seconds']),
        ),
        averageDuration: Duration(
          seconds: EnsureTypeHelper.ensureInt(row['avg_duration_seconds']),
        ),
        firstWorkoutDate:
            row['first_workout_date'] != null
                ? DateTime.tryParse(row['first_workout_date'] as String)
                : null,
        lastWorkoutDate:
            row['last_workout_date'] != null
                ? DateTime.tryParse(row['last_workout_date'] as String)
                : null,
      );
    }

    return statistics;
  }

  /// Get paginated workouts with filtering (lightweight - no tracking points)
  Future<PaginatedWorkouts> getPaginatedWorkouts(
    int userId, {
    int page = 1,
    int limit = 20,
    String? workoutType,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    bool loadTrackingPoints = false,
  }) async {
    final db = await database;

    // Build where clause
    final whereConditions = <String>['user_id = ?', 'deleted_locally = 0'];
    final whereArgs = <dynamic>[userId];

    if (workoutType != null) {
      whereConditions.add('type = ?');
      whereArgs.add(workoutType);
    }

    if (startDate != null) {
      whereConditions.add('start_time >= ?');
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereConditions.add('start_time <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereConditions.add('(name LIKE ? OR notes LIKE ?)');
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }

    final whereClause = whereConditions.join(' AND ');

    // Get total count for pagination
    final countResult = await db.rawQuery('''
      SELECT COUNT(*) as total 
      FROM $_workoutsTable 
      WHERE $whereClause
    ''', whereArgs);

    final totalCount = EnsureTypeHelper.ensureInt(countResult.first['total']);

    // Calculate pagination
    final offset = (page - 1) * limit;
    final totalPages = (totalCount / limit).ceil();

    // Get paginated workouts
    final workouts = await db.query(
      _workoutsTable,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );

    // Convert to entities
    List<WorkoutSessionEntity> workoutEntities = [];

    for (final workoutMap in workouts) {
      final workoutId = workoutMap['id'] as int;

      // Optionally load tracking points and status changes
      List<Map<String, dynamic>> points = [];
      List<Map<String, dynamic>> statusChanges = [];

      if (loadTrackingPoints) {
        points = await db.query(
          _trackingPointsTable,
          where: 'workout_id = ?',
          whereArgs: [workoutId],
          orderBy: 'timestamp ASC',
        );

        statusChanges = await db.query(
          _statusChangesTable,
          where: 'workout_id = ?',
          whereArgs: [workoutId],
          orderBy: 'timestamp ASC',
        );
      }

      workoutEntities.add(
        _mapToWorkoutEntity(workoutMap, points, statusChanges),
      );
    }

    return PaginatedWorkouts(
      workouts: workoutEntities,
      currentPage: page,
      totalPages: totalPages,
      totalCount: totalCount,
      hasNextPage: page < totalPages,
      hasPreviousPage: page > 1,
      limit: limit,
    );
  }

  /// Get workout count for quick stats
  Future<int> getWorkoutCount(int userId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count 
      FROM $_workoutsTable 
      WHERE user_id = ? AND deleted_locally = 0
    ''',
      [userId],
    );

    return EnsureTypeHelper.ensureInt(result.first['count']);
  }
}

// ==================== DATA MODELS ====================

enum WorkoutDeleteQueueStatus { queued, deleting, retrying, deleted, failed }

class WorkoutDeleteQueueEntry {
  final int id;
  final int localWorkoutId;
  final int remoteActivityId;
  final int userId;
  final WorkoutDeleteQueueStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkoutDeleteQueueEntry({
    required this.id,
    required this.localWorkoutId,
    required this.remoteActivityId,
    required this.userId,
    required this.status,
    required this.retryCount,
    this.lastError,
    this.nextRetryAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkoutDeleteQueueEntry.fromMap(Map<String, dynamic> map) {
    return WorkoutDeleteQueueEntry(
      id: EnsureTypeHelper.ensureInt(map['id']),
      localWorkoutId: EnsureTypeHelper.ensureInt(map['local_workout_id']),
      remoteActivityId: EnsureTypeHelper.ensureInt(map['remote_activity_id']),
      userId: EnsureTypeHelper.ensureInt(map['user_id']),
      status: WorkoutDeleteQueueStatus.values.firstWhere(
        (status) => status.name == map['status'],
        orElse: () => WorkoutDeleteQueueStatus.queued,
      ),
      retryCount: EnsureTypeHelper.ensureInt(map['retry_count']),
      lastError: map['last_error'] as String?,
      nextRetryAt:
          map['next_retry_at'] != null
              ? DateTime.tryParse(map['next_retry_at'] as String)
              : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

/// Workout statistics model
class WorkoutStatistics {
  final int totalWorkouts;
  final double totalDistance;
  final double averageDistance;
  final int totalCalories;
  final double averageCalories;
  final double maxDistance;
  final Duration totalDuration;
  final Duration averageDuration;
  final DateTime? firstWorkoutDate;
  final DateTime? lastWorkoutDate;

  const WorkoutStatistics({
    required this.totalWorkouts,
    required this.totalDistance,
    required this.averageDistance,
    required this.totalCalories,
    required this.averageCalories,
    required this.maxDistance,
    required this.totalDuration,
    required this.averageDuration,
    this.firstWorkoutDate,
    this.lastWorkoutDate,
  });

  factory WorkoutStatistics.empty() {
    return const WorkoutStatistics(
      totalWorkouts: 0,
      totalDistance: 0.0,
      averageDistance: 0.0,
      totalCalories: 0,
      averageCalories: 0.0,
      maxDistance: 0.0,
      totalDuration: Duration.zero,
      averageDuration: Duration.zero,
    );
  }

  String get formattedTotalDistance {
    if (totalDistance >= 1000) {
      return '${(totalDistance / 1000).toStringAsFixed(1)} km';
    } else {
      return '${totalDistance.toInt()} m';
    }
  }

  String get formattedTotalDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}

/// Paginated workouts model
class PaginatedWorkouts {
  final List<WorkoutSessionEntity> workouts;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasNextPage;
  final bool hasPreviousPage;
  final int limit;

  const PaginatedWorkouts({
    required this.workouts,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.hasNextPage,
    required this.hasPreviousPage,
    required this.limit,
  });
}
