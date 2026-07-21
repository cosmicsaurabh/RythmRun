/// API endpoints configuration
class ApiEndpoints {
  // User endpoints
  static const String login = '/users/login';
  static const String googleAuth = '/users/auth/google';
  static const String register = '/users/register';
  static const String logout = '/users/logout';
  static const String refreshToken = '/users/refresh-token';
  static const String me = '/users/me';
  static const String profile = '/users/profile';
  static const String changePassword = '/users/change-password';
  static const String resendVerification = '/users/verify-email/resend';
  static const String passwordResetRequest = '/users/password-reset/request';

  // Activity endpoints
  static const String activities = '/activities';
}
