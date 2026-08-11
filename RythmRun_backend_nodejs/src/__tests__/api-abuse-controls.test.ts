import 'reflect-metadata';
import { jest } from '@jest/globals';

const mockProductionController = {
  register: jest.fn(),
  login: jest.fn(),
  googleAuth: jest.fn(),
  verifyEmail: jest.fn(),
  resendVerification: jest.fn(),
  requestPasswordReset: jest.fn(),
  passwordResetPage: jest.fn(),
  submitPasswordReset: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  me: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
  deleteAccount: jest.fn(),
};

jest.unstable_mockModule('../config/container.js', () => ({
  container: {
    resolve: jest.fn(() => mockProductionController),
  },
}));

// The avatar router pulls in the S3 client transitively; replace it so this
// HTTP test constructs no AWS client.
jest.unstable_mockModule('../services/s3.service.js', () => ({
  S3Service: class S3Service {},
  default: {},
}));

import http, { type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';

import type { ApplicationOptions } from '../app.js';

const { createApp } = await import('../app.js');
const { UserController } = await import('../controllers/user.controller.js');
const { createUserRouter } = await import('../routes/user.routes.js');
const { AUTH_RATE_LIMITS } = await import('../config/rate-limits.js');
const { googleAuthUnavailableError, invalidCredentialsError } = await import(
  '../errors/auth.error.js'
);
const { setSecurityLogSink } = await import('../utils/security-log.js');

const USER_ID = 17;
const AUTHORIZATION = 'Bearer abuse-control-test-token';

interface HttpResponse {
  statusCode: number;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
}

function request(
  server: Server,
  method: string,
  path: string,
  body?: unknown,
  requestHeaders: Record<string, string> = {},
): Promise<HttpResponse> {
  const { port } = server.address() as AddressInfo;
  const payload = body === undefined ? undefined : JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const outbound = http.request(
      {
        host: '127.0.0.1',
        port,
        method,
        path,
        headers: {
          ...requestHeaders,
          ...(payload === undefined
            ? {}
            : {
                'content-type': 'application/json',
                'content-length': Buffer.byteLength(payload),
              }),
        },
      },
      (response) => {
        const chunks: Buffer[] = [];
        response.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
        response.on('error', reject);
        response.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let responseBody: unknown = text;
          if (text && response.headers['content-type']?.includes('json')) {
            responseBody = JSON.parse(text);
          }
          resolve({
            statusCode: response.statusCode ?? 0,
            headers: response.headers,
            body: responseBody,
          });
        });
      },
    );

    outbound.on('error', reject);
    if (payload !== undefined) {
      outbound.write(payload);
    }
    outbound.end();
  });
}

const userService = {
  register: jest.fn(),
  login: jest.fn(),
  googleLogin: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  getMe: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
  requestPasswordReset: jest.fn(),
  resendVerification: jest.fn(),
  deleteAccount: jest.fn(),
};

const authenticate = jest.fn(
  (req: Request, res: Response, next: NextFunction) => {
    if (req.headers.authorization !== AUTHORIZATION) {
      res.status(401).json({ status: 'error', message: 'No token provided' });
      return;
    }
    req.user = { id: USER_ID, sessionId: 'session', tokenId: 'token' };
    next();
  },
);

/**
 * Each server gets a freshly built router, and therefore a fresh limiter
 * store, so one test's spent budget can never leak into another.
 */
async function startTestServer(
  options: ApplicationOptions = {},
): Promise<Server> {
  const app = createApp(
    {
      users: createUserRouter({
        controller: new UserController(userService as never),
        authenticate,
      }),
      friends: Router(),
      avatar: Router(),
      activityImages: Router(),
      activities: Router(),
      comments: Router(),
      likes: Router(),
    },
    options,
  );

  return new Promise<Server>((resolve, reject) => {
    const listener = app.listen(0, '127.0.0.1', (error?: Error) => {
      if (error !== undefined) {
        reject(error);
        return;
      }
      resolve(listener);
    });
    listener.on('error', reject);
  });
}

async function stop(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

describe('IP-2.6 authentication rate limits', () => {
  let restoreSink: (line: string) => void;

  beforeEach(() => {
    jest.clearAllMocks();
    // Keep the security-event stream out of the test output.
    restoreSink = setSecurityLogSink(() => undefined);
  });

  afterEach(() => {
    setSecurityLogSink(restoreSink);
  });

  it('blocks the request after the configured failed-login budget is spent', async () => {
    const server = await startTestServer();
    userService.login.mockRejectedValue(invalidCredentialsError());

    try {
      const attempts: HttpResponse[] = [];
      for (let attempt = 0; attempt < AUTH_RATE_LIMITS.login.limit; attempt += 1) {
        attempts.push(
          await request(server, 'POST', '/api/users/login', {
            username: 'runner@example.com',
            password: 'wrong-password',
          }),
        );
      }

      expect(attempts.map((response) => response.statusCode)).toEqual(
        Array(AUTH_RATE_LIMITS.login.limit).fill(401),
      );

      const blocked = await request(server, 'POST', '/api/users/login', {
        username: 'runner@example.com',
        password: 'wrong-password',
      });

      expect(blocked.statusCode).toBe(429);
      expect(blocked.body).toMatchObject({
        error: 'AUTH_RATE_LIMITED',
        retryable: true,
        statusCode: 429,
      });
      expect(Number(blocked.headers['retry-after'])).toBeGreaterThan(0);
      expect(Number(blocked.headers['retry-after'])).toBeLessThanOrEqual(
        AUTH_RATE_LIMITS.login.windowMs / 1000,
      );
      // The blocked request never reached the service.
      expect(userService.login).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.login.limit,
      );
    } finally {
      await stop(server);
    }
  });

  it('holds the failed-login budget against a concurrent burst', async () => {
    const server = await startTestServer();
    // A realistic login does async work (query + bcrypt) before responding.
    // If the budget were only charged once the response finished, every
    // overlapping request would read an uncharged bucket and be admitted.
    userService.login.mockImplementation(
      () =>
        new Promise((_resolve, reject) => {
          setTimeout(() => reject(invalidCredentialsError()), 25);
        }),
    );

    try {
      const burst = await Promise.all(
        Array.from({ length: 40 }, () =>
          request(server, 'POST', '/api/users/login', {
            username: 'runner@example.com',
            password: 'wrong-password',
          }),
        ),
      );

      const admitted = burst.filter((r) => r.statusCode === 401).length;
      const blocked = burst.filter((r) => r.statusCode === 429).length;

      expect(admitted).toBe(AUTH_RATE_LIMITS.login.limit);
      expect(blocked).toBe(40 - AUTH_RATE_LIMITS.login.limit);
      expect(userService.login).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.login.limit,
      );
    } finally {
      userService.login.mockReset();
      await stop(server);
    }
  });

  it('never reflects the attempted account back in the limit response', async () => {
    const server = await startTestServer();
    userService.login.mockRejectedValue(invalidCredentialsError());

    try {
      for (let attempt = 0; attempt <= AUTH_RATE_LIMITS.login.limit; attempt += 1) {
        await request(server, 'POST', '/api/users/login', {
          username: 'secret-runner@example.com',
          password: 'wrong-password',
        });
      }

      const blocked = await request(server, 'POST', '/api/users/login', {
        username: 'secret-runner@example.com',
        password: 'wrong-password',
      });

      expect(blocked.statusCode).toBe(429);
      expect(JSON.stringify(blocked.body)).not.toContain('secret-runner');
      expect(JSON.stringify(blocked.body)).not.toContain('wrong-password');
    } finally {
      await stop(server);
    }
  });

  it('does not charge a successful sign-in against the failed-login budget', async () => {
    const server = await startTestServer();
    userService.login.mockResolvedValue({ id: USER_ID, accessToken: 'a' });

    try {
      for (let attempt = 0; attempt < AUTH_RATE_LIMITS.login.limit * 3; attempt += 1) {
        const response = await request(server, 'POST', '/api/users/login', {
          username: 'runner@example.com',
          password: 'correct-password',
        });
        expect(response.statusCode).toBe(200);
      }
    } finally {
      await stop(server);
    }
  });

  it('bounds one password sprayed across many accounts from one address', async () => {
    const server = await startTestServer();
    userService.login.mockRejectedValue(invalidCredentialsError());

    try {
      const codes: number[] = [];
      // Every attempt names a different account, so the account+address key is
      // fresh each time and never trips. Only the address ceiling stops this.
      for (let attempt = 0; attempt < 40; attempt += 1) {
        const response = await request(server, 'POST', '/api/users/login', {
          username: `candidate-${attempt}@example.com`,
          password: 'one-sprayed-password',
        });
        codes.push(response.statusCode);
      }

      const admitted = codes.filter((code) => code === 401).length;
      expect(admitted).toBe(AUTH_RATE_LIMITS.loginAddress.limit);
      expect(codes[AUTH_RATE_LIMITS.loginAddress.limit]).toBe(429);
      expect(userService.login).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.loginAddress.limit,
      );
    } finally {
      await stop(server);
    }
  });

  it('does not let the address ceiling drain a bystander account budget', async () => {
    const server = await startTestServer();
    userService.login.mockRejectedValue(invalidCredentialsError());

    try {
      // Spray until the address ceiling is spent.
      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.loginAddress.limit;
        attempt += 1
      ) {
        await request(server, 'POST', '/api/users/login', {
          username: `sprayed-${attempt}@example.com`,
          password: 'one-sprayed-password',
        });
      }

      // A bystander sharing the address is now blocked by the address ceiling.
      // Those blocked attempts must not be charged to their per-account budget,
      // or they would stay locked out after the address window cleared.
      for (let attempt = 0; attempt < 10; attempt += 1) {
        const blocked = await request(server, 'POST', '/api/users/login', {
          username: 'bystander@example.com',
          password: 'their-own-password',
        });
        expect(blocked.statusCode).toBe(429);
      }

      // The bystander's own budget is untouched: the controller was never
      // reached for any of those requests.
      expect(userService.login).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.loginAddress.limit,
      );
    } finally {
      await stop(server);
    }
  });

  it('gives a second account its own budget on the same client address', async () => {
    const server = await startTestServer();
    userService.login.mockRejectedValue(invalidCredentialsError());

    try {
      for (let attempt = 0; attempt <= AUTH_RATE_LIMITS.login.limit; attempt += 1) {
        await request(server, 'POST', '/api/users/login', {
          username: 'first@example.com',
          password: 'wrong-password',
        });
      }

      const otherAccount = await request(server, 'POST', '/api/users/login', {
        username: 'second@example.com',
        password: 'wrong-password',
      });

      expect(otherAccount.statusCode).toBe(401);
    } finally {
      await stop(server);
    }
  });

  it('caps registrations per client address regardless of outcome', async () => {
    const server = await startTestServer();
    userService.register.mockResolvedValue({ id: USER_ID });

    try {
      for (let attempt = 0; attempt < AUTH_RATE_LIMITS.register.limit; attempt += 1) {
        const response = await request(server, 'POST', '/api/users/register', {
          username: `runner-${attempt}@example.com`,
          password: 'long-enough-password',
        });
        expect(response.statusCode).toBe(201);
      }

      const blocked = await request(server, 'POST', '/api/users/register', {
        username: 'runner-overflow@example.com',
        password: 'long-enough-password',
      });

      expect(blocked.statusCode).toBe(429);
      expect(userService.register).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.register.limit,
      );
    } finally {
      await stop(server);
    }
  });

  it('caps recovery requests while keeping the generic anti-enumeration reply', async () => {
    const server = await startTestServer();
    userService.requestPasswordReset.mockResolvedValue(undefined);

    try {
      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.passwordResetRequest.limit;
        attempt += 1
      ) {
        const response = await request(
          server,
          'POST',
          '/api/users/password-reset/request',
          { username: 'runner@example.com' },
        );
        expect(response.statusCode).toBe(200);
        expect(response.body).toMatchObject({
          message:
            'If an account exists for that email, a password reset link has been sent.',
        });
      }

      const blocked = await request(
        server,
        'POST',
        '/api/users/password-reset/request',
        { username: 'runner@example.com' },
      );

      expect(blocked.statusCode).toBe(429);
      expect(userService.requestPasswordReset).toHaveBeenCalledTimes(
        AUTH_RATE_LIMITS.passwordResetRequest.limit,
      );
    } finally {
      await stop(server);
    }
  });

  it('does not spend the Google budget on a provider outage', async () => {
    const server = await startTestServer();
    userService.googleLogin.mockRejectedValue(googleAuthUnavailableError());

    try {
      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.googleExchange.limit * 2;
        attempt += 1
      ) {
        const response = await request(server, 'POST', '/api/users/auth/google', {
          idToken: 'provider-token',
        });
        // A 503 is our dependency failing, not the caller misbehaving.
        expect(response.statusCode).toBe(503);
      }
    } finally {
      await stop(server);
    }
  });

  it('keeps the account-scoped resend budget behind authentication', async () => {
    const server = await startTestServer();
    userService.resendVerification.mockResolvedValue(undefined);

    try {
      const unauthenticated = await request(
        server,
        'POST',
        '/api/users/verify-email/resend',
      );
      expect(unauthenticated.statusCode).toBe(401);

      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.verificationResend.limit;
        attempt += 1
      ) {
        const response = await request(
          server,
          'POST',
          '/api/users/verify-email/resend',
          undefined,
          { authorization: AUTHORIZATION },
        );
        expect(response.statusCode).toBe(200);
      }

      const blocked = await request(
        server,
        'POST',
        '/api/users/verify-email/resend',
        undefined,
        { authorization: AUTHORIZATION },
      );
      expect(blocked.statusCode).toBe(429);
    } finally {
      await stop(server);
    }
  });

  it('caps account-deletion re-auth attempts behind authentication', async () => {
    const server = await startTestServer();
    userService.deleteAccount.mockResolvedValue(undefined);
    const deleteBody = { password: 'correct-horse-battery-staple' };

    try {
      const unauthenticated = await request(
        server,
        'DELETE',
        '/api/users/me',
        deleteBody,
      );
      expect(unauthenticated.statusCode).toBe(401);

      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.accountDeletion.limit;
        attempt += 1
      ) {
        const response = await request(
          server,
          'DELETE',
          '/api/users/me',
          deleteBody,
          { authorization: AUTHORIZATION },
        );
        expect(response.statusCode).toBe(200);
      }

      const blocked = await request(
        server,
        'DELETE',
        '/api/users/me',
        deleteBody,
        { authorization: AUTHORIZATION },
      );
      expect(blocked.statusCode).toBe(429);
      expect(blocked.body).toMatchObject({
        error: 'AUTH_RATE_LIMITED',
        statusCode: 429,
      });
    } finally {
      await stop(server);
    }
  });
});

describe('IP-2.6 forwarded-header trust', () => {
  let restoreSink: (line: string) => void;

  beforeEach(() => {
    jest.clearAllMocks();
    restoreSink = setSecurityLogSink(() => undefined);
    userService.login.mockRejectedValue(invalidCredentialsError());
  });

  afterEach(() => {
    setSecurityLogSink(restoreSink);
  });

  it('ignores a spoofed X-Forwarded-For when no proxy is trusted', async () => {
    const server = await startTestServer({ trustProxyHops: 0 });

    try {
      for (let attempt = 0; attempt <= AUTH_RATE_LIMITS.login.limit; attempt += 1) {
        await request(
          server,
          'POST',
          '/api/users/login',
          { username: 'runner@example.com', password: 'wrong-password' },
          // A different forged address on every attempt.
          { 'x-forwarded-for': `203.0.113.${attempt}` },
        );
      }

      const blocked = await request(
        server,
        'POST',
        '/api/users/login',
        { username: 'runner@example.com', password: 'wrong-password' },
        { 'x-forwarded-for': '203.0.113.250' },
      );

      // Rotating the header bought nothing: the socket address still governs.
      expect(blocked.statusCode).toBe(429);
    } finally {
      await stop(server);
    }
  });

  it('uses the forwarded address when exactly one proxy hop is trusted', async () => {
    const server = await startTestServer({ trustProxyHops: 1 });

    try {
      for (
        let attempt = 0;
        attempt < AUTH_RATE_LIMITS.login.limit;
        attempt += 1
      ) {
        await request(
          server,
          'POST',
          '/api/users/login',
          { username: 'runner@example.com', password: 'wrong-password' },
          { 'x-forwarded-for': '198.51.100.1' },
        );
      }

      const sameClient = await request(
        server,
        'POST',
        '/api/users/login',
        { username: 'runner@example.com', password: 'wrong-password' },
        { 'x-forwarded-for': '198.51.100.1' },
      );
      const differentClient = await request(
        server,
        'POST',
        '/api/users/login',
        { username: 'runner@example.com', password: 'wrong-password' },
        { 'x-forwarded-for': '198.51.100.2' },
      );

      expect(sameClient.statusCode).toBe(429);
      // A genuinely different client behind the same proxy is unaffected.
      expect(differentClient.statusCode).toBe(401);
    } finally {
      await stop(server);
    }
  });
});

describe('IP-2.6 CORS allowlist', () => {
  const ALLOWED = 'https://app.rythmrun.example';
  const DENIED = 'https://attacker.example';

  it('reflects only an allowlisted origin and never a wildcard', async () => {
    const server = await startTestServer({ allowedOrigins: [ALLOWED] });

    try {
      const allowed = await request(server, 'GET', '/health', undefined, {
        origin: ALLOWED,
      });
      const denied = await request(server, 'GET', '/health', undefined, {
        origin: DENIED,
      });

      expect(allowed.headers['access-control-allow-origin']).toBe(ALLOWED);
      expect(denied.headers['access-control-allow-origin']).toBeUndefined();
      expect(allowed.headers['access-control-allow-origin']).not.toBe('*');
    } finally {
      await stop(server);
    }
  });

  it('never grants credentials, so a cookie can never ride a CORS response', async () => {
    const server = await startTestServer({ allowedOrigins: [ALLOWED] });

    try {
      const response = await request(server, 'GET', '/health', undefined, {
        origin: ALLOWED,
      });

      expect(
        response.headers['access-control-allow-credentials'],
      ).toBeUndefined();
    } finally {
      await stop(server);
    }
  });

  it('denies every browser origin when the allowlist is empty', async () => {
    const server = await startTestServer({ allowedOrigins: [] });

    try {
      const response = await request(server, 'GET', '/health', undefined, {
        origin: ALLOWED,
      });

      expect(response.headers['access-control-allow-origin']).toBeUndefined();
      // The request itself still succeeds — CORS constrains the browser, not
      // the server, and non-browser clients send no Origin at all.
      expect(response.statusCode).toBe(200);
    } finally {
      await stop(server);
    }
  });

  it('answers a preflight for an allowlisted origin only', async () => {
    const server = await startTestServer({ allowedOrigins: [ALLOWED] });

    try {
      const allowed = await request(
        server,
        'OPTIONS',
        '/api/users/login',
        undefined,
        {
          origin: ALLOWED,
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'authorization,content-type',
        },
      );
      const denied = await request(
        server,
        'OPTIONS',
        '/api/users/login',
        undefined,
        {
          origin: DENIED,
          'access-control-request-method': 'POST',
        },
      );

      expect(allowed.headers['access-control-allow-origin']).toBe(ALLOWED);
      expect(denied.headers['access-control-allow-origin']).toBeUndefined();
    } finally {
      await stop(server);
    }
  });
});

describe('IP-2.6 request correlation', () => {
  it('mints a unique id per request and ignores a client-supplied one', async () => {
    const server = await startTestServer();

    try {
      const first = await request(server, 'GET', '/health');
      const second = await request(server, 'GET', '/health', undefined, {
        'x-request-id': 'client-chosen-id',
      });

      expect(first.headers['x-request-id']).toEqual(expect.any(String));
      expect(second.headers['x-request-id']).not.toBe('client-chosen-id');
      expect(first.headers['x-request-id']).not.toBe(
        second.headers['x-request-id'],
      );
    } finally {
      await stop(server);
    }
  });
});
