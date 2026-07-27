import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/network/http_client.dart';
import 'package:rythmrun_frontend_flutter/core/utils/error_handler.dart';

void main() {
  test('maps an invalid Google token to a useful retry message', () {
    final message = ErrorHandler.getErrorMessage(
      UnauthorizedException(
        'Invalid Google ID token',
        code: 'AUTH_GOOGLE_INVALID',
      ),
    );

    expect(message, contains('Google sign-in could not be verified'));
  });

  test('maps Google account conflicts without collapsing to generic 401', () {
    final message = ErrorHandler.getErrorMessage(
      HttpStatusException(
        409,
        'Account conflict',
        code: 'AUTH_GOOGLE_ACCOUNT_CONFLICT',
      ),
    );

    expect(message, contains('already exists for this email'));
    expect(message, contains('original method'));
  });

  test('maps a backend rate limit to a wait-and-retry message', () {
    final message = ErrorHandler.getErrorMessage(
      HttpStatusException(
        429,
        'Too many requests. Please wait and try again.',
        code: 'AUTH_RATE_LIMITED',
        retryable: true,
      ),
    );

    expect(message, contains('Too many attempts'));
    // The raw exception string must never reach the user.
    expect(message, isNot(contains('HttpStatusException')));
    expect(message, isNot(contains('429')));
  });

  test('maps a rate-limited sign-in delivered as a 401-family exception', () {
    final message = ErrorHandler.getErrorMessage(
      UnauthorizedException(
        'Too many requests. Please wait and try again.',
        code: 'AUTH_RATE_LIMITED',
      ),
    );

    expect(message, contains('Too many attempts'));
    expect(message, isNot(contains('Unauthorized')));
  });

  test('maps a rejected sign-in without welding the class name onto it', () {
    // The exact shape http_client builds for a real failed login.
    final message = ErrorHandler.getErrorMessage(
      UnauthorizedException(
        'Invalid username or password',
        code: 'AUTH_INVALID_CREDENTIALS',
      ),
    );

    expect(message, 'Incorrect email or password. Please try again.');
    // The defect this replaces rendered 'UnauthorizedInvalid username or
    // password': stripping 'Exception: ' out of the middle of
    // 'UnauthorizedException: ...' left the class-name prefix glued on.
    expect(message, isNot(contains('Unauthorized')));
    expect(message, isNot(contains('Exception')));
  });

  test('renders an unmapped error code as clean text, not a class name', () {
    // No arm exists for this code, so it falls through to the generic path.
    // That path must still never expose the exception's type or status line.
    final message = ErrorHandler.getErrorMessage(
      const HttpStatusException(
        418,
        'The server refused the request.',
        code: 'SOME_FUTURE_BACKEND_CODE',
      ),
    );

    expect(message, 'The server refused the request.');
    expect(message, isNot(contains('HttpStatusException')));
    expect(message, isNot(contains('418')));
  });

  test('keeps the typed generic messages for unmapped codes', () {
    // Falling through the switch must land on the type-based branch, not on
    // the raw text, for the statuses that have a dedicated message.
    expect(
      ErrorHandler.getErrorMessage(
        ForbiddenException('nope', code: 'SOME_FUTURE_BACKEND_CODE'),
      ),
      "You don't have permission to perform this action.",
    );
    expect(
      ErrorHandler.getErrorMessage(
        NotFoundException('nope', code: 'SOME_FUTURE_BACKEND_CODE'),
      ),
      'The requested resource was not found.',
    );
    expect(
      ErrorHandler.getErrorMessage(
        ServerException('boom', code: 'SOME_FUTURE_BACKEND_CODE'),
      ),
      'Server error occurred. Please try again later.',
    );
  });

  test('still recognises an uncoded credential rejection', () {
    // A 401 carrying the legacy text but no error code must not regress to
    // the generic "Please log in to continue."
    final message = ErrorHandler.getErrorMessage(
      UnauthorizedException('Invalid username or password'),
    );

    expect(message, isNot(contains('Exception')));
    expect(message.toLowerCase(), contains('password'));
  });

  test('keeps the generic auth prompt for an expired session', () {
    final message = ErrorHandler.getErrorMessage(
      UnauthorizedException('Authentication is required'),
    );

    expect(message, 'Please log in to continue.');
  });

  test('leaves foreign exception handling intact', () {
    // SocketException has no message field, so the toString()-based checks
    // below the typed branches must keep working.
    final message = ErrorHandler.getErrorMessage(
      const SocketException('Connection refused'),
    );

    expect(message, isNot(contains('SocketException')));
    expect(message.toLowerCase(), contains('connect'));
  });
}
