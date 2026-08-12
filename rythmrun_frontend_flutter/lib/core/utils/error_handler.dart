import 'dart:io';
import 'package:http/http.dart' as http;
import '../network/auth_failures.dart';
import '../network/http_client.dart';
import '../config/app_config.dart';

class ErrorHandler {
  /// Converts any exception to a user-friendly error message
  static String getErrorMessage(dynamic exception) {
    // Typed session failures from the auth coordinator already carry a curated,
    // user-facing message keyed by their reason — surface it directly.
    if (exception is AuthSessionFailure) {
      return exception.message;
    }

    String message = _readableMessage(exception);

    if (exception is HttpStatusException) {
      switch (exception.code) {
        case 'AUTH_INVALID_CREDENTIALS':
          return 'Incorrect email or password. Please try again.';
        case 'AUTH_GOOGLE_INVALID':
          return 'Google sign-in could not be verified. Please choose your account and try again.';
        case 'AUTH_GOOGLE_ACCOUNT_CONFLICT':
          return 'A RythmRun account already exists for this email. Sign in with its original method.';
        case 'AUTH_EMAIL_UNVERIFIED_CONFLICT':
          return 'An account already exists for this email. Sign in with your password and verify your email, then Google sign-in will link automatically.';
        case 'AUTH_VERIFICATION_TOKEN_INVALID':
          return 'This verification link is invalid or has expired. Request a new one.';
        case 'AUTH_VERIFICATION_RATE_LIMITED':
          return 'Please wait a moment before requesting another verification email.';
        case 'AUTH_RATE_LIMITED':
          // IP-2.6 abuse controls. Without this arm a 429 falls through to the
          // generic path and surfaces the raw 'HttpStatusException(429): ...'
          // string, because 429 has no dedicated exception type.
          return 'Too many attempts. Please wait a few minutes and try again.';
        case 'ACTIVITY_IMAGE_CONTENT_TYPE_UNSUPPORTED':
          return 'Unsupported image format. Please select a JPEG, PNG, or WebP image.';
        case 'ACTIVITY_IMAGE_TOO_LARGE':
          return 'Image file is too large. Maximum size is 10 MB.';
        case 'ACTIVITY_IMAGE_SIZE_MISMATCH':
          return 'Uploaded image size did not match expected size. Please try again.';
        case 'ACTIVITY_IMAGE_CHECKSUM_INVALID':
          return 'Uploaded image corrupted in transit. Please try again.';
        case 'ACTIVITY_IMAGE_ACTIVITY_LIMIT_EXCEEDED':
          return 'Maximum number of images per activity reached (10 images max).';
        case 'ACTIVITY_IMAGE_USER_QUOTA_EXCEEDED':
          return 'Activity image storage quota exceeded.';
        case 'ACTIVITY_IMAGE_TOO_MANY_PENDING':
          return 'Too many pending image uploads. Please wait a moment and try again.';
        case 'ACCOUNT_DELETION_REAUTH_REQUIRED':
          return 'Re-authentication is required to delete your account.';
        case 'ACCOUNT_DELETION_PASSWORD_INVALID':
          return 'Incorrect password. Account deletion cancelled.';
        case 'ACCOUNT_DELETION_GOOGLE_INVALID':
          return 'Google authentication could not be verified. Account deletion cancelled.';
        case 'AUTH_USERNAME_TAKEN':
          return 'This email is already registered. Please sign in instead.';
        case 'AUTH_PASSWORD_INVALID':
          return 'Incorrect current password. Please try again.';
        case 'AUTH_PASSWORD_UNAVAILABLE':
          return 'This account uses Google sign-in and has no password to change.';
        case 'AUTH_USER_NOT_FOUND':
          // Thrown from the same change-password/delete/profile flows as the
          // arms above (e.g. the account was removed under a still-valid access
          // token); a generic 404 "resource not found" reads as a bug there.
          return 'Your account could not be found. Please sign in again.';
      }
    }

    // Handle custom HTTP client exceptions first
    if (exception is UnauthorizedException) {
      // If it's a specific login error message, show that
      if (message.contains('Invalid username or password') ||
          message.contains('Invalid credentials') ||
          message.contains('Login failed')) {
        return message;
      }
      // Otherwise show generic auth message
      return 'Please log in to continue.';
    }

    if (exception is ForbiddenException) {
      return 'You don\'t have permission to perform this action.';
    }

    if (exception is NotFoundException) {
      return 'The requested resource was not found.';
    }

    if (exception is ServerException) {
      return 'Server error occurred. Please try again later.';
    }

    if (exception is NetworkException) {
      if (AppConfig.isDebug) {
        final baseUrl = AppConfig.baseUrl;
        return 'Network error connecting to dev server at $baseUrl. Please check your connection and ensure the server is running.';
      }
      return 'Network error occurred. Please check your connection and try again.';
    }

    // Handle network connectivity errors
    if (exception is SocketException ||
        exception is http.ClientException ||
        message.contains('SocketException') ||
        message.contains('ClientException') ||
        message.contains('Connection refused') ||
        message.contains('Connection timed out') ||
        message.contains('Network is unreachable')) {
      // Provide more helpful messages in debug mode
      if (AppConfig.isDebug) {
        final baseUrl = AppConfig.baseUrl;
        if (message.contains('Connection refused')) {
          return 'Unable to connect to dev server at $baseUrl. Please ensure the server is running and accessible.';
        } else if (message.contains('Connection timed out')) {
          return 'Connection to dev server at $baseUrl timed out. Please check your network connection.';
        } else {
          return 'Unable to connect to dev server at $baseUrl. Please check your network connection and ensure the server is running.';
        }
      }
      // Production message
      return 'Unable to connect to server. Please check your internet connection and try again.';
    }

    // Handle timeout errors
    if (message.contains('TimeoutException') || message.contains('timeout')) {
      if (AppConfig.isDebug) {
        final baseUrl = AppConfig.baseUrl;
        return 'Connection to dev server at $baseUrl timed out. Please check your network connection.';
      }
      return 'Connection timeout. Please check your internet connection and try again.';
    }

    // Unmapped errors degrade to the readable message. Backend errors now carry
    // a stable `code` handled by the switch above; the old string-matching arms
    // (and the `Validation failed:` JSON parser) are gone.
    return message;
  }

  /// The human-readable text carried by an exception.
  ///
  /// Our own exception types expose the server's message directly, so use it.
  /// Deriving it from `toString()` instead used to weld the class name onto
  /// the text: `toString()` is `'UnauthorizedException: <msg>'`, and stripping
  /// `'Exception: '` cut that literal out of the *middle*, so a failed login
  /// reached the user as `'UnauthorizedInvalid username or password'`.
  ///
  /// The switch has no `default` arm on purpose — falling through to the
  /// type-based branches is what produces the right generic message per status
  /// — so an unmapped code has to degrade safely. It now degrades to clean
  /// text rather than a mangled class name, meaning a new backend error code
  /// cannot silently reintroduce that defect.
  static String _readableMessage(dynamic exception) {
    if (exception is HttpStatusException) {
      return exception.message;
    }
    if (exception is NetworkException) {
      return exception.message;
    }
    // Foreign exceptions (SocketException, TimeoutException, ...) have no
    // message field; the checks further down deliberately match on their
    // `toString()` text, so keep the existing derivation for them.
    return exception.toString().replaceAll('Exception: ', '');
  }
}
