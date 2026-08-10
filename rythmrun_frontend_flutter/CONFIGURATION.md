# Configuration Guide

## Environment Setup

This app supports multiple environments (development, staging, production) with different configurations.

### How to Determine Current Environment

#### Method 1: Console Output
When you start the app, it prints the configuration:
```
=== App Configuration ===
Environment: dev
Base URL: http://192.168.1.47:8080/api
Timeout: 30 seconds
Debug Mode: true
Release Mode: false
Profile Mode: false
========================
```

#### Method 2: Build Mode Detection
Used only when `APP_ENV` is not supplied:
- **Debug Mode** (`flutter run`): `dev` environment
- **Profile Mode** (`flutter run --profile`): `staging` environment  
- **Release Mode** (`flutter run --release`): `prod` environment

#### Method 3: Explicit `APP_ENV` override
`--dart-define=APP_ENV=<dev|staging|prod>` selects the environment directly and
takes precedence over build-mode detection. It exists so a release-mode build
can be pointed at the staging backend for the staging manual checks without
shipping a debug binary.

| Define | Accepted values | Default | Effect |
| --- | --- | --- | --- |
| `APP_ENV` | `dev`, `staging`, `prod` | unset (build mode decides) | Selects the API base URL and HTTP timeout only |

Scope limits worth knowing:
- It selects **base URL and timeout only**. `AppConfig.isDebug`/`isRelease`/
  `isProfile` still derive from `kDebugMode`/`kReleaseMode`, so this define
  cannot turn a release build into a debug build.
- It does **not** affect advertising. `ADS_ENV` is a separate contract (below)
  and does not accept `dev`/`prod`.
- An unrecognized value has no base URL mapped, so the first request throws
  rather than falling back to production.

### Current Configuration

#### Development (dev)
- **Base URL**: `http://192.168.1.47:8080/api`
- **Timeout**: 30 seconds
- **Retries**: GET may retry network failures twice; mutations default to no transport retry
- **Build Command**: `flutter run`

#### Staging (staging)
- **Base URL**: `https://rythmrun-staging.onrender.com/api`
- **Timeout**: 15 seconds
- **Retries**: GET may retry network failures twice; mutations default to no transport retry
- **Build Command**: `flutter run --profile`

#### Production (prod)
- **Base URL**: `https://rythmrun.onrender.com/api`
- **Timeout**: 10 seconds
- **Retries**: GET may retry network failures twice; mutations default to no transport retry
- **Build Command**: `flutter run --release`

## Advertising Configuration (IP-1.7)

Advertising has a separate compile-time environment contract. `ADS_ENV` does not select the API base URL described above. Values are supplied with Flutter `--dart-define` flags and are read by both Dart and Android Gradle; changing them after an APK is built has no effect.

Ads are disabled by default. Development, test, profile, staging, iOS, and an ads-disabled production release use the no-op provider. Safe Android packages receive the official Google sample application ID so the manifest remains valid, delay native Mobile Ads measurement startup, remove ad-identifier/Privacy Sandbox ad permissions from the merged manifest, and never call Mobile Ads initialization from Dart.

### Exact variables

| Variable | Allowed value | Default | Contract |
| --- | --- | --- | --- |
| `ADS_ENV` | `development`, `staging`, or `production` | `development` | Advertising environment only. Use the full names; `dev` and `prod` are not accepted. |
| `ADS_ENABLED` | `true` or `false` | `false` | `true` is effective only for an Android release with `ADS_ENV=production`. Use lowercase values. |
| `ADMOB_ANDROID_APP_ID` | `ca-app-pub-<16-digit-publisher-id>~<10-digit-app-id>` | empty | Required only when production ads are intentionally enabled. It must be non-sample. |
| `ADMOB_POST_ACTIVITY_UNIT_ID` | `ca-app-pub-<same-16-digit-publisher-id>/<10-digit-unit-id>` | empty | Required only when production ads are intentionally enabled. It must be non-sample and use the application ID's publisher. |

The production application and unit IDs must be explicit, well formed, from the same publisher, and outside Google's sample publisher. Any Android build configured with `ADS_ENV=production` and `ADS_ENABLED=true` validates those values independently of the requested Gradle task, so aggregate/custom tasks cannot bypass the check. Missing, malformed, sample, or publisher-mismatched values fail configuration before packaging. Valid production values are injected only into the release manifest; debug/profile manifests keep the sample application ID and Dart remains no-op. There is no source-code fallback.

Only the post-activity placement can be configured by this contract. Start-of-day rewarded ads and activity banners remain disabled. iOS remains ads-disabled. Consent/privacy choices, live production serving, placement approval, and any additional placement remain blocked on IP-5.5.

### Resolution matrix

| Build/configuration | Dart provider | Android manifest application ID | Result |
| --- | --- | --- | --- |
| No ad defines | No-op | Official Google sample ID | Safe default |
| Development or staging, `ADS_ENABLED=false` | No-op | Official Google sample ID | Supported non-production configuration |
| Development or staging, `ADS_ENABLED=true` | No-op | Official Google sample ID | Fails closed; do not pass production IDs to these builds |
| Debug/profile with production ads requested, missing/invalid IDs | None | No package | Configuration fails independently of the Gradle task name |
| Debug/profile with production ads requested, valid explicit IDs | No-op | Official Google sample ID | Values cannot enable ads or be used by a provider; supplied compile-time defines may still be embedded in the Dart artifact, so this is prohibited for normal builds |
| Production release, `ADS_ENABLED=false` | No-op | Official Google sample ID | Supported ads-disabled release |
| Android production release, `ADS_ENABLED=true`, valid explicit IDs | AdMob, post-activity only | Explicit application ID | Configuration is packageable, but live use still requires IP-5.5 |
| Android production release, `ADS_ENABLED=true`, missing/invalid IDs | None | No package | Configuration fails before packaging |
| iOS | No-op | Not applicable | Ads remain out of scope until IP-5.5 |

Never pass production IDs to development, test, staging, or routine verification commands. Never commit them to this file, a script, a Dart source file, an Android manifest, a screenshot, or test output. The release owner must inject approved values through the protected release system only after IP-5.5 is complete.

### Safe commands

Development and tests default safely, but pass the intent explicitly in reproducible QA commands:

```bash
flutter run \
  --dart-define=ADS_ENV=development \
  --dart-define=ADS_ENABLED=false

flutter test \
  --dart-define=ADS_ENV=development \
  --dart-define=ADS_ENABLED=false
```

Staging/profile with ads disabled:

```bash
flutter run --profile \
  --dart-define=ADS_ENV=staging \
  --dart-define=ADS_ENABLED=false
```

Production release with ads disabled:

```bash
flutter build apk --release \
  --dart-define=ADS_ENV=production \
  --dart-define=ADS_ENABLED=false
```

Fail-closed release check. This command must fail before producing an APK because production ads were requested without IDs:

```bash
flutter build apk --release \
  --dart-define=ADS_ENV=production \
  --dart-define=ADS_ENABLED=true
```

Production-ID shape template for the protected release system only; the strings below are placeholders, are intentionally not valid IDs, and must not be pasted into a real build:

```bash
flutter build apk --release \
  --dart-define=ADS_ENV=production \
  --dart-define=ADS_ENABLED=true \
  --dart-define='ADMOB_ANDROID_APP_ID=ca-app-pub-<16-digit-publisher-id>~<10-digit-app-id>' \
  --dart-define='ADMOB_POST_ACTIVITY_UNIT_ID=ca-app-pub-<same-16-digit-publisher-id>/<10-digit-unit-id>'
```

### Workout-completion boundary

The post-activity placement is optional and is downstream of local durability. Finish must first return a newly saved local workout ID. Save-pending, failed, no-active-workout, or tracking-cleanup-pending outcomes show recovery UI and cannot request an ad. A single newly committed ID can reach the completion gate at most once. A save completed later through Retry deliberately does not request an ad. Eligibility is rechecked after asynchronous initialization and again immediately before provider display. Initialization/show waits are bounded, and timeout, SDK/load, or cooldown-storage failures cannot hang completion, show late, hide, roll back, or turn a saved workout into a failed completion.

Repository tests cover this state/configuration contract. Follow MC-1.14 in `docs/_engineering/improvement-plan/MANUAL-CHECKS.md` for merged-manifest and supported-device proof. That check does not authorize live ads; IP-5.5 remains the release gate.

### How to Change Configuration

#### 1. Update Environment URLs
Edit `lib/core/config/app_config.dart`:
```dart
static const Map<String, String> _baseUrls = {
  'dev': 'http://192.168.1.47:8080/api', // Replace for your LAN/tunnel
  'staging': 'https://rythmrun-staging.onrender.com/api',
  'prod': 'https://rythmrun.onrender.com/api',
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

#### 3. Build directly with Flutter
```bash
# Development
flutter run

# Production
flutter run --release
```

### Network Features

- **Method-aware retry**: GET retries network failures up to twice with bounded backoff; POST/PUT/DELETE/multipart requests default to zero transport retries unless an owning coordinator proves replay safety
- **Timeout Handling**: Requests timeout after environment-specific duration
- **Error Classification**: Different exception types for different error scenarios
- **Connection Pooling**: Efficient HTTP client reuse

## Google sign-in configuration

Google sign-in exchanges a Google ID token at
`POST /api/users/auth/google`; the backend returns the same RythmRun
access/refresh-token response used by password login. The Google web OAuth
client ID configured in the app must match the audience configured on the
backend.

Google authentication is disabled unless `GOOGLE_SERVER_CLIENT_ID` is supplied
at build time, and it fails closed when the selected API base URL is not HTTPS.
The current local development URL in `AppConfig` is plain HTTP, so use an HTTPS
development endpoint or tunnel before testing Google sign-in. Never send a
Google ID token to a cleartext endpoint. The login screen hides the Google
action when these requirements are not met; on iOS it also requires a non-empty
`GOOGLE_CLIENT_ID`.

> **Release caveat:** App Store rules may require an equivalent Sign in with
> Apple option when a third-party identity provider is offered. Sign in with
> Apple is outside the scope of this Google-authentication change; evaluate and
> implement it, if required, before submitting the iOS app for review.

> **Production branding TODO:** The current plain `G` in the login button is a
> temporary placeholder. Replace it with Google-approved branding assets and
> button treatment before production release.

### Android

1. Register an Android OAuth client for package
   `com.github.cosmicsaurabh.rythmrun` and every signing certificate SHA used by
   the build (debug, internal, and release as applicable).
2. Create a web OAuth client for the backend token audience.
3. Build with the web client ID:

```bash
flutter run \
  --dart-define='GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com'
```

No client secret or `google-services.json` is required by this direct
`google_sign_in` setup.

### iOS

1. Register an iOS OAuth client for bundle ID
   `com.github.cosmicsaurabh.rythmrun`.
2. Copy `ios/Flutter/GoogleAuth.xcconfig.example` to
   `ios/Flutter/GoogleAuth.xcconfig` and replace the iOS client ID and reversed
   client ID placeholders. The local file is git-ignored and feeds the URL
   scheme declared in `Info.plist`.
3. Supply the same iOS application client ID to Dart and the web/backend client
   ID as the server audience:

```bash
flutter run \
  --dart-define='GOOGLE_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com' \
  --dart-define='GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com'
```

OAuth client IDs are identifiers and will be present in the built app. Never
put an OAuth client secret in Flutter source, Dart defines, xcconfig files, or
mobile release configuration.

### Adding New Endpoints

1. Add the endpoint to `lib/core/config/api_endpoints.dart`
2. Use `AppConfig.getUrl(ApiEndpoints.yourEndpoint)` in your datasource
3. The endpoint will automatically use the correct base URL for the environment

### Troubleshooting

#### Connection Timeout Issues
1. Check if the backend server is running
2. Verify the IP address in the configuration
3. Check network connectivity
4. Call `AppConfig.printConfig()` from an approved debug-only entry point if you need to verify the resolved environment; the app does not currently expose a debug menu

#### Environment Not Detected Correctly
1. Check the build mode you're using
2. Verify the configuration in `AppConfig._environment`
3. Use `AppConfig.printConfig()` to debug
