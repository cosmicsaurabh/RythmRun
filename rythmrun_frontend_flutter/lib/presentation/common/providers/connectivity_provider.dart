import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/connectivity_service.dart';

/// Provider for connectivity status
final connectivityStatusProvider =
    StreamProvider<ConnectivityStatus>((ref) {
  final service = ConnectivityService();
  
  // Start monitoring when provider is first accessed
  service.startMonitoring();
  
  // Stop monitoring when provider is disposed
  ref.onDispose(() {
    service.stopMonitoring();
  });
  
  return service.statusStream;
});

/// Provider for current connectivity status (synchronous access)
final currentConnectivityStatusProvider = Provider<ConnectivityStatus>((ref) {
  final asyncStatus = ref.watch(connectivityStatusProvider);
  return asyncStatus.when(
    data: (status) => status,
    loading: () => ConnectivityStatus.connected, // Default to connected while loading
    error: (_, __) => ConnectivityStatus.disconnected,
  );
});

