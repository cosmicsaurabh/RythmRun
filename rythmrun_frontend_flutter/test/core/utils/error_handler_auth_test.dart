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
}
