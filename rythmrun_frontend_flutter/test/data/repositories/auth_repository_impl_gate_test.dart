import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_local_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/models/auth_response_model.dart';
import 'package:rythmrun_frontend_flutter/data/models/user_model.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/auth_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';

void main() {
  test(
    'account exit drains refresh persistence and rejects another auth attempt',
    () async {
      final gate = AuthenticationAttemptGate();
      final remote = _DelayedAuthRemoteDataSource();
      final local = _MemoryAuthLocalDataSource();
      final repository = AuthRepositoryImpl(
        remote,
        local,
        authenticationAttemptGate: gate,
      );

      final pendingRefresh = repository.refreshToken();
      await Future<void>.delayed(Duration.zero);
      expect(gate.isActive, isTrue);

      await expectLater(
        repository.login(
          LoginRequestEntity(email: 'b@example.com', password: 'password'),
        ),
        throwsStateError,
      );
      expect(remote.loginCalls, 0);

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) => didDrain = true);
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);

      remote.refreshCompleter.complete(_response);
      await pendingRefresh;
      await drain;
      expect(local.savedResponse, _response);

      await local.clearAuthData();
      expect(local.savedResponse, isNull);
      expect(gate.tryAcquire(), isNull);
    },
  );
}

const _response = AuthResponseModel(
  user: UserModel(
    id: '7',
    firstName: 'A',
    lastName: 'Runner',
    email: 'a@example.com',
  ),
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);

class _DelayedAuthRemoteDataSource extends AuthRemoteDataSource {
  final Completer<AuthResponseModel> refreshCompleter =
      Completer<AuthResponseModel>();
  int loginCalls = 0;

  @override
  Future<AuthResponseModel> refreshToken(String refreshToken) {
    return refreshCompleter.future;
  }

  @override
  Future<AuthResponseModel> loginUser(String email, String password) async {
    loginCalls += 1;
    return _response;
  }
}

class _MemoryAuthLocalDataSource extends AuthLocalDataSource {
  AuthResponseModel? savedResponse;

  @override
  Future<String?> getRefreshToken() async => 'refresh-a';

  @override
  Future<void> saveAuthData(AuthResponseModel authResponse) async {
    savedResponse = authResponse;
  }

  @override
  Future<void> clearAuthData() async {
    savedResponse = null;
  }
}
