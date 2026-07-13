import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Centralized application configuration
/// Supports different environments (dev, staging, prod)
class AppConfig {
  // Environment-specific configurations
  static const Map<String, String> _baseUrls = {
    'dev': 'http://192.168.1.47:8080/api', // local (UPDATE THIS IP ADDRESS)
    'staging': 'https://rythmrun-staging.onrender.com/api', // staging
    'prod': 'https://rythmrun.onrender.com/api', //Render API
  };

  static const Map<String, String> _r2Domains = {
    'dev':
        'https://dev-account-id.r2.cloudflarestorage.com', // R2 dev (update with your dev R2 account)
    'staging':
        'https://staging-account-id.r2.cloudflarestorage.com', // R2 staging
    'prod': 'https://your-account-id.r2.cloudflarestorage.com', // R2 prod
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

  /// Get the R2 domain for the current environment
  static String get r2Domain {
    final env = _environment;
    final domain = _r2Domains[env];
    if (domain == null || domain.isEmpty) {
      throw Exception('No R2 domain configured for environment: $env');
    }
    return domain;
  }

  /// Legacy: CloudFront domain (now points to R2)
  static String get cloudfrontDomain => r2Domain;

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

  /// Get full URL for an endpoint
  static String getUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }

  /// Print current configuration (useful for debugging)
  static void printConfig() {
    if (isDebug) {
      log('=== App Configuration ===');
      log('Environment: $environment');
      log('Base URL: $baseUrl');
      log('R2 Domain: $r2Domain');
      log('Timeout: ${timeout.inSeconds} seconds');
      log('Debug Mode: $isDebug');
      log('Release Mode: $isRelease');
      log('Profile Mode: $isProfile');
      log('========================');
    }
  }
}
