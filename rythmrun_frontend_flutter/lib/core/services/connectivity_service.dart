import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Enum representing network connectivity status
enum ConnectivityStatus {
  connected, // A network interface is available
  slow, // Retained for externally reported or legacy slow states
  disconnected, // No network interface is available
}

/// Service for monitoring platform-reported network connectivity.
class ConnectivityService {
  static ConnectivityService? mockInstance;
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => mockInstance ?? _instance;
  ConnectivityService._internal() : this._fromConnectivity(Connectivity());
  ConnectivityService._fromConnectivity(Connectivity connectivity)
    : _checkPlatformConnectivity = connectivity.checkConnectivity,
      _connectivityChanges = connectivity.onConnectivityChanged;

  @visibleForTesting
  ConnectivityService.test({
    required Future<List<ConnectivityResult>> Function() checkConnectivity,
    required Stream<List<ConnectivityResult>> connectivityChanges,
  }) : _checkPlatformConnectivity = checkConnectivity,
       _connectivityChanges = connectivityChanges;

  final Future<List<ConnectivityResult>> Function() _checkPlatformConnectivity;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  ConnectivityStatus _currentStatus = ConnectivityStatus.connected;
  bool _isMonitoring = false;
  int _monitoringGeneration = 0;
  int _connectivityChangeRevision = 0;

  /// Stream of connectivity status changes
  Stream<ConnectivityStatus> get statusStream {
    return Stream<ConnectivityStatus>.multi((controller) {
      ConnectivityStatus? lastStatus;
      void addStatus(ConnectivityStatus status) {
        if (status == lastStatus) return;
        lastStatus = status;
        controller.add(status);
      }

      final subscription = _statusController.stream.listen(
        addStatus,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
      addStatus(_currentStatus);
    });
  }

  /// Current connectivity status
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Start monitoring connectivity
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    final monitoringGeneration = ++_monitoringGeneration;

    // Listen to connectivity changes
    _connectivitySubscription = _connectivityChanges.listen((
      List<ConnectivityResult> results,
    ) {
      if (!_isCurrentMonitoringGeneration(monitoringGeneration)) return;
      _connectivityChangeRevision += 1;
      _handleConnectivityChange(results);
    });

    await _checkConnectivity(monitoringGeneration, _connectivityChangeRevision);
  }

  /// Stop monitoring connectivity
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringGeneration += 1;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity(
    int monitoringGeneration,
    int expectedChangeRevision,
  ) async {
    try {
      final results = await _checkPlatformConnectivity();
      if (_isCurrentMonitoringGeneration(monitoringGeneration) &&
          _connectivityChangeRevision == expectedChangeRevision) {
        _handleConnectivityChange(results);
      }
    } catch (e) {
      if (!_isCurrentMonitoringGeneration(monitoringGeneration) ||
          _connectivityChangeRevision != expectedChangeRevision) {
        return;
      }
      debugPrint('❌ Error checking connectivity: $e');
      _updateStatus(ConnectivityStatus.disconnected);
    }
  }

  bool _isCurrentMonitoringGeneration(int generation) {
    return _isMonitoring && _monitoringGeneration == generation;
  }

  /// Handle connectivity change
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      _updateStatus(ConnectivityStatus.disconnected);
      return;
    }

    _updateStatus(ConnectivityStatus.connected);
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
