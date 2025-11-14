import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Enum representing network connectivity status
enum ConnectivityStatus {
  connected, // Good internet connection
  slow, // Slow internet connection
  disconnected, // No internet connection
}

/// Service for monitoring network connectivity and speed
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _speedCheckTimer;

  ConnectivityStatus _currentStatus = ConnectivityStatus.connected;
  bool _isMonitoring = false;

  /// Stream of connectivity status changes
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  /// Current connectivity status
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Start monitoring connectivity
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    // Check initial status
    _checkConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      _handleConnectivityChange(results);
    });

    // Periodically check internet speed by pinging a reliable server
    _speedCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkInternetSpeed(),
    );
  }

  /// Stop monitoring connectivity
  void stopMonitoring() {
    _isMonitoring = false;
    _connectivitySubscription?.cancel();
    _speedCheckTimer?.cancel();
    _connectivitySubscription = null;
    _speedCheckTimer = null;
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('❌ Error checking connectivity: $e');
      _updateStatus(ConnectivityStatus.disconnected);
    }
  }

  /// Handle connectivity change
  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    // If no connectivity at all
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      _updateStatus(ConnectivityStatus.disconnected);
      return;
    }

    // If connected, check actual internet speed
    await _checkInternetSpeed();
  }

  /// Check internet speed by attempting to connect to a reliable server
  Future<void> _checkInternetSpeed() async {
    try {
      // Try to connect to a reliable server (Google DNS)
      final stopwatch = Stopwatch()..start();

      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 3),
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Connection timeout');
        },
      );

      stopwatch.stop();
      socket.destroy();

      final responseTime = stopwatch.elapsedMilliseconds;

      // Determine status based on response time
      if (responseTime < 500) {
        _updateStatus(ConnectivityStatus.connected);
      } else if (responseTime < 2000) {
        _updateStatus(ConnectivityStatus.slow);
      } else {
        _updateStatus(ConnectivityStatus.slow);
      }
    } on SocketException {
      // No internet connection
      _updateStatus(ConnectivityStatus.disconnected);
    } on TimeoutException {
      // Very slow or no connection
      _updateStatus(ConnectivityStatus.slow);
    } catch (e) {
      debugPrint('❌ Error checking internet speed: $e');
      // On error, assume disconnected
      _updateStatus(ConnectivityStatus.disconnected);
    }
  }

  /// Update status and notify listeners
  void _updateStatus(ConnectivityStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
      debugPrint('🌐 Connectivity status changed: $status');
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}

/// Exception for timeout
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
