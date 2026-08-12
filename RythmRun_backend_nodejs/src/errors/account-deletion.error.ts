export type AccountDeletionErrorCode =
  | 'ACCOUNT_DELETION_REAUTH_REQUIRED'
  | 'ACCOUNT_DELETION_PASSWORD_INVALID'
  | 'ACCOUNT_DELETION_GOOGLE_INVALID';

export class AccountDeletionServiceError extends Error {
  constructor(
    readonly code: AccountDeletionErrorCode,
    readonly statusCode: number,
    message: string,
    readonly retryable = false,
  ) {
    super(message);
    this.name = 'AccountDeletionServiceError';
    Object.setPrototypeOf(this, AccountDeletionServiceError.prototype);
  }
}

export function accountDeletionReauthRequiredError(): AccountDeletionServiceError {
  return new AccountDeletionServiceError(
    'ACCOUNT_DELETION_REAUTH_REQUIRED',
    400,
    'Re-authentication password or Google ID token is required',
  );
}

export function accountDeletionPasswordInvalidError(): AccountDeletionServiceError {
  return new AccountDeletionServiceError(
    'ACCOUNT_DELETION_PASSWORD_INVALID',
    401,
    'Invalid current password',
  );
}

export function accountDeletionGoogleInvalidError(): AccountDeletionServiceError {
  return new AccountDeletionServiceError(
    'ACCOUNT_DELETION_GOOGLE_INVALID',
    401,
    'Google re-authentication token could not be verified',
  );
}
