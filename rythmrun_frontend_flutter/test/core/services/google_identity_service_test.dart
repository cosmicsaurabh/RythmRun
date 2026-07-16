import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rythmrun_frontend_flutter/core/services/google_identity_service.dart';

void main() {
  test(
    'a queued authenticate waits for an unawaited sign-out to finish',
    () async {
      final releaseLogout = Completer<void>();
      final client = _FakeGoogleSignInClient(
        firstSignOutCompleter: releaseLogout,
        idToken: 'google-id-token',
      );
      final service = NativeGoogleIdentityService(
        client: client,
        serverClientId: 'server-client-id',
      );

      final logout = service.signOut();
      await _flushAsyncWork();
      expect(client.signOutCalls, 1);

      final authentication = service.authenticate();
      await _flushAsyncWork();
      expect(client.signOutCalls, 1);
      expect(client.authenticateCalls, 0);

      releaseLogout.complete();
      await logout;
      expect(await authentication, 'google-id-token');

      expect(client.initializeCalls, 1);
      expect(client.signOutCalls, 2);
      expect(client.authenticateCalls, 1);
      expect(client.events, <String>[
        'initialize',
        'signOut:1:start',
        'signOut:1:end',
        'signOut:2:start',
        'signOut:2:end',
        'authenticate',
      ]);
    },
  );

  test(
    'an operation failure does not poison the serialization queue',
    () async {
      final client = _FakeGoogleSignInClient(
        firstSignOutError: StateError('native sign-out failed'),
        idToken: 'google-id-token',
      );
      final service = NativeGoogleIdentityService(
        client: client,
        serverClientId: 'server-client-id',
      );

      await expectLater(service.signOut(), throwsStateError);

      expect(await service.authenticate(), 'google-id-token');
      expect(client.initializeCalls, 1);
      expect(client.authenticateCalls, 1);
    },
  );

  test(
    'iOS-style configuration fails closed before native initialization',
    () async {
      final client = _FakeGoogleSignInClient(idToken: 'google-id-token');
      final service = NativeGoogleIdentityService(
        client: client,
        serverClientId: 'server-client-id',
        clientIdRequired: true,
      );

      await expectLater(
        service.authenticate(),
        throwsA(
          isA<GoogleIdentityException>().having(
            (error) => error.message,
            'message',
            contains('platform'),
          ),
        ),
      );
      expect(client.initializeCalls, 0);
    },
  );

  test('maps native cancellation to a null token', () async {
    final client = _FakeGoogleSignInClient(
      authenticationError: const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      ),
    );
    final service = NativeGoogleIdentityService(
      client: client,
      serverClientId: 'server-client-id',
    );

    expect(await service.authenticate(), isNull);
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeGoogleSignInClient implements GoogleSignInClient {
  _FakeGoogleSignInClient({
    this.idToken,
    this.firstSignOutCompleter,
    this.firstSignOutError,
    this.authenticationError,
  });

  final String? idToken;
  final Completer<void>? firstSignOutCompleter;
  final Object? firstSignOutError;
  final Object? authenticationError;
  final List<String> events = <String>[];
  int initializeCalls = 0;
  int signOutCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<void> initialize({String? clientId, String? serverClientId}) async {
    initializeCalls += 1;
    events.add('initialize');
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<String?> authenticateIdToken() async {
    authenticateCalls += 1;
    events.add('authenticate');
    final error = authenticationError;
    if (error != null) throw error;
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    final call = signOutCalls;
    events.add('signOut:$call:start');
    if (call == 1) {
      final error = firstSignOutError;
      if (error != null) throw error;
      await firstSignOutCompleter?.future;
    }
    events.add('signOut:$call:end');
  }
}
