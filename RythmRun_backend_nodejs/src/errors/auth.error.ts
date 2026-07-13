export type AuthErrorCode =
  | 'AUTH_ACCESS_INVALID'
  | 'AUTH_INVALID_CREDENTIALS'
  | 'AUTH_PASSWORD_INVALID'
  | 'AUTH_REFRESH_INVALID'
  | 'AUTH_USERNAME_TAKEN'
  | 'AUTH_USER_NOT_FOUND';

export class AuthApplicationError extends Error {
  readonly retryable = false;

  constructor(
    readonly code: AuthErrorCode,
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = 'AuthApplicationError';
    Object.setPrototypeOf(this, AuthApplicationError.prototype);
  }
}

export function invalidAccessError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_ACCESS_INVALID',
    401,
    'Authentication is required',
  );
}

export function invalidCredentialsError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_INVALID_CREDENTIALS',
    401,
    'Invalid username or password',
  );
}

export function invalidRefreshError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_REFRESH_INVALID',
    401,
    'Refresh session is invalid',
  );
}
