import {
  gaxios,
  OAuth2Client,
  type TokenPayload,
} from 'google-auth-library';

import {
  AuthApplicationError,
  googleAuthUnavailableError,
  invalidGoogleTokenError,
} from '../errors/auth.error.js';

const MAXIMUM_EMAIL_LENGTH = 255;
const MAXIMUM_PROVIDER_SUBJECT_LENGTH = 255;
const MAXIMUM_PROFILE_NAME_LENGTH = 50;
const CERTIFICATE_RETRIEVAL_ERROR_PREFIX =
  'Failed to retrieve verification certificates:';

interface GoogleLoginTicket {
  getPayload(): TokenPayload | undefined;
}

interface GoogleIdTokenClient {
  verifyIdToken(options: {
    idToken: string;
    audience: string;
  }): Promise<GoogleLoginTicket>;
}

export interface GoogleIdentity {
  subject: string;
  email: string;
  firstname?: string;
  lastname?: string;
}

export interface GoogleIdentityVerifier {
  verifyIdToken(idToken: string): Promise<GoogleIdentity>;
}

function optionalProfileName(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  if (!normalized) {
    return undefined;
  }
  return normalized.slice(0, MAXIMUM_PROFILE_NAME_LENGTH);
}

function isGoogleVerificationUnavailable(error: unknown): boolean {
  return (
    error instanceof gaxios.GaxiosError ||
    (error instanceof Error &&
      error.message.startsWith(CERTIFICATE_RETRIEVAL_ERROR_PREFIX))
  );
}

/**
 * Verifies Google ID tokens using Google's signing keys and enforces the
 * backend OAuth client as the token audience. Only claims from the verified
 * ticket are returned to the account service.
 */
export class GoogleAuthService implements GoogleIdentityVerifier {
  constructor(
    private readonly clientId: string,
    private readonly client: GoogleIdTokenClient = new OAuth2Client(),
  ) {}

  async verifyIdToken(idToken: string): Promise<GoogleIdentity> {
    try {
      const ticket = await this.client.verifyIdToken({
        idToken,
        audience: this.clientId,
      });
      const payload = ticket.getPayload();
      const email = payload?.email?.trim().toLowerCase();

      if (
        payload === undefined ||
        typeof payload.sub !== 'string' ||
        payload.sub.length === 0 ||
        payload.sub.length > MAXIMUM_PROVIDER_SUBJECT_LENGTH ||
        payload.email_verified !== true ||
        email === undefined ||
        email.length === 0 ||
        email.length > MAXIMUM_EMAIL_LENGTH
      ) {
        throw invalidGoogleTokenError();
      }

      return {
        subject: payload.sub,
        email,
        firstname: optionalProfileName(payload.given_name),
        lastname: optionalProfileName(payload.family_name),
      };
    } catch (error: unknown) {
      if (
        error instanceof AuthApplicationError &&
        error.code === 'AUTH_GOOGLE_INVALID'
      ) {
        throw error;
      }
      if (isGoogleVerificationUnavailable(error)) {
        throw googleAuthUnavailableError();
      }
      throw invalidGoogleTokenError();
    }
  }
}
