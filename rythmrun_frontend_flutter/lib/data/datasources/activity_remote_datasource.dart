import 'dart:convert';

import '../../core/config/api_endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/network/http_client.dart';

class ActivityRemoteDataSource {
  final AppHttpClient _httpClient;

  ActivityRemoteDataSource({required AppHttpClient httpClient})
    : _httpClient = httpClient;

  /// Push workout to server. Returns server-assigned activity ID.
  Future<int> createActivity(
    Map<String, dynamic> activityJson,
    Map<String, String> authHeaders,
  ) async {
    final response = await _httpClient.post(
      AppConfig.getUrl(ApiEndpoints.activities),
      headers: {'Content-Type': 'application/json', ...authHeaders},
      body: json.encode(activityJson),
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

  Future<void> deleteActivity(
    int activityId,
    Map<String, String> authHeaders,
  ) async {
    await _httpClient.delete(
      AppConfig.getUrl('${ApiEndpoints.activities}/$activityId'),
      headers: authHeaders,
      maxRetries: 0,
    );
  }
}
