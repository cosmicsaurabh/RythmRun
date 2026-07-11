import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:rythmrun_frontend_flutter/core/services/local_db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum LegacyDatabaseVariant {
  version1(userVersion: 1),
  version2(userVersion: 2),
  version3(userVersion: 3),
  version3DeleteQueueHybrid(userVersion: 3),
  version4(userVersion: 4),
  version5(userVersion: 5);

  const LegacyDatabaseVariant({required this.userVersion});

  final int userVersion;

  bool get hasStatusChanges => userVersion >= 2;

  bool get hasSyncColumns => userVersion >= 3;

  bool get hasDeleteSupport =>
      userVersion >= 4 || this == version3DeleteQueueHybrid;

  bool get hasImages => userVersion >= 4;

  bool get hasMetricsVersion => userVersion >= 5;

  // A v2 database upgraded by the shipped v3 code received a nullable column.
  // The delete-queue feature was then shipped without increasing user_version.
  bool get hasNullableClientSyncId => this == version3DeleteQueueHybrid;
}

class LocalDbTestHarness {
  final Directory temporaryDirectory;
  final String databasePath;
  final DatabaseFactory databaseFactory;

  final List<LocalDbService> _services = <LocalDbService>[];
  final List<Database> _databases = <Database>[];

  LocalDbTestHarness._({
    required this.temporaryDirectory,
    required this.databasePath,
    required this.databaseFactory,
  });

  static void initializeFfi() {
    sqfliteFfiInit();
  }

  static Future<LocalDbTestHarness> create() async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'rythmrun_local_db_test_',
    );

    return LocalDbTestHarness._(
      temporaryDirectory: temporaryDirectory,
      databasePath: path.join(temporaryDirectory.path, 'workouts.db'),
      databaseFactory: databaseFactoryFfi,
    );
  }

  Future<LocalDbService> openService() async {
    final service = LocalDbService(
      databaseFactory: databaseFactory,
      databasePath: databasePath,
    );
    _services.add(service);
    await service.database;
    return service;
  }

  Future<Database> createLegacyDatabase(LegacyDatabaseVariant variant) async {
    final database = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: variant.userVersion,
        onCreate: (database, version) async {
          for (final statement in _schemaFor(variant)) {
            await database.execute(statement);
          }
        },
      ),
    );
    _databases.add(database);
    return database;
  }

  Future<Database> createVersion4Database() {
    return createLegacyDatabase(LegacyDatabaseVariant.version4);
  }

  Future<Database> openRawDatabase() async {
    final database = await databaseFactory.openDatabase(databasePath);
    _databases.add(database);
    return database;
  }

  Future<void> dispose() async {
    for (final service in _services.reversed) {
      await service.close();
    }

    for (final database in _databases.reversed) {
      if (database.isOpen) {
        await database.close();
      }
    }

    await databaseFactory.deleteDatabase(databasePath);
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

List<String> _schemaFor(LegacyDatabaseVariant variant) {
  return <String>[
    _workoutsSchema(variant),
    _trackingPointsSchema,
    if (variant.hasStatusChanges) _statusChangesSchema,
    if (variant.hasDeleteSupport) ..._workoutDeleteQueueSchema,
    if (variant.hasImages) ..._workoutImagesSchema,
  ];
}

String _workoutsSchema(LegacyDatabaseVariant variant) {
  final syncColumns =
      variant.hasSyncColumns
          ? '''
      remote_activity_id INTEGER,
      client_sync_id TEXT${variant.hasNullableClientSyncId ? '' : ' NOT NULL'},'''
          : '';
  final deletedLocallyColumn =
      variant.hasDeleteSupport
          ? '      deleted_locally INTEGER DEFAULT 0,'
          : '';
  final metricsVersionColumn =
      variant.hasMetricsVersion
          ? '''
      metrics_version INTEGER NOT NULL DEFAULT 1
        CHECK(metrics_version IN (1, 2)),'''
          : '';

  return '''
    CREATE TABLE workouts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      status TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT,
      paused_duration INTEGER,
$metricsVersionColumn
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
$syncColumns
$deletedLocallyColumn
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      synced INTEGER DEFAULT 0
    )
  ''';
}

const String _trackingPointsSchema = '''
  CREATE TABLE tracking_points (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude REAL,
    accuracy REAL,
    speed REAL,
    heading REAL,
    timestamp TEXT NOT NULL,
    FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE CASCADE
  )
''';

const String _statusChangesSchema = '''
  CREATE TABLE status_changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workout_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE CASCADE
  )
''';

const List<String> _workoutDeleteQueueSchema = <String>[
  '''
    CREATE TABLE workout_delete_queue (
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
  ''',
  '''
    CREATE INDEX idx_workout_delete_queue_user_status
    ON workout_delete_queue(user_id, status, next_retry_at)
  ''',
];

const List<String> _workoutImagesSchema = <String>[
  '''
    CREATE TABLE workout_images (
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
      FOREIGN KEY (workout_id) REFERENCES workouts (id) ON DELETE CASCADE,
      UNIQUE(workout_id, client_image_id)
    )
  ''',
  '''
    CREATE INDEX idx_workout_images_workout_id
    ON workout_images(workout_id)
  ''',
  '''
    CREATE INDEX idx_workout_images_status_next_retry
    ON workout_images(status, next_retry_at)
  ''',
  '''
    CREATE INDEX idx_workout_images_remote_activity_id
    ON workout_images(remote_activity_id)
  ''',
];
