import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Configured HTTP client with proper timeout and error handling
class AppHttpClient {
  late final http.Client _client;
  final Duration _timeout;

  AppHttpClient({Duration? timeout}) : _timeout = timeout ?? AppConfig.timeout {
    _client = http.Client();
  }

  /// Make a GET request
  Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    int maxRetries = 2,
  }) async {
    return _makeRequest(
      () => _client.get(Uri.parse(url), headers: headers),
      maxRetries: maxRetries,
    );
  }

  /// Make a POST request
  Future<http.Response> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 2,
  }) async {
    return _makeRequest(
      () => _client.post(Uri.parse(url), headers: headers, body: body),
      maxRetries: maxRetries,
    );
  }

  /// Make a PUT request
  Future<http.Response> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 2,
  }) async {
    return _makeRequest(
      () => _client.put(Uri.parse(url), headers: headers, body: body),
      maxRetries: maxRetries,
    );
  }

  /// Make a DELETE request
  Future<http.Response> delete(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 2,
  }) async {
    return _makeRequest(
      () => _client.delete(Uri.parse(url), headers: headers, body: body),
      maxRetries: maxRetries,
    );
  }

  /// Generic request method with retry logic and timeout
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
  }) async {
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        final response = await request().timeout(_timeout);

        // Check if response is successful
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // Handle specific error status codes
        // Try to get error message from response body
        String errorMessage;
        try {
          final Map<String, dynamic> errorBody = json.decode(response.body);
          errorMessage =
              errorBody['message'] ?? errorBody['error'] ?? 'Unknown error';
        } catch (e) {
          // Fallback if response body isn't JSON
          errorMessage = response.reasonPhrase ?? 'Unknown error';
        }

        switch (response.statusCode) {
          case 401:
            throw UnauthorizedException(errorMessage);
          case 403:
            throw ForbiddenException(errorMessage);
          case 404:
            throw NotFoundException(errorMessage);
          case 500:
            throw ServerException(errorMessage);
          default:
            throw HttpException('HTTP ${response.statusCode}: $errorMessage');
        }
      } on SocketException catch (e) {
        attempts++;
        if (attempts > maxRetries) {
          throw NetworkException('Please check your internet connection : $e');
        }
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } on TimeoutException {
        attempts++;
        if (attempts > maxRetries) {
          throw NetworkException(
            'Request timeout after ${_timeout.inSeconds} seconds',
          );
        }
        // Wait before retrying
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } catch (e) {
        // Re-throw other exceptions without retrying
        rethrow;
      }
    }

    throw NetworkException('Request failed after ${maxRetries + 1} attempts');
  }

  /// Close the HTTP client
  void close() {
    _client.close();
  }
}

/// Custom exceptions for better error handling
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);

  @override
  String toString() => 'UnauthorizedException: $message';
}

class ForbiddenException implements Exception {
  final String message;
  ForbiddenException(this.message);

  @override
  String toString() => 'ForbiddenException: $message';
}

class NotFoundException implements Exception {
  final String message;
  NotFoundException(this.message);

  @override
  String toString() => 'NotFoundException: $message';
}

class ServerException implements Exception {
  final String message;
  ServerException(this.message);

  @override
  String toString() => 'ServerException: $message';
}
