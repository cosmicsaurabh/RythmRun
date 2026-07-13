import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/auth_remote_datasource.dart';

void main() {
  test(
    'preserves structured login rejection instead of string-wrapping it',
    () async {
      final httpClient = AppHttpClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object>{
              'error': 'AUTH_INVALID_CREDENTIALS',
              'message': 'Invalid username or password',
            }),
            401,
          ),
        ),
      );
      addTearDown(httpClient.close);
      final dataSource = AuthRemoteDataSource(httpClient: httpClient);

      await expectLater(
        dataSource.loginUser('runner@example.test', 'incorrect'),
        throwsA(
          isA<UnauthorizedException>().having(
            (error) => error.code,
            'code',
            'AUTH_INVALID_CREDENTIALS',
          ),
        ),
      );
    },
  );

  test('refresh rotation never retries a transport failure', () async {
    var calls = 0;
    final httpClient = AppHttpClient(
      client: MockClient((_) async {
        calls++;
        throw http.ClientException('connection closed');
      }),
    );
    addTearDown(httpClient.close);
    final dataSource = AuthRemoteDataSource(httpClient: httpClient);

    await expectLater(
      dataSource.refreshToken('refresh-presented-once'),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, 1);
  });

  test('session verification uses the protected users/me endpoint', () async {
    Uri? requestedUrl;
    final httpClient = AppHttpClient(
      client: MockClient((request) async {
        requestedUrl = request.url;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(httpClient.close);
    final dataSource = AuthRemoteDataSource(httpClient: httpClient);

    final valid = await dataSource.verifySession(<String, String>{
      'Authorization': 'Bearer opaque-access-token',
    });

    expect(valid, isTrue);
    expect(requestedUrl?.path, '/api/users/me');
  });
}
