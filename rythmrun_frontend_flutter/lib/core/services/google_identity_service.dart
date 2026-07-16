import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';

/// Narrow seam around the native Google SDK.
///
/// A null token means the user dismissed the account chooser. All other
/// failures are surfaced as [GoogleIdentityException]s so presentation code
/// does not depend on plugin-specific exception types.
abstract interface class GoogleIdentityService {
  Future<String?> authenticate();

  Future<void> signOut();
}

final class GoogleIdentityException implements Exception {
  const GoogleIdentityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Testable adapter for the v7 plugin singleton.
abstract interface class GoogleSignInClient {
  Future<void> initialize({String? clientId, String? serverClientId});

  bool supportsAuthenticate();

  Future<String?> authenticateIdToken();

  Future<void> signOut();
}

final class PluginGoogleSignInClient implements GoogleSignInClient {
  PluginGoogleSignInClient({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) {
    return _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  @override
  bool supportsAuthenticate() => _googleSignIn.supportsAuthenticate();

  @override
  Future<String?> authenticateIdToken() async {
    final account = await _googleSignIn.authenticate();
    return account.authentication.idToken;
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}

/// Production Google identity adapter.
///
/// The v7 plugin singleton must be initialized exactly once. Initialization is
/// therefore lazy and memoized, which also keeps app startup independent of an
/// optional sign-in provider.
final class NativeGoogleIdentityService implements GoogleIdentityService {
  NativeGoogleIdentityService({
    GoogleSignInClient? client,
    String? clientId,
    String? serverClientId,
    bool backendUsesSecureTransport = true,
    bool clientIdRequired = false,
  }) : _client = client ?? PluginGoogleSignInClient(),
       _clientId = _normalized(clientId),
       _serverClientId = _normalized(serverClientId),
       _backendUsesSecureTransport = backendUsesSecureTransport,
       _clientIdRequired = clientIdRequired;

  final GoogleSignInClient _client;
  final String? _clientId;
  final String? _serverClientId;
  final bool _backendUsesSecureTransport;
  final bool _clientIdRequired;
  Future<void>? _initialization;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<String?> authenticate() => _serialize(_authenticate);

  Future<String?> _authenticate() async {
    try {
      await _ensureInitialized();
      if (!_client.supportsAuthenticate()) {
        throw const GoogleIdentityException(
          'Google sign-in is not supported on this platform.',
        );
      }

      // Underlying SDKs generally support a single current user. Clearing any
      // stale native session also ensures an account chooser is available when
      // a runner deliberately switches accounts.
      await _client.signOut();
      final idToken = _normalized(await _client.authenticateIdToken());
      if (idToken == null) {
        await _bestEffortSignOut();
        throw const GoogleIdentityException(
          'Google did not return an identity token. Check the OAuth client configuration.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw GoogleIdentityException(_messageFor(error.code));
    }
  }

  @override
  Future<void> signOut() => _serialize(_signOut);

  Future<void> _signOut() async {
    await _ensureInitialized();
    await _client.signOut();
  }

  Future<void> _ensureInitialized() {
    if (!_backendUsesSecureTransport) {
      throw const GoogleIdentityException(
        'Google sign-in requires a secure HTTPS backend connection.',
      );
    }
    if (_serverClientId == null) {
      throw const GoogleIdentityException(
        'Google sign-in is not configured for this build.',
      );
    }
    if (_clientIdRequired && _clientId == null) {
      throw const GoogleIdentityException(
        'Google sign-in is not configured for this platform.',
      );
    }
    return _initialization ??= _client.initialize(
      clientId: _clientId,
      serverClientId: _serverClientId,
    );
  }

  Future<void> _bestEffortSignOut() async {
    try {
      await _client.signOut();
    } catch (_) {
      // The original authentication failure is more useful to the caller.
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _messageFor(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured correctly for this app.',
      GoogleSignInExceptionCode.interrupted =>
        'Google sign-in was interrupted. Please try again.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in is temporarily unavailable. Please try again.',
      _ => 'Google sign-in failed. Please try again.',
    };
  }
}
