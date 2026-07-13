import '../../core/services/auth_persistence_service.dart';
import '../../core/services/auth_token_store.dart';
import '../../domain/entities/user_entity.dart';
import '../models/auth_response_model.dart';

/// Local account data source.
///
/// It is intentionally subclass-friendly for repository tests, while the
/// production implementation delegates to one injected persistence service.
/// Raw individual credential/header getters are not part of this API.
class AuthLocalDataSource
    implements AuthCredentialVault, RejectedCredentialQuarantine {
  AuthLocalDataSource({AuthPersistenceService? persistenceService})
    : _persistenceService = persistenceService ?? AuthPersistenceService();

  final AuthPersistenceService _persistenceService;

  Future<void> saveAuthData(AuthResponseModel authResponse) {
    return _persistenceService.saveAuthData(authResponse);
  }

  @override
  Future<AuthCredentialSnapshot?> readCredentialSnapshot() {
    return _persistenceService.readCredentialSnapshot();
  }

  Future<AuthCredentialSnapshot> replaceCredentials(
    AuthTokenPair replacement, {
    bool requiresServerVerification = false,
  }) {
    return _persistenceService.replaceCredentials(
      replacement,
      requiresServerVerification: requiresServerVerification,
    );
  }

  @override
  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
    bool requiresServerVerification = false,
  }) {
    return _persistenceService.compareAndSetCredentials(
      expectedRevision: expectedRevision,
      replacement: replacement,
      requiresServerVerification: requiresServerVerification,
    );
  }

  @override
  Future<AuthCredentialSnapshot?> markCredentialsServerVerified({
    required int expectedRevision,
  }) {
    return _persistenceService.markCredentialsServerVerified(
      expectedRevision: expectedRevision,
    );
  }

  Future<UserEntity?> getUserData() => _persistenceService.getUserData();

  Future<void> updateUserData(UserEntity user) {
    return _persistenceService.updateUserData(user);
  }

  Future<bool> hasValidSession() => _persistenceService.hasValidSession();

  Future<bool> needsTokenRefresh() => _persistenceService.needsTokenRefresh();

  Future<void> clearCredentials() => _persistenceService.clearCredentials();

  @override
  Future<bool> clearCredentialsIfRevision(int expectedRevision) {
    return _persistenceService.clearCredentialsIfRevision(expectedRevision);
  }

  Future<void> clearAuthData() => _persistenceService.clearAuthData();

  @override
  Future<void> markAuthCleanupPending() {
    return _persistenceService.markAuthCleanupPending();
  }

  Future<bool> hasPendingAuthCleanup() {
    return _persistenceService.hasPendingAuthCleanup();
  }

  Future<bool> needsBackendSync() => _persistenceService.needsBackendSync();

  Future<void> updateLastBackendSync() {
    return _persistenceService.updateLastBackendSync();
  }

  Future<bool> canStayLoggedInOffline() {
    return _persistenceService.canStayLoggedInOffline();
  }

  Future<DateTime?> getLastBackendSync() {
    return _persistenceService.getLastBackendSync();
  }
}
