# Configuration Guide

## Environment Setup

This app supports multiple environments (development, staging, production) with different configurations.

### How to Determine Current Environment

#### Method 1: Console Output
When you start the app, it prints the configuration:
```
=== App Configuration ===
Environment: dev
Base URL: http://192.168.1.51:8080/api
Timeout: 30 seconds
Debug Mode: true
Release Mode: false
Profile Mode: false
========================
```

#### Method 2: Debug Menu
- Tap the bug icon (🐛) in the top-right corner of the app
- The environment info is displayed at the top

#### Method 3: Build Mode Detection
- **Debug Mode** (`flutter run`): `dev` environment
- **Profile Mode** (`flutter run --profile`): `staging` environment  
- **Release Mode** (`flutter run --release`): `prod` environment

### Current Configuration

#### Development (dev)
- **Base URL**: `http://192.168.1.51:8080/api`
- **Timeout**: 30 seconds
- **Retries**: 2 attempts
- **Build Command**: `flutter run` or `./scripts/build_dev.sh`

#### Staging (staging)
- **Base URL**: `http://192.168.1.51:8080/api` (same as dev for now)
- **Timeout**: 15 seconds
- **Retries**: 2 attempts
- **Build Command**: `flutter run --profile`

#### Production (prod)
- **Base URL**: `http://192.168.1.51:8080/api` (same as dev for now)
- **Timeout**: 10 seconds
- **Retries**: 2 attempts
- **Build Command**: `flutter run --release` or `./scripts/build_prod.sh`

### How to Change Configuration

#### 1. Update Environment URLs
Edit `lib/core/config/app_config.dart`:
```dart
static const Map<String, String> _baseUrls = {
  'dev': 'http://192.168.1.51:8080/api',
  'staging': '', // Change this
  'prod': '', // Change this
};
```

#### 2. Update Timeouts
```dart
static const Map<String, int> _timeouts = {
  'dev': 30000,
  'staging': 15000,
  'prod': 10000,
};
```

#### 3. Use Build Scripts
```bash
# Development
./scripts/build_dev.sh

# Production
./scripts/build_prod.sh
```

### Network Features

- **Automatic Retry**: Failed requests are retried with exponential backoff
- **Timeout Handling**: Requests timeout after environment-specific duration
- **Error Classification**: Different exception types for different error scenarios
- **Connection Pooling**: Efficient HTTP client reuse

### Adding New Endpoints

1. Add the endpoint to `lib/core/config/api_endpoints.dart`
2. Use `AppConfig.getUrl(ApiEndpoints.yourEndpoint)` in your datasource
3. The endpoint will automatically use the correct base URL for the environment

### Troubleshooting

#### Connection Timeout Issues
1. Check if the backend server is running
2. Verify the IP address in the configuration
3. Check network connectivity
4. Use the debug menu to verify the current environment

#### Environment Not Detected Correctly
1. Check the build mode you're using
2. Verify the configuration in `AppConfig._environment`
3. Use `AppConfig.printConfig()` to debug

