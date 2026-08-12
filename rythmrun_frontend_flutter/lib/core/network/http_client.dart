import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Configured HTTP client with proper timeout and error handling
class AppHttpClient {
  late final http.Client _client;
  final Duration _timeout;

  AppHttpClient({Duration? timeout, http.Client? client})
    : _timeout = timeout ?? AppConfig.timeout {
    _client = client ?? http.Client();
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
    int maxRetries = 0,
  }) async {
    return _makeRequest(
      () => _client.post(Uri.parse(url), headers: headers, body: body),
      maxRetries: maxRetries,
    );
  }

  /// Submit a multipart form. The request is rebuilt for each attempt so its
  /// byte stream is never reused. Upload callers should normally disable
  /// retries because a storage write is not guaranteed to be idempotent.
  Future<http.Response> postMultipart(
    String url, {
    required Map<String, String> fields,
    required String fileField,
    required List<int> fileBytes,
    required String filename,
    int maxRetries = 0,
  }) async {
    return _makeRequest(() async {
      final request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(fileField, fileBytes, filename: filename),
      );

      final streamedResponse = await _client.send(request);
      return http.Response.fromStream(streamedResponse);
    }, maxRetries: maxRetries);
  }

  /// Make a PUT request
  Future<http.Response> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 0,
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
    int maxRetries = 0,
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
    if (maxRetries < 0) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'must be non-negative',
      );
    }

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
        var errorMessage = response.reasonPhrase ?? 'Unknown error';
        String? errorCode;
        bool? retryable;
        try {
          final decodedBody = json.decode(response.body);
          if (decodedBody is Map<String, dynamic>) {
            final responseMessage = decodedBody['message'];
            if (responseMessage is String && responseMessage.isNotEmpty) {
              errorMessage = responseMessage;
            }
            final responseCode = decodedBody['code'];
            if (responseCode is String && responseCode.isNotEmpty) {
              errorCode = responseCode;
            }
            final responseRetryable = decodedBody['retryable'];
            if (responseRetryable is bool) {
              retryable = responseRetryable;
            }
          }
        } on FormatException {
          // Proxy and infrastructure errors are not guaranteed to be JSON.
        }

        switch (response.statusCode) {
          case 401:
            throw UnauthorizedException(
              errorMessage,
              code: errorCode,
              retryable: retryable,
            );
          case 403:
            throw ForbiddenException(
              errorMessage,
              code: errorCode,
              retryable: retryable,
            );
          case 404:
            throw NotFoundException(
              errorMessage,
              code: errorCode,
              retryable: retryable,
            );
          case >= 500 && <= 599:
            throw ServerException(
              errorMessage,
              statusCode: response.statusCode,
              code: errorCode,
              retryable: retryable,
            );
          default:
            throw HttpStatusException(
              response.statusCode,
              errorMessage,
              code: errorCode,
              retryable: retryable,
            );
        }
      } on HandshakeException {
        attempts++;
        if (attempts > maxRetries) {
          throw const NetworkException(
            'A secure connection could not be established.',
            kind: NetworkFailureKind.tls,
          );
        }
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } on SocketException {
        attempts++;
        if (attempts > maxRetries) {
          throw const NetworkException(
            'The service could not be reached. Check your connection.',
            kind: NetworkFailureKind.offline,
          );
        }
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } on TimeoutException {
        attempts++;
        if (attempts > maxRetries) {
          throw const NetworkException(
            'The request timed out. Try again.',
            kind: NetworkFailureKind.timeout,
          );
        }
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } on http.ClientException {
        attempts++;
        if (attempts > maxRetries) {
          throw const NetworkException(
            'The network request could not be completed.',
            kind: NetworkFailureKind.client,
          );
        }
        await Future.delayed(Duration(milliseconds: 1000 * attempts));
      } catch (e) {
        // Re-throw other exceptions without retrying
        rethrow;
      }
    }

    throw const NetworkException('The network request could not be completed.');
  }

  /// Close the HTTP client
  void close() {
    _client.close();
  }
}

/// Custom exceptions for better error handling
class HttpStatusException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final bool? retryable;

  const HttpStatusException(
    this.statusCode,
    this.message, {
    this.code,
    this.retryable,
  });

  @override
  String toString() => 'HttpStatusException($statusCode): $message';
}

enum NetworkFailureKind { offline, timeout, tls, client }

class NetworkException implements Exception {
  final String message;
  final NetworkFailureKind kind;

  const NetworkException(this.message, {this.kind = NetworkFailureKind.client});

  @override
  String toString() => 'NetworkException: $message';
}

class UnauthorizedException extends HttpStatusException {
  UnauthorizedException(String message, {String? code, bool? retryable})
    : super(401, message, code: code, retryable: retryable);

  @override
  String toString() => 'UnauthorizedException: $message';
}

class ForbiddenException extends HttpStatusException {
  ForbiddenException(String message, {String? code, bool? retryable})
    : super(403, message, code: code, retryable: retryable);

  @override
  String toString() => 'ForbiddenException: $message';
}

class NotFoundException extends HttpStatusException {
  NotFoundException(String message, {String? code, bool? retryable})
    : super(404, message, code: code, retryable: retryable);

  @override
  String toString() => 'NotFoundException: $message';
}

class ServerException extends HttpStatusException {
  ServerException(
    String message, {
    int statusCode = 500,
    String? code,
    bool? retryable,
  }) : super(statusCode, message, code: code, retryable: retryable);

  @override
  String toString() => 'ServerException: $message';
}
