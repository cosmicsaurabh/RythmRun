import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/network/authenticated_request_coordinator.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/services/online_operation_guard.dart';
import 'package:rythmrun_frontend_flutter/data/datasources/avatar_remote_datasource.dart';
import 'package:rythmrun_frontend_flutter/data/repositories/avatar_repository_impl.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';

void main() {
  group('AvatarRemoteDataSourceImpl', () {
    test('sends the exact MIME type and byte count to the backend', () async {
      final httpClient = _FakeRemoteHttpClient();
      final dataSource = AvatarRemoteDataSourceImpl(
        httpClient,
        _FakeAuthenticatedRequests(),
      );

      final authorization = await dataSource.getUploadUrl(
        'jpg',
        'image/jpeg',
        321,
      );

      expect(jsonDecode(httpClient.requestBody! as String), {
        'ext': 'jpg',
        'contentType': 'image/jpeg',
        'sizeBytes': 321,
      });
      expect(
        httpClient.requestHeaders?['Authorization'],
        'Bearer access-token',
      );
      expect(httpClient.requestMaxRetries, 0);
      expect(authorization.key, 'avatars/7/issued.jpg');
      expect(authorization.requiredHeaders, {
        'Content-Type': 'image/jpeg',
        'Content-Length': '321',
      });
    });

    test('requests upload authorization with idempotent replay', () async {
      final authenticatedRequests = _FakeAuthenticatedRequests();
      final dataSource = AvatarRemoteDataSourceImpl(
        _FakeRemoteHttpClient(),
        authenticatedRequests,
      );

      // Fetching an upload URL is safe to replay after a refresh: it only mints
      // a fresh presigned PUT and single-use intent, so a lost-response retry
      // must not fail the upload.
      await dataSource.getUploadUrl('jpg', 'image/jpeg', 321);

      expect(
        authenticatedRequests.lastReplayPolicy,
        AuthenticatedReplayPolicy.idempotent,
      );
    });

    test('fetches an authenticated signed avatar read URL', () async {
      final httpClient = _FakeRemoteHttpClient();
      final dataSource = AvatarRemoteDataSourceImpl(
        httpClient,
        _FakeAuthenticatedRequests(),
      );

      final url = await dataSource.getReadUrl();

      expect(url.toString(), 'https://signed.example.test/avatar.jpg?token=1');
      expect(httpClient.lastGetUrl, contains('/avatar/read-url'));
      expect(
        httpClient.requestHeaders?['Authorization'],
        'Bearer access-token',
      );
    });
  });

  group('AvatarUploadAuthorization', () {
    test('accepts the constrained PUT contract', () {
      final authorization = AvatarUploadAuthorization.fromJson({
        'uploadUrl': 'https://uploads.example.test/',
        'uploadMethod': 'PUT',
        'key': 'avatars/7/id.jpg',
        'requiredHeaders': {
          'Content-Type': 'image/jpeg',
          'Content-Length': '3',
        },
      });

      expect(authorization.key, 'avatars/7/id.jpg');
      expect(authorization.uploadUri.scheme, 'https');
      expect(authorization.requiredHeaders['Content-Type'], 'image/jpeg');
    });

    test('rejects POST or missing signed upload headers', () {
      expect(
        () => AvatarUploadAuthorization.fromJson({
          'uploadUrl': 'https://uploads.example.test/',
          'uploadMethod': 'POST',
          'key': 'avatars/7/id.jpg',
          'requiredHeaders': {
            'Content-Type': 'image/jpeg',
            'Content-Length': '3',
          },
        }),
        throwsFormatException,
      );

      expect(
        () => AvatarUploadAuthorization.fromJson({
          'uploadUrl': 'https://uploads.example.test/',
          'uploadMethod': 'PUT',
          'key': 'avatars/7/id.jpg',
          'requiredHeaders': <String, String>{},
        }),
        throwsFormatException,
      );
    });
  });

  group('AvatarRepositoryImpl', () {
    late _FakeAvatarRemoteDataSource remote;
    late _FakeAuthRepository authRepository;
    late _FakeHttpClient httpClient;
    late AvatarRepositoryImpl repository;

    setUp(() {
      remote = _FakeAvatarRemoteDataSource();
      authRepository = _FakeAuthRepository();
      httpClient = _FakeHttpClient();
      repository = AvatarRepositoryImpl(remote, authRepository, httpClient);
    });

    test(
      'uses byte-bound PUT authorization and confirms the issued key',
      () async {
        final result = await repository.uploadAvatar(
          XFile.fromData(
            Uint8List.fromList(<int>[1, 2, 3]),
            mimeType: 'IMAGE/JPEG; charset=binary',
            name: 'picked.jpeg',
          ),
        );

        expect(remote.requestedExtension, 'jpg');
        expect(remote.requestedContentType, 'image/jpeg');
        expect(remote.requestedSizeBytes, 3);
        expect(
          httpClient.uploadedHeaders,
          remote.authorization.requiredHeaders,
        );
        expect(httpClient.uploadedBytes, <int>[1, 2, 3]);
        expect(httpClient.maxRetries, 0);
        expect(remote.confirmedKey, remote.authorization.key);
        expect(result.key, remote.authorization.key);
      },
    );

    test(
      'rejects unsupported and oversized files before authorization',
      () async {
        await expectLater(
          repository.uploadAvatar(
            XFile.fromData(
              Uint8List.fromList(<int>[1]),
              mimeType: 'image/gif',
              name: 'avatar.gif',
            ),
          ),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          repository.uploadAvatar(
            XFile.fromData(
              Uint8List(10 * 1024 * 1024 + 1),
              mimeType: 'image/jpeg',
              name: 'avatar.jpg',
            ),
          ),
          throwsA(isA<Exception>()),
        );

        expect(remote.requestCount, 0);
        expect(httpClient.uploadCount, 0);
      },
    );

    test('rejects upload authorization for a different byte count', () async {
      remote.authorization = AvatarUploadAuthorization.fromJson({
        'uploadUrl': 'https://uploads.example.test/',
        'uploadMethod': 'PUT',
        'key': 'avatars/7/issued.jpg',
        'requiredHeaders': {
          'Content-Type': 'image/jpeg',
          'Content-Length': '4',
        },
      });

      await expectLater(
        repository.uploadAvatar(
          XFile.fromData(
            Uint8List.fromList(<int>[1, 2, 3]),
            mimeType: 'image/jpeg',
            name: 'avatar.jpg',
          ),
        ),
        throwsA(isA<Exception>()),
      );

      expect(httpClient.uploadCount, 0);
      expect(remote.confirmedKey, isNull);
    });

    test(
      'does not expose storage credentials or object keys in failures',
      () async {
        const sensitiveKey = 'avatars/7/private-object.jpg';
        const sensitiveSignature = 'super-secret-signature';
        remote.authorization = AvatarUploadAuthorization.fromJson({
          'uploadUrl':
              'https://uploads.example.test/?signature=$sensitiveSignature',
          'uploadMethod': 'PUT',
          'key': sensitiveKey,
          'requiredHeaders': {
            'Content-Type': 'image/jpeg',
            'Content-Length': '1',
          },
        });
        httpClient.error = Exception('$sensitiveKey $sensitiveSignature');

        try {
          await repository.uploadAvatar(
            XFile.fromData(
              Uint8List.fromList(<int>[1]),
              mimeType: 'image/jpeg',
              name: 'avatar.jpg',
            ),
          );
          fail('Expected the upload to fail');
        } catch (error) {
          expect(error.toString(), isNot(contains(sensitiveKey)));
          expect(error.toString(), isNot(contains(sensitiveSignature)));
        }
      },
    );

    test(
      'offline mode refuses an avatar upload before authorization',
      () async {
        final guard = OnlineOperationGuard();
        final offlineRepository = AvatarRepositoryImpl(
          remote,
          authRepository,
          httpClient,
          onlineOperationGuard: guard,
        );

        await expectLater(
          offlineRepository.uploadAvatar(
            XFile.fromData(
              Uint8List.fromList(<int>[1, 2, 3]),
              mimeType: 'image/jpeg',
              name: 'picked.jpeg',
            ),
          ),
          throwsA(
            isA<AuthSessionUnavailable>().having(
              (error) => error.reason,
              'reason',
              AuthSessionUnavailableReason.offlineMode,
            ),
          ),
        );
        expect(remote.requestCount, 0);
        expect(httpClient.uploadCount, 0);

        // Once the session is online the same upload proceeds and confirms.
        guard.setOnline(true);
        final result = await offlineRepository.uploadAvatar(
          XFile.fromData(
            Uint8List.fromList(<int>[1, 2, 3]),
            mimeType: 'image/jpeg',
            name: 'picked.jpeg',
          ),
        );
        expect(result.key, remote.authorization.key);
      },
    );
  });
}

class _FakeAvatarRemoteDataSource implements AvatarRemoteDataSource {
  AvatarUploadAuthorization authorization = AvatarUploadAuthorization.fromJson({
    'uploadUrl': 'https://uploads.example.test/',
    'uploadMethod': 'PUT',
    'key': 'avatars/7/issued.jpg',
    'requiredHeaders': {'Content-Type': 'image/jpeg', 'Content-Length': '3'},
  });
  int requestCount = 0;
  String? requestedExtension;
  String? requestedContentType;
  int? requestedSizeBytes;
  String? confirmedKey;

  @override
  Future<AvatarUploadAuthorization> getUploadUrl(
    String ext,
    String contentType,
    int sizeBytes,
  ) async {
    requestCount += 1;
    requestedExtension = ext;
    requestedContentType = contentType;
    requestedSizeBytes = sizeBytes;
    return authorization;
  }

  @override
  Future<void> confirmUpload(String key, String contentType) async {
    confirmedKey = key;
  }

  @override
  Future<Uri> getReadUrl() async =>
      Uri.parse('https://signed.example.test/avatar.jpg?token=1');
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<UserEntity> refreshCurrentUser() => throw UnimplementedError();

  @override
  Future<void> resendVerificationEmail() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<UserEntity?> getCurrentUser() async => const UserEntity(
    id: '7',
    firstName: 'Test',
    lastName: 'Runner',
    email: 'test@example.com',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  int uploadCount = 0;
  Map<String, String>? uploadedHeaders;
  List<int>? uploadedBytes;
  int? maxRetries;
  Object? error;

  @override
  Future<http.Response> put(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 0,
  }) async {
    uploadCount += 1;
    uploadedHeaders = headers;
    uploadedBytes = body as List<int>?;
    this.maxRetries = maxRetries;
    if (error != null) {
      throw error!;
    }
    return http.Response('', 204);
  }
}

class _FakeRemoteHttpClient extends AppHttpClient {
  Object? requestBody;
  Map<String, String>? requestHeaders;
  int? requestMaxRetries;
  String? lastGetUrl;

  @override
  Future<http.Response> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 0,
  }) async {
    requestBody = body;
    requestHeaders = headers;
    requestMaxRetries = maxRetries;
    return http.Response(
      jsonEncode({
        'uploadUrl': 'https://uploads.example.test/',
        'uploadMethod': 'PUT',
        'key': 'avatars/7/issued.jpg',
        'requiredHeaders': {
          'Content-Type': 'image/jpeg',
          'Content-Length': '321',
        },
      }),
      200,
    );
  }

  @override
  Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    int maxRetries = 2,
  }) async {
    lastGetUrl = url;
    requestHeaders = headers;
    return http.Response(
      jsonEncode({
        'key': 'avatars/7/issued.jpg',
        'url': 'https://signed.example.test/avatar.jpg?token=1',
        'urlExpiresAt': '2026-07-27T12:00:00.000Z',
      }),
      200,
    );
  }
}
