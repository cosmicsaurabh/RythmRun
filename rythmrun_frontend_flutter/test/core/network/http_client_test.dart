import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';

void main() {
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
