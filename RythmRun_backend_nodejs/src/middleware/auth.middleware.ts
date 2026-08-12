import type { RequestHandler } from 'express';

import { container } from '../config/container.js';
import { AuthApplicationError } from '../errors/auth.error.js';
import type {
  AuthSessionService,
  AuthenticatedPrincipal,
} from '../services/auth-session.service.js';

export interface AccessTokenAuthenticator {
  authenticateAccessToken(token: string): Promise<AuthenticatedPrincipal>;
}

function sendInvalidAccess(res: Parameters<RequestHandler>[1]): void {
  res.status(401).json({
    code: 'AUTH_ACCESS_INVALID',
    message: 'Authentication is required',
    statusCode: 401,
    timestamp: new Date().toISOString(),
  });
}

function sendAuthServiceUnavailable(
  res: Parameters<RequestHandler>[1],
): void {
  res.status(503).json({
    code: 'AUTH_SERVICE_UNAVAILABLE',
    message: 'Authentication service is temporarily unavailable',
    statusCode: 503,
    retryable: true,
    timestamp: new Date().toISOString(),
  });
}

export function createAuthMiddleware(
  authenticator: AccessTokenAuthenticator,
): RequestHandler {
  return async (req, res, next) => {
    const authorization = req.headers.authorization;
    const match =
      typeof authorization === 'string'
        ? /^Bearer ([^\s]+)$/.exec(authorization)
        : null;
    if (match === null) {
      sendInvalidAccess(res);
      return;
    }

    let principal: AuthenticatedPrincipal;
    try {
      principal = await authenticator.authenticateAccessToken(match[1]);
    } catch (error: unknown) {
      if (
        error instanceof AuthApplicationError &&
        error.code === 'AUTH_ACCESS_INVALID'
      ) {
        sendInvalidAccess(res);
        return;
      }

      const category = error instanceof Error ? error.name : 'UnknownError';
      console.error(`Access session verification failed (${category})`);
      sendAuthServiceUnavailable(res);
      return;
    }

    req.user = {
      id: principal.userId,
      sessionId: principal.sessionId,
      tokenId: principal.tokenId,
    };
    next();
  };
}

export const authMiddleware = createAuthMiddleware({
  authenticateAccessToken: (token) =>
    container
      .resolve<AuthSessionService>('AuthSessionService')
      .authenticateAccessToken(token),
});
