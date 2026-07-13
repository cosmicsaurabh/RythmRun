import 'dart:convert';

import '../../core/config/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/network/authenticated_request_coordinator.dart';
import '../../core/network/http_client.dart';

class ActivityRemoteDataSource {
  final AppHttpClient _httpClient;
  final AuthenticatedRequestExecutor _authenticatedRequests;

  ActivityRemoteDataSource({
    required AppHttpClient httpClient,
    required AuthenticatedRequestExecutor authenticatedRequests,
  }) : _httpClient = httpClient,
       _authenticatedRequests = authenticatedRequests;

  /// Push workout to server. Returns server-assigned activity ID.
  Future<int> createActivity(Map<String, dynamic> activityJson) async {
    final response = await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => _httpClient.post(
            AppConfig.getUrl(ApiEndpoints.activities),
            headers: {'Content-Type': 'application/json', ...authHeaders},
            body: json.encode(activityJson),
            // clientSyncId makes a lost-response transport retry safe.
            maxRetries: 2,
          ),
    );

    final jsonResponse = json.decode(response.body);
    if (jsonResponse is! Map<String, dynamic>) {
      throw Exception('Invalid activity create response');
    }

    final responseData = jsonResponse['data'];
    if (responseData is! Map<String, dynamic>) {
      throw Exception('Activity response did not contain a data payload');
    }

    final activityId = responseData['id'];
    if (activityId is num) {
      return activityId.toInt();
    }

    throw Exception('Activity response did not contain a valid ID');
  }

  Future<void> deleteActivity(int activityId) async {
    await _authenticatedRequests.execute(
      replayPolicy: AuthenticatedReplayPolicy.idempotent,
      request:
          (authHeaders) => _httpClient.delete(
            AppConfig.getUrl('${ApiEndpoints.activities}/$activityId'),
            headers: authHeaders,
            maxRetries: 0,
          ),
    );
  }
}
