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

  test(
    'profile update sends declared fields and parses the safe user',
    () async {
      http.Request? captured;
      final httpClient = AppHttpClient(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'id': 7,
              'username': 'runner@example.test',
              'firstname': 'Renamed',
              'lastname': 'Runner',
              'profilePicturePath': null,
              'profilePictureType': null,
            }),
            200,
          );
        }),
      );
      addTearDown(httpClient.close);
      final dataSource = AuthRemoteDataSource(httpClient: httpClient);

      final updated = await dataSource.updateProfile(
        'Renamed',
        'Runner',
        <String, String>{'Authorization': 'Bearer opaque-access-token'},
      );

      expect(captured?.method, 'PUT');
      expect(captured?.url.path, '/api/users/profile');
      expect(captured?.headers['Authorization'], 'Bearer opaque-access-token');
      // The wire body carries exactly the two declared lowercase fields.
      expect(jsonDecode(captured!.body), <String, Object>{
        'firstname': 'Renamed',
        'lastname': 'Runner',
      });
      expect(updated.id, '7');
      expect(updated.firstName, 'Renamed');
      expect(updated.lastName, 'Runner');
      expect(updated.email, 'runner@example.test');
    },
  );

  test('profile update never retries a transport failure', () async {
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
      dataSource.updateProfile('Renamed', 'Runner', const <String, String>{}),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, 1);
  });
}
