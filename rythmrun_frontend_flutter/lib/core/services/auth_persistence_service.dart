import 'dart:async';
import 'dart:convert';

import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/auth_response_model.dart';
import '../../domain/entities/user_entity.dart';
import 'auth_token_store.dart';

/// Narrow preference seam. Authentication credentials must never be written
/// through this interface; it exists only for non-secret account metadata.
abstract interface class AuthPreferences {
  String? getString(String key);

  bool? getBool(String key);

  bool containsKey(String key);

  Future<bool> setString(String key, String value);

  Future<bool> setBool(String key, bool value);

  Future<bool> remove(String key);
}

final class SharedPreferencesAuthPreferences implements AuthPreferences {
  SharedPreferencesAuthPreferences(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  bool? getBool(String key) => _preferences.getBool(key);

  @override
  bool containsKey(String key) => _preferences.containsKey(key);

  @override
  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    return _preferences.setBool(key, value);
  }

  @override
  Future<bool> remove(String key) => _preferences.remove(key);
}

typedef AuthPreferencesFactory = Future<AuthPreferences> Function();

/// Persists account metadata and delegates credentials to [AuthTokenStore].
///
/// The service is injectable so migration and interrupted-write behavior can
/// be tested without a device keychain. The default constructor is suitable
/// for application dependency injection.
class AuthPersistenceService {
  AuthPersistenceService({
    AuthTokenStore? tokenStore,
    AuthPreferencesFactory? preferencesFactory,
    DateTime Function()? now,
  }) : _tokenStore =
           // The token store and this service must share one clock so the
           // verified/observed timestamps it stamps and the offline-window
           // policy evaluated here agree. When an external store is injected,
           // the caller owns that consistency (production and tests inject the
           // same clock into both).
           tokenStore ?? SecureAuthTokenStore(now: now ?? DateTime.now),
       _preferencesFactory =
           preferencesFactory ??
           (() async => SharedPreferencesAuthPreferences(
             await SharedPreferences.getInstance(),
           )),
       _now = now ?? DateTime.now;

  static const String userDataKey = 'user_data';
  static const String lastBackendSyncKey = 'last_backend_sync';
  static const String authCleanupPendingKey = 'auth_cleanup_pending';

  // Auth timing knobs. Baked in at compile time (int.fromEnvironment), so an
  // override needs a rebuild + reinstall — unlike the backend token/session
  // TTLs, which the app follows live because it reads expiry from the JWT.
  // Defaults reproduce today's behavior exactly.

  /// Maximum offline access after a successful server verification (D-009).
  /// Override with `--dart-define=OFFLINE_WINDOW_HOURS=<n>` to force the
  /// re-verification path in a test build.
  static const int _offlineWindowHours = int.fromEnvironment(
    'OFFLINE_WINDOW_HOURS',
    defaultValue: 168,
  );
  static const Duration offlineWindow = Duration(hours: _offlineWindowHours);

  /// Small tolerance so benign NTP corrections do not force re-verification,
  /// while a meaningful clock rollback or future-dated verification still
  /// fails offline admission closed. Negligible against [offlineWindow].
  /// Override with `--dart-define=CLOCK_SKEW_TOLERANCE_SECONDS=<n>`.
  static const int _clockSkewToleranceSeconds = int.fromEnvironment(
    'CLOCK_SKEW_TOLERANCE_SECONDS',
    defaultValue: 120,
  );
  static const Duration clockSkewTolerance = Duration(
    seconds: _clockSkewToleranceSeconds,
  );

  /// Default cadence for the periodic backend reconciliation in
  /// [needsBackendSync]. Override with
  /// `--dart-define=BACKEND_SYNC_INTERVAL_HOURS=<n>`.
  static const int _backendSyncIntervalHours = int.fromEnvironment(
    'BACKEND_SYNC_INTERVAL_HOURS',
    defaultValue: 168,
  );

  final AuthTokenStore _tokenStore;
  final AuthPreferencesFactory _preferencesFactory;
  final DateTime Function() _now;

  Future<AuthCredentialSnapshot?> readCredentialSnapshot() {
    return _tokenStore.read();
  }

  Future<AuthCredentialSnapshot> replaceCredentials(AuthTokenPair replacement) {
    return _tokenStore.write(replacement);
  }

  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
  }) {
    return _tokenStore.compareAndSet(
      expectedRevision: expectedRevision,
      replacement: replacement,
    );
  }

  Future<void> saveAuthData(AuthResponseModel authResponse) async {
    await replaceCredentials(
      AuthTokenPair(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
      ),
    );

    final preferences = await _preferencesFactory();
    await _writeString(
      preferences,
      userDataKey,
      jsonEncode(authResponse.user.toJson()),
    );
    await _writeString(
      preferences,
      lastBackendSyncKey,
      _now().toIso8601String(),
    );
  }

  Future<UserEntity?> getUserData() async {
    final preferences = await _preferencesFactory();
    final encoded = preferences.getString(userDataKey);
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return UserEntity(
        id: decoded['id'] as String,
        firstName: decoded['firstName'] as String,
        lastName: decoded['lastName'] as String,
        email: decoded['email'] as String,
        hasPassword: decoded['hasPassword'] as bool? ?? true,
        // Same default as UserModel.fromJson: a blob cached before this field
        // existed must not flash an "unverified" banner.
        emailVerified: decoded['emailVerified'] as bool? ?? true,
        profilePicturePath: decoded['profilePicturePath'] as String?,
        profilePictureType: decoded['profilePictureType'] as String?,
        createdAt:
            decoded['createdAt'] is String
                ? DateTime.parse(decoded['createdAt'] as String)
                : null,
      );
    } catch (_) {
      await _removePreference(preferences, userDataKey);
      return null;
    }
  }

  Future<bool> hasValidSession() async {
    final snapshot = await readCredentialSnapshot();
    if (snapshot == null) return false;
    try {
      return !JwtDecoder.isExpired(snapshot.pair.accessToken);
    } catch (_) {
      return false;
    }
  }

  Future<bool> needsTokenRefresh() async {
    final snapshot = await readCredentialSnapshot();
    if (snapshot == null) return false;
    try {
      return JwtDecoder.isExpired(snapshot.pair.accessToken) &&
          !JwtDecoder.isExpired(snapshot.pair.refreshToken);
    } catch (_) {
      return false;
    }
  }

  Future<void> markAuthCleanupPending() async {
    final preferences = await _preferencesFactory();
    final didWrite = await preferences.setBool(authCleanupPendingKey, true);
    if (!didWrite || preferences.getBool(authCleanupPendingKey) != true) {
      throw StateError('Failed to persist pending authentication cleanup.');
    }
  }

  Future<bool> hasPendingAuthCleanup() async {
    final preferences = await _preferencesFactory();
    return preferences.getBool(authCleanupPendingKey) ?? false;
  }

  Future<void> clearCredentials() async {
    // The secure store serializes its own delete/read, so no extra FIFO is
    // needed here now that legacy migration is gone.
    await _tokenStore.delete();
    if (await _tokenStore.read() != null) {
      throw StateError('Secure authentication credentials remain.');
    }
  }

  Future<bool> clearCredentialsIfRevision(int expectedRevision) {
    return _tokenStore.deleteIfRevision(expectedRevision);
  }

  Future<void> clearAuthData() async {
    // The caller sets the cleanup marker before entering this operation. It is
    // intentionally removed only after every account value is confirmed gone.
    await clearCredentials();
    final preferences = await _preferencesFactory();
    await _removePreference(preferences, userDataKey);
    await _removePreference(preferences, lastBackendSyncKey);

    if (preferences.containsKey(userDataKey) ||
        preferences.containsKey(lastBackendSyncKey) ||
        await _tokenStore.read() != null) {
      throw StateError('Locally persisted authentication data remains.');
    }

    if (preferences.getBool(authCleanupPendingKey) == true) {
      await _removePreference(preferences, authCleanupPendingKey);
    }
  }

  Future<void> updateUserData(UserEntity user) async {
    final preferences = await _preferencesFactory();
    await _writeString(
      preferences,
      userDataKey,
      jsonEncode(<String, Object?>{
        'id': user.id,
        'firstName': user.firstName,
        'lastName': user.lastName,
        'email': user.email,
        'hasPassword': user.hasPassword,
        'emailVerified': user.emailVerified,
        'profilePicturePath': user.profilePicturePath,
        'profilePictureType': user.profilePictureType,
        'createdAt': user.createdAt?.toIso8601String(),
      }),
    );
  }

  Future<void> clearUserData() async {
    final preferences = await _preferencesFactory();
    await _removePreference(preferences, userDataKey);
  }

  Future<DateTime?> getLastBackendSync() async {
    final preferences = await _preferencesFactory();
    final encoded = preferences.getString(lastBackendSyncKey);
    if (encoded == null) return null;
    return DateTime.tryParse(encoded);
  }

  Future<bool> needsBackendSync({
    Duration syncInterval = const Duration(hours: _backendSyncIntervalHours),
  }) async {
    final lastSync = await getLastBackendSync();
    if (lastSync == null) return true;
    return _now().difference(lastSync) > syncInterval;
  }

  Future<void> updateLastBackendSync() async {
    final preferences = await _preferencesFactory();
    await _writeString(
      preferences,
      lastBackendSyncKey,
      _now().toIso8601String(),
    );
  }

  /// Whether the cached identity may enter bounded offline mode.
  ///
  /// Offline admission requires a present, server-verified credential pair with
  /// a non-expired refresh token, a stored user, and a verification that is
  /// within the [offlineWindow] measured against an integrity-sensitive,
  /// tamper-checked wall clock. A rolled-back or future-dated clock fails
  /// closed and requires fresh online verification (IP-2.3 / D-009).
  ///
  /// As a deliberate side effect, this advances the secure observed-clock
  /// high-water mark *after* the eligibility decision has read the previous
  /// value, so a subsequent clock rollback below it is detectable.
  Future<bool> canStayLoggedInOffline() async {
    final snapshot = await readCredentialSnapshot();
    if (snapshot == null) return false;
    if (await getUserData() == null) return false;
    try {
      if (JwtDecoder.isExpired(snapshot.pair.refreshToken)) return false;
    } catch (_) {
      return false;
    }

    final eligible = _isWithinVerifiedOfflineWindow(snapshot);
    // Recording the observed high-water mark is best effort. A transient secure
    // write failure (e.g. keychain busy) must never discard an already-earned
    // eligibility decision or escape into session startup. A skipped advance
    // only fails to raise the mark; it can never lower it, so it cannot weaken
    // rollback detection.
    try {
      await _tokenStore.advanceObservedClock();
    } catch (_) {}
    return eligible;
  }

  bool _isWithinVerifiedOfflineWindow(AuthCredentialSnapshot snapshot) {
    final verifiedAtMs = snapshot.lastVerifiedAtMs;
    // A pair with no integrity-sensitive verification anchor (a pre-IP-2.3
    // envelope) cannot enter offline mode until one online verification stamps
    // it. Completed local data is not deleted.
    if (verifiedAtMs == null) return false;

    final nowMs = _now().millisecondsSinceEpoch;
    final toleranceMs = clockSkewTolerance.inMilliseconds;

    // Clock rollback: a current time below the highest wall clock this device
    // has ever observed cannot be trusted to bound the offline window.
    final observedMaxMs = snapshot.maxObservedAtMs;
    if (observedMaxMs != null && nowMs < observedMaxMs - toleranceMs) {
      return false;
    }

    // A verification timestamp in the future is impossible for a legitimate
    // clock and must not grant an unbounded window.
    if (verifiedAtMs > nowMs + toleranceMs) return false;

    // Bounded seven-day window from the last integrity-checked verification.
    return nowMs - verifiedAtMs <= offlineWindow.inMilliseconds;
  }

  Future<void> _writeString(
    AuthPreferences preferences,
    String key,
    String value,
  ) async {
    final didWrite = await preferences.setString(key, value);
    if (!didWrite || preferences.getString(key) != value) {
      throw StateError('Failed to persist local authentication metadata.');
    }
  }

  Future<void> _removePreference(
    AuthPreferences preferences,
    String key,
  ) async {
    if (!preferences.containsKey(key)) return;
    final didRemove = await preferences.remove(key);
    if (!didRemove || preferences.containsKey(key)) {
      throw StateError('Failed to clear local authentication metadata.');
    }
  }
}
