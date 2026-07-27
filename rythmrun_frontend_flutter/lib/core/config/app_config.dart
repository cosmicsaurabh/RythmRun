import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Centralized application configuration
/// Supports different environments (dev, staging, prod)
class AppConfig {
  static const String _googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    // Public web OAuth client ID (audience) — safe to embed; it ships in every
    // build regardless. A --dart-define of the same name still overrides this
    // (e.g. for a different audience in staging).
    defaultValue:
        '825804253502-2g743kq71sr2cep4tqo5ciabs9h26qkn.apps.googleusercontent.com',
  );

  // Environment-specific configurations
  static const Map<String, String> _baseUrls = {
    'dev': 'http://192.168.1.47:8080/api', // local (UPDATE THIS IP ADDRESS)
    'staging': 'https://rythmrun-staging.onrender.com/api', // staging
    'prod': 'https://rythmrun.onrender.com/api', //Render API
  };

  static const Map<String, int> _timeouts = {
    'dev': 30000, // 30 seconds for dev
    'staging': 15000, // 15 seconds for staging
    'prod': 10000, // 10 seconds for prod
  };

  // Environment detection
  static String get _environment {
    // You can override this with a const or environment variable
    if (kDebugMode) {
      return 'dev';
    } else if (kReleaseMode) {
      return 'prod';
    } else {
      return 'staging';
    }
  }

  /// Get the base URL for the current environment
  static String get baseUrl {
    final env = _environment;
    final url = _baseUrls[env];
    if (url == null || url.isEmpty) {
      throw Exception('No base URL configured for environment: $env');
    }
    return url;
  }

  /// Get the timeout duration for HTTP requests
  static Duration get timeout {
    final env = _environment;
    final timeoutMs = _timeouts[env] ?? 30000; // Default to 30 seconds
    return Duration(milliseconds: timeoutMs);
  }

  /// Get the current environment name
  static String get environment => _environment;

  /// Check if running in debug mode
  static bool get isDebug => kDebugMode;

  /// Check if running in release mode
  static bool get isRelease => kReleaseMode;

  /// Check if running in profile mode
  static bool get isProfile => !kDebugMode && !kReleaseMode;

  /// OAuth client used by platforms that require an application client ID
  /// (notably iOS). Android can leave this empty when only a web/server client
  /// ID is required.
  static String? get googleClientId => _nonEmpty(_googleClientId);

  /// Web OAuth client ID whose audience is verified by the RythmRun backend.
  static String? get googleServerClientId => _nonEmpty(_googleServerClientId);

  static bool get googleAuthUsesSecureTransport =>
      Uri.tryParse(baseUrl)?.scheme.toLowerCase() == 'https';

  static bool get isGoogleSignInAvailable => isGoogleSignInConfigurationUsable(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
    baseUrl: baseUrl,
    serverClientId: googleServerClientId,
    clientId: googleClientId,
  );

  /// Pure availability policy shared by the login UI and configuration tests.
  /// Runtime checks in the native adapter remain authoritative.
  static bool isGoogleSignInConfigurationUsable({
    required TargetPlatform platform,
    required bool isWeb,
    required String baseUrl,
    required String? serverClientId,
    required String? clientId,
  }) {
    if (isWeb || Uri.tryParse(baseUrl)?.scheme.toLowerCase() != 'https') {
      return false;
    }
    if (_nonEmpty(serverClientId ?? '') == null) return false;

    return switch (platform) {
      TargetPlatform.android => true,
      TargetPlatform.iOS => _nonEmpty(clientId ?? '') != null,
      _ => false,
    };
  }

  /// Get full URL for an endpoint
  static String getUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }

  static String? _nonEmpty(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  /// Print current configuration (useful for debugging)
  static void printConfig() {
    if (isDebug) {
      log('=== App Configuration ===');
      log('Environment: $environment');
      log('Base URL: $baseUrl');
      log('Timeout: ${timeout.inSeconds} seconds');
      log('Debug Mode: $isDebug');
      log('Release Mode: $isRelease');
      log('Profile Mode: $isProfile');
      log('========================');
    }
  }
}
