import 'reflect-metadata';
import { jest } from '@jest/globals';

const mockProductionController = {
  register: jest.fn(),
  login: jest.fn(),
  googleAuth: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  me: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
  getUploadUrl: jest.fn(),
  confirmUpload: jest.fn(),
};

jest.unstable_mockModule('../config/container.js', () => ({
  container: {
    resolve: jest.fn(() => mockProductionController),
  },
}));

// AvatarController's typed error dependency imports AvatarService. Replace the
// unrelated S3 module before evaluation so this HTTP test constructs no AWS
// client while still using the real controller and AvatarServiceError class.
jest.unstable_mockModule('../services/s3.service.js', () => ({
  S3Service: class S3Service {},
}));

import http, { type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';
const { createApp } = await import('../app.js');
const { AvatarController } = await import('../controllers/avatar.controller.js');
const { UserController } = await import('../controllers/user.controller.js');
const { createAvatarRouter } = await import('../routes/avatar.routes.js');
const { createUserRouter } = await import('../routes/user.routes.js');
const { googleAuthUnavailableError } = await import('../errors/auth.error.js');
const { AvatarServiceError } = await import('../services/avatar.service.js');

const USER_ID = 17;
const SESSION_ID = '123e4567-e89b-42d3-a456-426614174001';
const TOKEN_ID = '123e4567-e89b-42d3-a456-426614174002';
const AUTHORIZATION = 'Bearer boundary-test-token';
const AVATAR_KEY =
  'avatars/17/123e4567-e89b-42d3-a456-426614174000.jpg';

interface HttpResponse {
  statusCode: number;
  body: unknown;
}

function requestJson(
  server: Server,
  method: string,
  path: string,
  body?: unknown,
  requestHeaders: Record<string, string> = {},
): Promise<HttpResponse> {
  const { port } = server.address() as AddressInfo;
  const payload = body === undefined ? undefined : JSON.stringify(body);

  return new Promise((resolve, reject) => {
    const request = http.request(
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
      response => {
        const chunks: Buffer[] = [];
        response.on('data', chunk => chunks.push(Buffer.from(chunk)));
        response.on('error', reject);
        response.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let responseBody: unknown = text;

          if (text && response.headers['content-type']?.includes('json')) {
            responseBody = JSON.parse(text);
          }

          resolve({
            statusCode: response.statusCode ?? 0,
            body: responseBody,
          });
        });
      },
    );

    request.on('error', reject);
    if (payload !== undefined) {
      request.write(payload);
    }
    request.end();
  });
}

function emptyRouter(): Router {
  return Router();
}

describe('HTTP security boundaries', () => {
  const userService = {
    register: jest.fn(),
    login: jest.fn(),
    googleLogin: jest.fn(),
    logout: jest.fn(),
    refreshToken: jest.fn(),
    getMe: jest.fn(),
    updateProfile: jest.fn(),
    changePassword: jest.fn(),
  };
  const avatarService = {
    requestUpload: jest.fn(),
    confirmUpload: jest.fn(),
  };
  const authenticate = jest.fn(
    (req: Request, res: Response, next: NextFunction) => {
      if (req.headers.authorization !== AUTHORIZATION) {
        res.status(401).json({
          status: 'error',
          message: 'No token provided',
        });
        return;
      }

      req.user = {
        id: USER_ID,
        sessionId: SESSION_ID,
        tokenId: TOKEN_ID,
      };
      next();
    },
  );

  const userController = new UserController(userService as any);
  const avatarController = new AvatarController(avatarService as any);
  const app = createApp({
    users: createUserRouter({
      controller: userController,
      authenticate,
    }),
    avatar: createAvatarRouter({
      controller: avatarController,
      authenticate,
    }),
    friends: emptyRouter(),
    activityImages: emptyRouter(),
    activities: emptyRouter(),
    comments: emptyRouter(),
    likes: emptyRouter(),
  });

  let server!: Server;

  beforeAll(async () => {
    server = await new Promise<Server>((resolve, reject) => {
      const listener = app.listen(0, '127.0.0.1', error => {
        if (error !== undefined) {
          reject(error);
          return;
        }
        resolve(listener);
      });
      listener.on('error', reject);
    });
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterAll(async () => {
    if (!server) {
      return;
    }

    await new Promise<void>((resolve, reject) => {
      server.close(error => (error ? reject(error) : resolve()));
    });
  });

  it('rejects a server-managed registration field before calling UserService', async () => {
    const response = await requestJson(server, 'POST', '/api/users/register', {
      username: 'runner@example.com',
      password: 'long-enough-password',
      profilePicturePath: '/private/owned-by-server',
    });

    expect(response.statusCode).toBe(400);
    expect(response.body).toMatchObject({
      error: 'REGISTRATION_FAILED',
      message: 'Validation failed',
      statusCode: 400,
    });
    expect(userService.register).not.toHaveBeenCalled();
  });

  it('rejects a server-managed profile field before calling UserService', async () => {
    const response = await requestJson(
      server,
      'PUT',
      '/api/users/profile',
      {
        firstname: 'Safe',
        profilePicturePath: '/private/owned-by-server',
      },
      { authorization: AUTHORIZATION },
    );

    expect(response.statusCode).toBe(400);
    expect(response.body).toMatchObject({
      error: 'PROFILE_UPDATE_FAILED',
      message: 'Validation failed',
      statusCode: 400,
    });
    expect(authenticate).toHaveBeenCalledTimes(1);
    expect(userService.updateProfile).not.toHaveBeenCalled();
  });

  it('returns the updated safe user through the protected profile route', async () => {
    const safeUser = {
      id: USER_ID,
      username: 'runner@example.com',
      firstname: 'Renamed',
      lastname: 'Runner',
      profilePicturePath: null,
      profilePictureType: null,
      hasPassword: true,
    };
    userService.updateProfile.mockResolvedValueOnce(safeUser);

    const response = await requestJson(
      server,
      'PUT',
      '/api/users/profile',
      { firstname: 'Renamed', lastname: 'Runner' },
      { authorization: AUTHORIZATION },
    );

    expect(response).toEqual({ statusCode: 200, body: safeUser });
    expect(authenticate).toHaveBeenCalledTimes(1);
    expect(userService.updateProfile).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({ firstname: 'Renamed', lastname: 'Runner' }),
    );
  });

  it('refreshes a token without requiring an access-token session', async () => {
    const authResponse = {
      id: USER_ID,
      username: 'runner@example.com',
      firstname: 'Safe',
      lastname: 'Runner',
      profilePicturePath: null,
      profilePictureType: null,
      hasPassword: true,
      accessToken: 'rotated-access-token',
      refreshToken: 'rotated-refresh-token',
    };
    userService.refreshToken.mockResolvedValueOnce(authResponse);

    const response = await requestJson(
      server,
      'POST',
      '/api/users/refresh-token',
      { refreshToken: 'presented-refresh-token' },
      { authorization: 'Bearer expired-access-token' },
    );

    expect(response).toEqual({ statusCode: 200, body: authResponse });
    expect(authenticate).not.toHaveBeenCalled();
    expect(userService.refreshToken).toHaveBeenCalledWith(
      'presented-refresh-token',
    );
  });

  it('exchanges only a validated Google ID-token payload on the public route', async () => {
    const authResponse = {
      id: USER_ID,
      username: 'runner@example.com',
      firstname: 'Safe',
      lastname: 'Runner',
      profilePicturePath: null,
      profilePictureType: null,
      hasPassword: false,
      accessToken: 'google-access-token',
      refreshToken: 'google-refresh-token',
    };
    userService.googleLogin.mockResolvedValueOnce(authResponse);

    const response = await requestJson(
      server,
      'POST',
      '/api/users/auth/google',
      { idToken: 'verified-by-service-layer' },
    );

    expect(response).toEqual({ statusCode: 200, body: authResponse });
    expect(authenticate).not.toHaveBeenCalled();
    expect(userService.googleLogin).toHaveBeenCalledWith(
      expect.objectContaining({ idToken: 'verified-by-service-layer' }),
    );
  });

  it('returns a safe 503 when Google verification is unavailable', async () => {
    userService.googleLogin.mockRejectedValueOnce(
      googleAuthUnavailableError(),
    );

    const response = await requestJson(
      server,
      'POST',
      '/api/users/auth/google',
      { idToken: 'provider-id-token-must-not-leak' },
    );

    expect(response.statusCode).toBe(503);
    expect(response.body).toMatchObject({
      error: 'AUTH_GOOGLE_UNAVAILABLE',
      message: 'Google authentication is temporarily unavailable',
      retryable: true,
      statusCode: 503,
    });
    expect(JSON.stringify(response.body)).not.toContain(
      'provider-id-token-must-not-leak',
    );
  });

  it('rejects client-supplied Google identity claims before verification', async () => {
    const response = await requestJson(
      server,
      'POST',
      '/api/users/auth/google',
      {
        idToken: 'provider-id-token',
        email: 'attacker-selected@example.com',
        subject: 'attacker-selected-subject',
      },
    );

    expect(response.statusCode).toBe(400);
    expect(response.body).toMatchObject({
      error: 'GOOGLE_AUTH_FAILED',
      message: 'Validation failed',
      statusCode: 400,
    });
    expect(userService.googleLogin).not.toHaveBeenCalled();
  });

  it('returns one safe refresh error for a malformed refresh request', async () => {
    const response = await requestJson(
      server,
      'POST',
      '/api/users/refresh-token',
      {},
    );

    expect(response.statusCode).toBe(401);
    expect(response.body).toMatchObject({
      error: 'AUTH_REFRESH_INVALID',
      message: 'Refresh session is invalid',
      statusCode: 401,
    });
    expect(authenticate).not.toHaveBeenCalled();
    expect(userService.refreshToken).not.toHaveBeenCalled();
  });

  it('returns the safe current-user profile through the protected route', async () => {
    const safeUser = {
      id: USER_ID,
      username: 'runner@example.com',
      firstname: 'Safe',
      lastname: 'Runner',
      profilePicturePath: null,
      profilePictureType: null,
      hasPassword: true,
    };
    userService.getMe.mockResolvedValueOnce(safeUser);

    const response = await requestJson(
      server,
      'GET',
      '/api/users/me',
      undefined,
      { authorization: AUTHORIZATION },
    );

    expect(response).toEqual({ statusCode: 200, body: safeUser });
    expect(authenticate).toHaveBeenCalledTimes(1);
    expect(userService.getMe).toHaveBeenCalledWith(USER_ID);
  });

  it('rejects an unauthenticated current-user request before dispatch', async () => {
    const response = await requestJson(server, 'GET', '/api/users/me');

    expect(response).toEqual({
      statusCode: 401,
      body: {
        status: 'error',
        message: 'No token provided',
      },
    });
    expect(userService.getMe).not.toHaveBeenCalled();
  });

  it.each([
    ['PUT', '/api/users/profile', { firstname: 'Safe' }, 'updateProfile'],
    [
      'POST',
      '/api/avatar/upload-url',
      { contentType: 'image/jpeg', sizeBytes: 1024 },
      'requestUpload',
    ],
    [
      'POST',
      '/api/avatar/confirm',
      { key: AVATAR_KEY, contentType: 'image/jpeg' },
      'confirmUpload',
    ],
  ])(
    'rejects unauthenticated %s %s before service dispatch',
    async (method, path, body, serviceMethod) => {
      const response = await requestJson(server, method, path, body);

      expect(response).toEqual({
        statusCode: 401,
        body: {
          status: 'error',
          message: 'No token provided',
        },
      });
      if (serviceMethod === 'updateProfile') {
        expect(userService.updateProfile).not.toHaveBeenCalled();
      } else {
        expect(
          avatarService[serviceMethod as keyof typeof avatarService],
        ).not.toHaveBeenCalled();
      }
    },
  );

  it.each([
    ['GET', '/api/users/profile-picture'],
    ['GET', '/api/users/profile-picture/17'],
    ['POST', '/api/users/profile-picture'],
  ])('keeps the retired %s %s endpoint unavailable', async (method, path) => {
    const response = await requestJson(server, method, path);

    expect(response.statusCode).toBe(404);
  });

  it.each([
    [
      '/api/avatar/upload-url',
      'requestUpload',
      { contentType: 'image/gif', sizeBytes: 1024 },
    ],
    [
      '/api/avatar/upload-url',
      'requestUpload',
      { contentType: 'image/jpeg', sizeBytes: 10 * 1024 * 1024 + 1 },
    ],
    [
      '/api/avatar/upload-url',
      'requestUpload',
      {
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        key: AVATAR_KEY,
      },
    ],
    [
      '/api/avatar/confirm',
      'confirmUpload',
      {
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
        userId: USER_ID,
      },
    ],
  ])(
    'rejects an invalid avatar DTO at %s before calling %s',
    async (path, serviceMethod, body) => {
      const response = await requestJson(server, 'POST', path, body, {
        authorization: AUTHORIZATION,
      });

      expect(response).toEqual({
        statusCode: 400,
        body: { message: 'Validation failed' },
      });
      expect(
        avatarService[serviceMethod as keyof typeof avatarService],
      ).not.toHaveBeenCalled();
    },
  );

  it('maps the service-level MIME/extension mismatch to a safe HTTP 400', async () => {
    avatarService.requestUpload.mockRejectedValueOnce(
      new AvatarServiceError(
        'Avatar extension does not match content type',
        400,
      ),
    );

    const response = await requestJson(
      server,
      'POST',
      '/api/avatar/upload-url',
      { ext: 'png', contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: AUTHORIZATION },
    );

    expect(response).toEqual({
      statusCode: 400,
      body: { message: 'Avatar extension does not match content type' },
    });
    expect(avatarService.requestUpload).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({
        ext: 'png',
        contentType: 'image/jpeg',
      }),
    );
  });

  it.each([
    ['Avatar upload intent has expired', 410],
    ['Avatar storage verification is temporarily unavailable', 503],
  ])(
    'maps the typed safe confirm error %s to HTTP %i',
    async (message, statusCode) => {
      avatarService.confirmUpload.mockRejectedValueOnce(
        new AvatarServiceError(message, statusCode),
      );

      const response = await requestJson(
        server,
        'POST',
        '/api/avatar/confirm',
        { key: AVATAR_KEY, contentType: 'image/jpeg' },
        { authorization: AUTHORIZATION },
      );

      expect(response).toEqual({
        statusCode,
        body: { message },
      });
    },
  );

  it('returns the valid multipart grant and both confirmation states', async () => {
    const grant = {
      uploadUrl: 'https://uploads.example.com',
      uploadMethod: 'POST',
      fields: {
        key: AVATAR_KEY,
        Policy: 'signed-policy',
        'X-Amz-Signature': 'signature',
      },
      key: AVATAR_KEY,
      expiresAt: '2026-07-10T10:05:00.000Z',
    };
    avatarService.requestUpload.mockResolvedValueOnce(grant);
    avatarService.confirmUpload
      .mockResolvedValueOnce({
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
        alreadyConfirmed: false,
      })
      .mockResolvedValueOnce({
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
        alreadyConfirmed: true,
      });

    const grantResponse = await requestJson(
      server,
      'POST',
      '/api/avatar/upload-url',
      { ext: 'jpeg', contentType: 'image/jpeg', sizeBytes: 1024 },
      { authorization: AUTHORIZATION },
    );
    const firstConfirmation = await requestJson(
      server,
      'POST',
      '/api/avatar/confirm',
      { key: AVATAR_KEY, contentType: 'image/jpeg' },
      { authorization: AUTHORIZATION },
    );
    const repeatedConfirmation = await requestJson(
      server,
      'POST',
      '/api/avatar/confirm',
      { key: AVATAR_KEY, contentType: 'image/jpeg' },
      { authorization: AUTHORIZATION },
    );

    expect(grantResponse).toEqual({ statusCode: 200, body: grant });
    expect(firstConfirmation).toEqual({
      statusCode: 200,
      body: {
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
        alreadyConfirmed: false,
      },
    });
    expect(repeatedConfirmation).toEqual({
      statusCode: 200,
      body: {
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
        alreadyConfirmed: true,
      },
    });
    expect(avatarService.requestUpload).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({
        ext: 'jpeg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
      }),
    );
    expect(avatarService.confirmUpload).toHaveBeenCalledTimes(2);
    expect(avatarService.confirmUpload).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({
        key: AVATAR_KEY,
        contentType: 'image/jpeg',
      }),
    );
  });
});
