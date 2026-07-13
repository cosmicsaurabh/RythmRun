import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { NextFunction, Request, Response } from 'express';

import { invalidAccessError } from '../errors/auth.error.js';
import { createAuthMiddleware } from '../middleware/auth.middleware.js';

function responseHarness() {
  const json = jest.fn();
  const status = jest.fn(() => ({ json }));
  return {
    response: { status } as unknown as Response,
    status,
    json,
  };
}

async function invoke(
  authorization: string | undefined,
  authenticateAccessToken: jest.Mock<(...args: [string]) => Promise<never>>,
) {
  const request = {
    headers: authorization === undefined ? {} : { authorization },
  } as Request;
  const response = responseHarness();
  const next = jest.fn() as unknown as NextFunction;
  const middleware = createAuthMiddleware({ authenticateAccessToken });

  await middleware(request, response.response, next);
  return { request, next, ...response };
}

describe('access authentication middleware', () => {
  it('sets the complete authenticated principal after session verification', async () => {
    const authenticateAccessToken = jest.fn(async () => ({
      userId: 7,
      sessionId: '6f5bc6c5-333b-4baf-9db4-c4d867e40532',
      tokenId: '2bad15f7-39c0-4ee1-a3db-4b3117cb6547',
    })) as unknown as jest.Mock<(...args: [string]) => Promise<never>>;

    const result = await invoke('Bearer access-token', authenticateAccessToken);

    expect(authenticateAccessToken).toHaveBeenCalledWith('access-token');
    expect(result.request.user).toEqual({
      id: 7,
      sessionId: '6f5bc6c5-333b-4baf-9db4-c4d867e40532',
      tokenId: '2bad15f7-39c0-4ee1-a3db-4b3117cb6547',
    });
    expect(result.next).toHaveBeenCalledTimes(1);
    expect(result.status).not.toHaveBeenCalled();
  });

  it.each([
    undefined,
    '',
    'Basic abc',
    'Bearer',
    'Bearer ',
    'Bearer one two',
    'bearer token',
  ])('returns the same safe error for malformed header %p', async (header) => {
    const authenticateAccessToken = jest.fn() as unknown as jest.Mock<
      (...args: [string]) => Promise<never>
    >;

    const result = await invoke(header, authenticateAccessToken);

    expect(authenticateAccessToken).not.toHaveBeenCalled();
    expect(result.next).not.toHaveBeenCalled();
    expect(result.status).toHaveBeenCalledWith(401);
    expect(result.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'AUTH_ACCESS_INVALID',
        message: 'Authentication is required',
        statusCode: 401,
      }),
    );
  });

  it('maps signature, claim, expiry, and revoked-session failures identically', async () => {
    const authenticateAccessToken = jest.fn(async () => {
      throw invalidAccessError();
    }) as unknown as jest.Mock<(...args: [string]) => Promise<never>>;

    const result = await invoke('Bearer rejected-token', authenticateAccessToken);

    expect(result.next).not.toHaveBeenCalled();
    expect(result.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'AUTH_ACCESS_INVALID',
        message: 'Authentication is required',
        statusCode: 401,
      }),
    );
  });

  it('keeps a database outage retryable instead of invalidating credentials', async () => {
    const sensitiveMessage = 'postgresql://credentials@internal.example/db';
    const databaseError = new Error(sensitiveMessage);
    databaseError.name = 'DatabaseUnavailableError';
    const authenticateAccessToken = jest.fn(async () => {
      throw databaseError;
    }) as unknown as jest.Mock<(...args: [string]) => Promise<never>>;
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    const result = await invoke('Bearer temporarily-unverifiable', authenticateAccessToken);

    expect(result.next).not.toHaveBeenCalled();
    expect(result.status).toHaveBeenCalledWith(503);
    expect(result.json).toHaveBeenCalledWith(
      expect.objectContaining({
        error: 'AUTH_SERVICE_UNAVAILABLE',
        message: 'Authentication service is temporarily unavailable',
        statusCode: 503,
        retryable: true,
      }),
    );
    expect(console.error).toHaveBeenCalledWith(
      'Access session verification failed (DatabaseUnavailableError)',
    );
    expect(JSON.stringify(result.json.mock.calls)).not.toContain(
      sensitiveMessage,
    );
  });
});
