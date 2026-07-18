import 'reflect-metadata';
import { jest } from '@jest/globals';

import { UserController } from '../controllers/user.controller.js';
import {
  invalidVerificationTokenError,
  verificationRateLimitedError,
} from '../errors/auth.error.js';

interface FakeResponse {
  statusCode: number;
  headers: Record<string, string>;
  body?: unknown;
  setHeader: jest.Mock;
  status: jest.Mock;
  type: jest.Mock;
  send: jest.Mock;
  json: jest.Mock;
}

function fakeResponse(): FakeResponse {
  const res = {
    statusCode: 200,
    headers: {} as Record<string, string>,
  } as FakeResponse;
  res.setHeader = jest.fn((key: string, value: string) => {
    res.headers[key] = value;
  });
  res.status = jest.fn((code: number) => {
    res.statusCode = code;
    return res;
  });
  res.type = jest.fn(() => res);
  res.send = jest.fn((body: unknown) => {
    res.body = body;
    return res;
  });
  res.json = jest.fn((body: unknown) => {
    res.body = body;
    return res;
  });
  return res;
}

describe('UserController email verification', () => {
  it('renders the success page with hardened headers on a valid token', async () => {
    const userService = {
      verifyEmail: jest.fn<() => Promise<string>>().mockResolvedValue('verified'),
    };
    const controller = new UserController(userService as never);
    const res = fakeResponse();

    await controller.verifyEmail({ query: { token: 'raw' } } as never, res as never);

    expect(userService.verifyEmail).toHaveBeenCalledWith('raw');
    expect(res.statusCode).toBe(200);
    expect(res.headers['Referrer-Policy']).toBe('no-referrer');
    expect(res.headers['Content-Security-Policy']).toContain("default-src 'none'");
    expect(String(res.body)).toContain('email address is confirmed');
  });

  it('renders the already-verified page for a re-clicked link', async () => {
    const userService = {
      verifyEmail: jest
        .fn<() => Promise<string>>()
        .mockResolvedValue('already_verified'),
    };
    const controller = new UserController(userService as never);
    const res = fakeResponse();

    await controller.verifyEmail({ query: {} } as never, res as never);

    expect(userService.verifyEmail).toHaveBeenCalledWith('');
    expect(res.statusCode).toBe(200);
    expect(String(res.body)).toContain('already confirmed');
  });

  it('renders the error page and mirrors the status for an invalid token', async () => {
    const userService = {
      verifyEmail: jest
        .fn<() => Promise<string>>()
        .mockRejectedValue(invalidVerificationTokenError()),
    };
    const controller = new UserController(userService as never);
    const res = fakeResponse();

    await controller.verifyEmail({ query: { token: 'x' } } as never, res as never);

    expect(res.statusCode).toBe(410);
    expect(res.headers['Referrer-Policy']).toBe('no-referrer');
    expect(String(res.body)).toContain('invalid or has expired');
  });

  it('acknowledges a resend generically for the authenticated user', async () => {
    const userService = {
      resendVerification: jest
        .fn<() => Promise<void>>()
        .mockResolvedValue(undefined),
    };
    const controller = new UserController(userService as never);
    const res = fakeResponse();

    await controller.resendVerification(
      { user: { id: 7 } } as never,
      res as never,
    );

    expect(userService.resendVerification).toHaveBeenCalledWith(7);
    expect(res.statusCode).toBe(200);
  });

  it('maps a resend rate-limit to a 429 response', async () => {
    const userService = {
      resendVerification: jest
        .fn<() => Promise<void>>()
        .mockRejectedValue(verificationRateLimitedError()),
    };
    const controller = new UserController(userService as never);
    const res = fakeResponse();

    await controller.resendVerification(
      { user: { id: 7 } } as never,
      res as never,
    );

    expect(res.statusCode).toBe(429);
    expect((res.body as { error: string }).error).toBe(
      'AUTH_VERIFICATION_RATE_LIMITED',
    );
  });
});
