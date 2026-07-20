import 'dart:async';
import 'dart:convert';

import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/auth_response_model.dart';
import '../../domain/entities/user_entity.dart';
import 'auth_token_store.dart';

/// Narrow preference seam. Authentication credentials must never be written
/// through this interface; it exists only for non-secret account metadata and
/// safe migration from the two historical preference keys.
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

  static const String legacyAccessTokenKey = 'access_token';
  static const String legacyRefreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';
  static const String lastBackendSyncKey = 'last_backend_sync';
  static const String authCleanupPendingKey = 'auth_cleanup_pending';

  /// Maximum offline access after a successful server verification (D-009).
  static const Duration offlineWindow = Duration(days: 7);

  /// Small tolerance so benign NTP corrections do not force re-verification,
  /// while a meaningful clock rollback or future-dated verification still
  /// fails offline admission closed. Negligible against [offlineWindow].
  static const Duration clockSkewTolerance = Duration(minutes: 2);

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final AuthTokenStore _tokenStore;
  final AuthPreferencesFactory _preferencesFactory;
  final DateTime Function() _now;

  Future<AuthCredentialSnapshot?>? _migrationInFlight;
  Future<void> _credentialLifecycleTail = Future<void>.value();
  bool _migrationSettled = false;

  Future<AuthCredentialSnapshot?> readCredentialSnapshot() async {
    if (!_migrationSettled) return _ensureLegacyMigration();
    return _tokenStore.read();
  }

  Future<AuthCredentialSnapshot> replaceCredentials(
    AuthTokenPair replacement, {
    bool requiresServerVerification = false,
  }) async {
    await _ensureLegacyMigration();
    return _tokenStore.write(
      replacement,
      requiresServerVerification: requiresServerVerification,
    );
  }

  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  }) async {
    await _ensureLegacyMigration();
    return _tokenStore.compareAndSet(
      expectedRevision: expectedRevision,
      replacement: replacement,
      requiresServerVerification: requiresServerVerification,
    );
  }

  Future<AuthCredentialSnapshot?> markCredentialsServerVerified({
    required int expectedRevision,
  }) async {
    await _ensureLegacyMigration();
    return _tokenStore.markServerVerified(expectedRevision: expectedRevision);
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
    // Prevent a new legacy migration from starting. The shared FIFO guarantees
    // that an already-started migration finishes before this final delete, or
    // that a clear which started first removes legacy values before any later
    // read can consider migrating them.
    _migrationSettled = true;
    await _serializeCredentialLifecycle(_clearCredentialsUnsafe);
  }

  Future<void> _clearCredentialsUnsafe() async {
    await _tokenStore.delete();
    final preferences = await _preferencesFactory();
    await _removeLegacyCredentials(preferences);
    if (await _tokenStore.read() != null) {
      throw StateError('Secure authentication credentials remain.');
    }
  }

  Future<bool> clearCredentialsIfRevision(int expectedRevision) async {
    await _ensureLegacyMigration();
    final deleted = await _tokenStore.deleteIfRevision(expectedRevision);
    if (!deleted) return false;

    final preferences = await _preferencesFactory();
    await _removeLegacyCredentials(preferences);
    _migrationSettled = true;
    return true;
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
        preferences.containsKey(legacyAccessTokenKey) ||
        preferences.containsKey(legacyRefreshTokenKey) ||
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
    Duration syncInterval = const Duration(days: 7),
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
    if (snapshot == null || snapshot.requiresServerVerification) return false;
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
    // envelope or a never-verified migration) cannot enter offline mode until
    // one online verification stamps it. Completed local data is not deleted.
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

  Future<AuthCredentialSnapshot?> _ensureLegacyMigration() {
    final existing = _migrationInFlight;
    if (existing != null) return existing;
    if (_migrationSettled) return _tokenStore.read();

    late final Future<AuthCredentialSnapshot?> operation;
    operation = _serializeCredentialLifecycle(
      _migrateLegacyCredentials,
    ).whenComplete(() {
      if (identical(_migrationInFlight, operation)) {
        _migrationInFlight = null;
      }
    });
    _migrationInFlight = operation;
    return operation;
  }

  Future<T> _serializeCredentialLifecycle<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _credentialLifecycleTail = _credentialLifecycleTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<AuthCredentialSnapshot?> _migrateLegacyCredentials() async {
    final preferences = await _preferencesFactory();
    final secureSnapshot = await _tokenStore.read();

    if (secureSnapshot != null) {
      // A verified secure write always wins. This is also the retry path for a
      // process interrupted after secure write but before preference cleanup.
      await _removeLegacyCredentials(preferences);
      _migrationSettled = true;
      return secureSnapshot;
    }

    final accessToken = preferences.getString(legacyAccessTokenKey);
    final refreshToken = preferences.getString(legacyRefreshTokenKey);
    if (accessToken == null && refreshToken == null) {
      _migrationSettled = true;
      return null;
    }

    final userId = _storedUserId(preferences.getString(userDataKey));
    if (accessToken == null ||
        refreshToken == null ||
        !_isCoherentIp21Pair(accessToken, refreshToken, userId: userId)) {
      // An incomplete, malformed, expired, or pre-IP-2.1 pair cannot be used.
      // Remove it from plaintext preferences and fail closed.
      await _removeLegacyCredentials(preferences);
      _migrationSettled = true;
      return null;
    }

    final migrated = await _tokenStore.write(
      AuthTokenPair(accessToken: accessToken, refreshToken: refreshToken),
      requiresServerVerification: true,
    );
    final readBack = await _tokenStore.read();
    if (readBack == null ||
        readBack.revision != migrated.revision ||
        readBack.pair != migrated.pair ||
        !readBack.requiresServerVerification) {
      throw StateError('Secure credential migration could not be verified.');
    }

    // Plaintext is removed only after the complete secure envelope is read
    // back. Any failure here leaves the remaining key for a safe retry.
    await _removeLegacyCredentials(preferences);
    _migrationSettled = true;
    return readBack;
  }

  String? _storedUserId(String? encodedUser) {
    if (encodedUser == null) return null;
    try {
      final decoded = jsonDecode(encodedUser);
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['id'];
      return id is String ? id : null;
    } catch (_) {
      return null;
    }
  }

  bool _isCoherentIp21Pair(
    String accessToken,
    String refreshToken, {
    String? userId,
  }) {
    final access = _decodeJwt(accessToken);
    final refresh = _decodeJwt(refreshToken);
    if (access == null || refresh == null) return false;

    final accessSubject = access['sub'];
    final refreshSubject = refresh['sub'];
    final accessSession = access['sid'];
    final refreshSession = refresh['sid'];
    final accessJti = access['jti'];
    final refreshJti = refresh['jti'];
    final accessIssuedAt = access['iat'];
    final refreshIssuedAt = refresh['iat'];
    final accessExpiresAt = access['exp'];
    final refreshExpiresAt = refresh['exp'];

    if (accessSubject is! String ||
        int.tryParse(accessSubject)?.toString() != accessSubject ||
        int.parse(accessSubject) <= 0 ||
        refreshSubject != accessSubject ||
        (userId != null && userId != accessSubject) ||
        access['typ'] != 'access' ||
        refresh['typ'] != 'refresh' ||
        accessSession is! String ||
        !_uuidPattern.hasMatch(accessSession) ||
        refreshSession != accessSession ||
        accessJti is! String ||
        !_uuidPattern.hasMatch(accessJti) ||
        refreshJti is! String ||
        !_uuidPattern.hasMatch(refreshJti) ||
        refreshJti == accessJti ||
        accessIssuedAt is! int ||
        refreshIssuedAt != accessIssuedAt ||
        accessExpiresAt is! int ||
        refreshExpiresAt is! int ||
        accessExpiresAt <= accessIssuedAt ||
        refreshExpiresAt <= refreshIssuedAt ||
        accessExpiresAt > refreshExpiresAt ||
        refreshExpiresAt <= _now().millisecondsSinceEpoch ~/ 1000) {
      return false;
    }
    return true;
  }

  Map<String, dynamic>? _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (header is! Map<String, dynamic> ||
          header['alg'] != 'HS256' ||
          payload is! Map<String, dynamic>) {
        return null;
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacyCredentials(AuthPreferences preferences) async {
    await _removePreference(preferences, legacyAccessTokenKey);
    await _removePreference(preferences, legacyRefreshTokenKey);
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
