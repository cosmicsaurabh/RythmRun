import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../network/http_client.dart';
import '../config/app_config.dart';

class ErrorHandler {
  /// Converts any exception to a user-friendly error message
  static String getErrorMessage(dynamic exception) {
    String message = exception.toString().replaceAll('Exception: ', '');

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

    // Handle backend validation errors
    if (message.contains('Validation failed:')) {
      return _parseValidationError(message);
    }

    // Handle authentication errors
    if (message.contains('UnauthorizedException') ||
        message.contains('Authentication required')) {
      return 'Please log in to continue.';
    }

    if (message.contains('Invalid credentials') ||
        message.contains('Invalid username or password')) {
      return 'Invalid email or password. Please try again.';
    }

    // Handle other specific errors
    if (message.contains('Username already exists')) {
      return 'This email is already registered';
    } else if (message.contains('User not found')) {
      return 'User not found';
    } else if (message.contains('Registration failed')) {
      return message;
    } else if (message.contains('Login failed')) {
      return 'Login failed. Please try again.';
    } else {
      return message;
    }
  }

  static String _parseValidationError(String errorMessage) {
    try {
      // Extract JSON part from the message
      final jsonStart = errorMessage.indexOf('[');
      final jsonEnd = errorMessage.lastIndexOf(']') + 1;

      if (jsonStart == -1 || jsonEnd == 0) {
        return 'Please check your input and try again';
      }

      final jsonString = errorMessage.substring(jsonStart, jsonEnd);
      final List<dynamic> validationErrors = json.decode(jsonString);

      final errorMessages = <Map<String, dynamic>>[];

      for (final error in validationErrors) {
        if (error is Map<String, dynamic>) {
          final property = error['property'] as String?;
          final constraints = error['constraints'] as Map<String, dynamic>?;

          if (constraints != null) {
            for (final constraint in constraints.values) {
              final message = _friendlyValidationMessage(
                property,
                constraint.toString(),
              );
              final priority = _getErrorPriority(
                property,
                constraint.toString(),
              );
              errorMessages.add({'message': message, 'priority': priority});
            }
          }
        }
      }

      // Sort by priority (lower number = higher priority)
      errorMessages.sort((a, b) => a['priority'].compareTo(b['priority']));
      final sortedMessages =
          errorMessages.map((e) => e['message'] as String).toList();

      if (sortedMessages.isEmpty) {
        return 'Please check your input and try again';
      } else if (sortedMessages.length == 1) {
        return sortedMessages.first;
      } else {
        // Multiple errors - show up to 3 most important ones
        final limitedErrors = sortedMessages.take(3).toList();
        return '• ${limitedErrors.join('\n• ')}';
      }
    } catch (e) {
      return 'Please check your input and try again';
    }
  }

  static String _friendlyValidationMessage(
    String? property,
    String constraint,
  ) {
    // Convert backend validation messages to user-friendly ones
    switch (property) {
      case 'password':
        if (constraint.contains('longer than or equal to 8')) {
          return 'Password must be at least 8 characters long';
        } else if (constraint.contains('must contain')) {
          return 'Password must contain uppercase, lowercase, number and special character';
        }
        return 'Password requirements not met';

      case 'username':
        if (constraint.contains('must be an email')) {
          return 'Please enter a valid email address';
        } else if (constraint.contains('should not be empty')) {
          return 'Email is required';
        }
        return 'Please enter a valid email';

      case 'firstname':
        return 'First name is required';

      case 'lastname':
        return 'Last name is required';

      default:
        return constraint;
    }
  }

  static int _getErrorPriority(String? property, String constraint) {
    // Lower number = higher priority (shows first)

    // Required field errors are most critical
    if (constraint.contains('should not be empty') ||
        constraint.contains('is required')) {
      return 1;
    }

    // Format validation errors by field importance
    switch (property) {
      case 'username': // Email field
        return 2;
      case 'password':
        return 3;
      case 'firstname':
      case 'lastname':
        return 4;
      default:
        return 5;
    }
  }
}
