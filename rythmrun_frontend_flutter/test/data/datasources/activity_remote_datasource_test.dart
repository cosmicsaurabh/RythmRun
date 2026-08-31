import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/activity_remote_datasource.dart';

void main() {
  test('activity restore GET uses idempotent authenticated replay', () async {
    final authenticatedRequests = _FakeAuthenticatedRequests();
    final dataSource = ActivityRemoteDataSource(
      httpClient: _FakeHttpClient(),
      authenticatedRequests: authenticatedRequests,
    );

    await dataSource.fetchActivities();

    expect(
      authenticatedRequests.lastReplayPolicy,
      AuthenticatedReplayPolicy.idempotent,
    );
  });
}

class _FakeAuthenticatedRequests implements AuthenticatedRequestExecutor {
  AuthenticatedReplayPolicy? lastReplayPolicy;

  @override
  Future<T> execute<T>({
    required Future<T> Function(Map<String, String> authHeaders) request,
    AuthenticatedReplayPolicy replayPolicy = AuthenticatedReplayPolicy.never,
  }) {
    lastReplayPolicy = replayPolicy;
    return request(const <String, String>{
      'Authorization': 'Bearer access-token',
    });
  }
}

class _FakeHttpClient extends AppHttpClient {
  @override
  Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    int maxRetries = 2,
  }) async {
    return http.Response(
      jsonEncode(<String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'activities': <dynamic>[],
          'pagination': <String, dynamic>{'hasNextPage': false},
        },
      }),
      200,
    );
  }
}
