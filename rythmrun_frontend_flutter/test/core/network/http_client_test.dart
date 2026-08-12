import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

void main() {
  test('reads the backend stable code field', () async {
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'code': 'AUTH_ACCESS_INVALID',
            'message': 'Authentication is required',
            'statusCode': 401,
          }),
          401,
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('https://example.test/api/users/me', maxRetries: 0),
      throwsA(
        isA<UnauthorizedException>()
            .having((error) => error.code, 'code', 'AUTH_ACCESS_INVALID')
            .having(
              (error) => error.message,
              'message',
              'Authentication is required',
            ),
      ),
    );
  });

  test('ignores a legacy error field — the code fallback is gone', () async {
    // Phase 4 dropped the `error`-field heuristic: a body that carries only the
    // old `error` key yields no stable code, so nothing keeps the client and a
    // backend that still emitted `error` accidentally compatible.
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'error': 'AUTH_ACCESS_INVALID',
            'message': 'Authentication is required',
          }),
          401,
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('https://example.test/api/users/me', maxRetries: 0),
      throwsA(
        isA<UnauthorizedException>()
            .having((error) => error.code, 'code', isNull)
            .having(
              (error) => error.message,
              'message',
              'Authentication is required',
            ),
      ),
    );
  });

  test('classifies every 5xx response as a server failure', () async {
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'code': 'AUTH_SERVICE_UNAVAILABLE',
            'message': 'Authentication service is temporarily unavailable',
            'retryable': true,
          }),
          503,
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.get('https://example.test/api/users/me', maxRetries: 0),
      throwsA(
        isA<ServerException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.code, 'code', 'AUTH_SERVICE_UNAVAILABLE')
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('mutation methods do not retry ClientException by default', () async {
    var calls = 0;
    final client = AppHttpClient(
      client: MockClient((_) async {
        calls++;
        throw http.ClientException('low-level detail token=secret');
      }),
    );
    addTearDown(client.close);

    Future<void> expectSanitized(Future<http.Response> request) async {
      await expectLater(
        request,
        throwsA(
          isA<NetworkException>()
              .having((error) => error.kind, 'kind', NetworkFailureKind.client)
              .having(
                (error) => error.message,
                'message',
                isNot(contains('secret')),
              ),
        ),
      );
    }

    await expectSanitized(client.post('https://example.test/mutation'));
    expect(calls, 1);
    await expectSanitized(client.put('https://example.test/mutation'));
    expect(calls, 2);
    await expectSanitized(client.delete('https://example.test/mutation'));
    expect(calls, 3);
  });

  test('retains structured activity rejection metadata', () async {
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'status': 'error',
            'code': 'ACTIVITY_DOMAIN_INVALID',
            'message': 'Activity payload is invalid',
            'retryable': false,
          }),
          422,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.post('https://example.test/api/activities', maxRetries: 0),
      throwsA(
        isA<HttpStatusException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having((error) => error.code, 'code', 'ACTIVITY_DOMAIN_INVALID')
            .having((error) => error.retryable, 'retryable', isFalse)
            .having(
              (error) => error.message,
              'message',
              'Activity payload is invalid',
            ),
      ),
    );
  });

  test('preserves retryable admission metadata', () async {
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'code': 'ACTIVITY_REQUEST_BUSY',
            'message': 'Another activity request is already in progress',
            'retryable': true,
          }),
          429,
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.post('https://example.test/api/activities', maxRetries: 0),
      throwsA(
        isA<HttpStatusException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.code, 'code', 'ACTIVITY_REQUEST_BUSY')
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('keeps a proxy-generated 413 classifiable without JSON', () async {
    final client = AppHttpClient(
      client: MockClient(
        (_) async => http.Response(
          'request entity too large',
          413,
          reasonPhrase: 'Content Too Large',
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.post('https://example.test/api/activities', maxRetries: 0),
      throwsA(
        isA<HttpStatusException>()
            .having((error) => error.statusCode, 'statusCode', 413)
            .having((error) => error.code, 'code', isNull)
            .having((error) => error.retryable, 'retryable', isNull),
      ),
    );
  });
}
