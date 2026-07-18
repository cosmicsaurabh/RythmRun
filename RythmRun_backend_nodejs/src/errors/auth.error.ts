export type AuthErrorCode =
  | 'AUTH_ACCESS_INVALID'
  | 'AUTH_EMAIL_UNVERIFIED_CONFLICT'
  | 'AUTH_GOOGLE_ACCOUNT_CONFLICT'
  | 'AUTH_GOOGLE_INVALID'
  | 'AUTH_GOOGLE_UNAVAILABLE'
  | 'AUTH_INVALID_CREDENTIALS'
  | 'AUTH_PASSWORD_UNAVAILABLE'
  | 'AUTH_PASSWORD_INVALID'
  | 'AUTH_REFRESH_INVALID'
  | 'AUTH_USERNAME_TAKEN'
  | 'AUTH_USER_NOT_FOUND'
  | 'AUTH_VERIFICATION_RATE_LIMITED'
  | 'AUTH_VERIFICATION_TOKEN_INVALID';

export class AuthApplicationError extends Error {
  constructor(
    readonly code: AuthErrorCode,
    readonly statusCode: number,
    message: string,
    readonly retryable = false,
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

export function invalidGoogleTokenError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_GOOGLE_INVALID',
    401,
    'Google identity token is invalid',
  );
}

export function googleAuthUnavailableError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_GOOGLE_UNAVAILABLE',
    503,
    'Google authentication is temporarily unavailable',
    true,
  );
}

export function googleAccountConflictError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_GOOGLE_ACCOUNT_CONFLICT',
    409,
    'An account already exists for this email',
  );
}

export function passwordUnavailableError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_PASSWORD_UNAVAILABLE',
    409,
    'Password changes are unavailable for this account',
  );
}

export function invalidRefreshError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_REFRESH_INVALID',
    401,
    'Refresh session is invalid',
  );
}

/**
 * Raised when a Google sign-in matches an existing local account whose email
 * has NOT been verified. Distinct from AUTH_GOOGLE_ACCOUNT_CONFLICT so the
 * client can tell the user to sign in with their password and verify first,
 * rather than a generic "account exists". Auto-linking an unverified account
 * would enable account pre-hijacking, so this stays a hard conflict.
 */
export function emailUnverifiedConflictError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_EMAIL_UNVERIFIED_CONFLICT',
    409,
    'An unverified account already exists for this email. Sign in with your password and verify your email first.',
  );
}

/**
 * Single opaque error for every verification-token failure (unknown,
 * malformed, expired, or already consumed). Collapsing them mirrors
 * invalidCredentialsError so the endpoint never becomes a token-state oracle.
 */
export function invalidVerificationTokenError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_VERIFICATION_TOKEN_INVALID',
    410,
    'This verification link is invalid or has expired',
  );
}

export function verificationRateLimitedError(): AuthApplicationError {
  return new AuthApplicationError(
    'AUTH_VERIFICATION_RATE_LIMITED',
    429,
    'Please wait before requesting another verification email',
    true,
  );
}
