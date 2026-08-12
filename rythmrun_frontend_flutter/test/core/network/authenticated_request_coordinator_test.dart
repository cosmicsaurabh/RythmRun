import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/auth_token_store.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/core/services/session_invalidation_signal.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/auth_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/user_model.dart';

void main() {
  late _FakeCredentialVault vault;
  late AppHttpClient unusedHttpClient;
  late _FakeAuthRemoteDataSource remote;
  late SessionInvalidationSignal invalidationSignal;
  late AuthenticatedRequestCoordinator coordinator;

  setUp(() {
    vault = _FakeCredentialVault(
      _snapshot(access: 'access-1', refresh: 'refresh-1'),
    );
    unusedHttpClient = AppHttpClient(
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    remote = _FakeAuthRemoteDataSource(unusedHttpClient);
    invalidationSignal = SessionInvalidationSignal();
    coordinator = AuthenticatedRequestCoordinator(
      credentialVault: vault,
      rejectedCredentialQuarantine: vault,
      authRemoteDataSource: remote,
      authenticationAttemptGate: AuthenticationAttemptGate(),
      sessionInvalidationSignal: invalidationSignal,
      commitRefreshedSession: (_) async {},
      commitServerVerification: () async {},
    );
  });

  tearDown(() async {
    unusedHttpClient.close();
    await invalidationSignal.dispose();
  });

  test(
    'three concurrent access rejections share one refresh and replay once',
    () async {
      remote.onRefresh = (_) async {
        await Future<void>.delayed(Duration.zero);
        return _response(access: 'access-2', refresh: 'refresh-2');
      };
      final attempts = <int, int>{};

      Future<String> run(int requestId) {
        return coordinator.execute<String>(
          replayPolicy: AuthenticatedReplayPolicy.idempotent,
          request: (headers) async {
            final attempt = (attempts[requestId] ?? 0) + 1;
            attempts[requestId] = attempt;
            if (attempt == 1) {
              expect(headers['Authorization'], 'Bearer access-1');
              throw UnauthorizedException(
                'expired',
                code: AuthenticatedRequestCoordinator.invalidAccessCode,
              );
            }
            expect(headers['Authorization'], 'Bearer access-2');
            return 'request-$requestId';
          },
        );
      }

      final results = await Future.wait(<Future<String>>[
        run(1),
        run(2),
        run(3),
      ]);

      expect(results, <String>['request-1', 'request-2', 'request-3']);
      expect(remote.refreshCalls, 1);
      expect(vault.compareAndSetCalls, 1);
      expect(attempts, <int, int>{1: 2, 2: 2, 3: 2});
      expect(vault.current!.pair.accessToken, 'access-2');
      expect(vault.current!.pair.refreshToken, 'refresh-2');
    },
  );

  test(
    'a second access rejection is surfaced without recursive refresh',
    () async {
      remote.onRefresh =
          (_) async => _response(access: 'access-2', refresh: 'refresh-2');
      var requestCalls = 0;

      await expectLater(
        coordinator.execute<void>(
          replayPolicy: AuthenticatedReplayPolicy.idempotent,
          request: (_) async {
            requestCalls++;
            throw UnauthorizedException(
              'expired',
              code: AuthenticatedRequestCoordinator.invalidAccessCode,
            );
          },
        ),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(requestCalls, 2);
      expect(remote.refreshCalls, 1);
      expect(vault.compareAndSetCalls, 1);
    },
  );

  test('403 never refreshes', () async {
    await expectLater(
      coordinator.execute<void>(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request: (_) async => throw ForbiddenException('forbidden'),
      ),
      throwsA(isA<ForbiddenException>()),
    );

    expect(remote.refreshCalls, 0);
    expect(vault.compareAndSetCalls, 0);
  });

  test('a different 401 code never refreshes', () async {
    await expectLater(
      coordinator.execute<void>(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request:
            (_) async =>
                throw UnauthorizedException(
                  'invalid',
                  code: 'AUTH_INVALID_CREDENTIALS',
                ),
      ),
      throwsA(isA<UnauthorizedException>()),
    );

    expect(remote.refreshCalls, 0);
  });

  test(
    'network refresh failure preserves credentials and is retryable',
    () async {
      final before = vault.current;
      remote.onRefresh =
          (_) async =>
              throw const NetworkException(
                'offline details that must not escape',
                kind: NetworkFailureKind.offline,
              );

      await expectLater(
        _accessRejectedRequest(coordinator),
        throwsA(
          isA<AuthSessionUnavailable>()
              .having(
                (error) => error.reason,
                'reason',
                AuthSessionUnavailableReason.network,
              )
              .having((error) => error.retryable, 'retryable', isTrue),
        ),
      );

      expect(vault.current, same(before));
      expect(vault.compareAndSetCalls, 0);
    },
  );

  test(
    'explicit invalid refresh clears its exact revision before invalidation',
    () async {
      final eventFuture = invalidationSignal.events.first;
      remote.onRefresh =
          (_) async =>
              throw UnauthorizedException(
                'rejected',
                code: AuthenticatedRequestCoordinator.invalidRefreshCode,
              );

      await expectLater(
        _accessRejectedRequest(coordinator),
        throwsA(
          isA<AuthSessionInvalid>()
              .having(
                (error) => error.reason,
                'reason',
                AuthSessionInvalidReason.refreshRejected,
              )
              .having((error) => error.retryable, 'retryable', isFalse),
        ),
      );

      final event = await eventFuture;
      expect(event.reason, SessionInvalidationReason.refreshRejected);
      expect(event.credentialRevision, 1);
      expect(vault.current, isNull);
      expect(vault.clearIfRevisionCalls, 1);
      expect(vault.compareAndSetCalls, 0);
    },
  );

  test('revision change during refresh rejects the stale result', () async {
    final refreshStarted = Completer<void>();
    final finishRefresh = Completer<AuthResponseModel>();
    remote.onRefresh = (_) {
      refreshStarted.complete();
      return finishRefresh.future;
    };

    final request = _accessRejectedRequest(coordinator);
    await refreshStarted.future;
    vault.replaceExternally(access: 'other-access', refresh: 'other-refresh');
    finishRefresh.complete(
      _response(access: 'stale-access', refresh: 'stale-refresh'),
    );

    await expectLater(
      request,
      throwsA(
        isA<AuthSessionUnavailable>().having(
          (error) => error.reason,
          'reason',
          AuthSessionUnavailableReason.credentialsChanged,
        ),
      ),
    );
    expect(vault.current!.pair.accessToken, 'other-access');
    expect(vault.compareAndSetCalls, 1);
  });

  test(
    'a staggered 401 from an active old-revision request reuses the completed flight',
    () async {
      remote.onRefresh =
          (_) async => _response(access: 'access-2', refresh: 'refresh-2');
      final releaseLateRejection = Completer<void>();
      final lateRequestStarted = Completer<void>();
      var earlyCalls = 0;
      var lateCalls = 0;

      final lateRequest = coordinator.execute<String>(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request: (headers) async {
          lateCalls++;
          if (lateCalls == 1) {
            expect(headers['Authorization'], 'Bearer access-1');
            lateRequestStarted.complete();
            await releaseLateRejection.future;
            throw UnauthorizedException(
              'expired',
              code: AuthenticatedRequestCoordinator.invalidAccessCode,
            );
          }
          expect(headers['Authorization'], 'Bearer access-2');
          return 'late';
        },
      );
      await lateRequestStarted.future;

      final earlyResult = await coordinator.execute<String>(
        replayPolicy: AuthenticatedReplayPolicy.idempotent,
        request: (headers) async {
          earlyCalls++;
          if (earlyCalls == 1) {
            throw UnauthorizedException(
              'expired',
              code: AuthenticatedRequestCoordinator.invalidAccessCode,
            );
          }
          expect(headers['Authorization'], 'Bearer access-2');
          return 'early';
        },
      );
      expect(earlyResult, 'early');

      releaseLateRejection.complete();
      expect(await lateRequest, 'late');
      expect(remote.refreshCalls, 1);
      expect(earlyCalls, 2);
      expect(lateCalls, 2);
    },
  );

  test(
    'a stale invalid refresh cannot clear a newer credential pair',
    () async {
      final refreshStarted = Completer<void>();
      final finishRefresh = Completer<AuthResponseModel>();
      final events = <SessionInvalidationEvent>[];
      final subscription = invalidationSignal.events.listen(events.add);
      addTearDown(subscription.cancel);
      remote.onRefresh = (_) {
        refreshStarted.complete();
        return finishRefresh.future;
      };

      final request = _accessRejectedRequest(coordinator);
      await refreshStarted.future;
      vault.replaceExternally(access: 'new-login', refresh: 'new-refresh');
      finishRefresh.completeError(
        UnauthorizedException(
          'rejected',
          code: AuthenticatedRequestCoordinator.invalidRefreshCode,
        ),
      );

      await expectLater(
        request,
        throwsA(
          isA<AuthSessionUnavailable>().having(
            (error) => error.reason,
            'reason',
            AuthSessionUnavailableReason.credentialsChanged,
          ),
        ),
      );
      expect(vault.current!.pair.accessToken, 'new-login');
      expect(vault.clearIfRevisionCalls, 0);
      expect(events, isEmpty);
    },
  );

  test(
    'secure-delete failure persists cleanup fallback before invalidation',
    () async {
      vault.failClear = true;
      final eventFuture = invalidationSignal.events.first;
      remote.onRefresh =
          (_) async =>
              throw UnauthorizedException(
                'rejected',
                code: AuthenticatedRequestCoordinator.invalidRefreshCode,
              );

      await expectLater(
        _accessRejectedRequest(coordinator),
        throwsA(isA<AuthSessionInvalid>()),
      );

      expect(
        (await eventFuture).reason,
        SessionInvalidationReason.refreshRejected,
      );
      expect(vault.current, isNotNull);
      expect(vault.cleanupPending, isTrue);
    },
  );

  test(
    'session-revoking mutation clears credentials and emits its reason',
    () async {
      final eventFuture = invalidationSignal.events.first;

      final result = await coordinator.executeSessionRevoking<String>(
        reason: SessionInvalidationReason.passwordChanged,
        request: (headers) async {
          expect(headers['Authorization'], 'Bearer access-1');
          return 'password changed';
        },
      );

      expect(result, 'password changed');
      expect(vault.current, isNull);
      final event = await eventFuture;
      expect(event.reason, SessionInvalidationReason.passwordChanged);
      expect(event.credentialRevision, 1);
    },
  );

  test('non-idempotent request refreshes but is not replayed', () async {
    remote.onRefresh =
        (_) async => _response(access: 'access-2', refresh: 'refresh-2');
    var requestCalls = 0;

    await expectLater(
      coordinator.execute<void>(
        request: (_) async {
          requestCalls++;
          throw UnauthorizedException(
            'expired',
            code: AuthenticatedRequestCoordinator.invalidAccessCode,
          );
        },
      ),
      throwsA(
        isA<AuthSessionUnavailable>().having(
          (error) => error.reason,
          'reason',
          AuthSessionUnavailableReason.requestNotReplayed,
        ),
      ),
    );

    expect(requestCalls, 1);
    expect(remote.refreshCalls, 1);
    expect(vault.current!.pair.accessToken, 'access-2');
  });

}

Future<void> _accessRejectedRequest(
  AuthenticatedRequestCoordinator coordinator,
) {
  return coordinator.execute<void>(
    replayPolicy: AuthenticatedReplayPolicy.idempotent,
    request:
        (_) async =>
            throw UnauthorizedException(
              'expired',
              code: AuthenticatedRequestCoordinator.invalidAccessCode,
            ),
  );
}

AuthCredentialSnapshot _snapshot({
  required String access,
  required String refresh,
  int revision = 1,
}) {
  return AuthCredentialSnapshot(
    pair: AuthTokenPair(accessToken: access, refreshToken: refresh),
    revision: revision,
  );
}

AuthResponseModel _response({required String access, required String refresh}) {
  return AuthResponseModel(
    user: const UserModel(
      id: '7',
      firstName: 'Ada',
      lastName: 'Runner',
      email: 'ada@example.test',
    ),
    accessToken: access,
    refreshToken: refresh,
  );
}

class _FakeCredentialVault
    implements AuthCredentialVault, RejectedCredentialQuarantine {
  _FakeCredentialVault(this.current);

  AuthCredentialSnapshot? current;
  int compareAndSetCalls = 0;
  int clearIfRevisionCalls = 0;
  bool failClear = false;
  bool cleanupPending = false;

  @override
  Future<AuthCredentialSnapshot?> readCredentialSnapshot() async => current;

  @override
  Future<AuthCredentialSnapshot?> compareAndSetCredentials({
    required int expectedRevision,
    required AuthTokenPair replacement,
  }) async {
    compareAndSetCalls++;
    final existing = current;
    if (existing == null || existing.revision != expectedRevision) return null;
    current = AuthCredentialSnapshot(
      pair: replacement,
      revision: expectedRevision + 1,
    );
    return current;
  }

  @override
  Future<bool> clearCredentialsIfRevision(int expectedRevision) async {
    clearIfRevisionCalls++;
    if (failClear) throw StateError('simulated secure delete failure');
    final existing = current;
    if (existing == null) return true;
    if (existing.revision != expectedRevision) return false;
    current = null;
    return true;
  }

  @override
  Future<void> markAuthCleanupPending() async {
    cleanupPending = true;
  }

  void replaceExternally({required String access, required String refresh}) {
    current = _snapshot(
      access: access,
      refresh: refresh,
      revision: (current?.revision ?? 0) + 1,
    );
  }
}

class _FakeAuthRemoteDataSource extends AuthRemoteDataSource {
  _FakeAuthRemoteDataSource(AppHttpClient httpClient)
    : super(httpClient: httpClient);

  int refreshCalls = 0;
  Future<AuthResponseModel> Function(String refreshToken)? onRefresh;

  @override
  Future<AuthResponseModel> refreshToken(String refreshToken) {
    refreshCalls++;
    final handler = onRefresh;
    if (handler == null) {
      return Future<AuthResponseModel>.value(
        _response(access: 'access-2', refresh: 'refresh-2'),
      );
    }
    return handler(refreshToken);
  }
}
