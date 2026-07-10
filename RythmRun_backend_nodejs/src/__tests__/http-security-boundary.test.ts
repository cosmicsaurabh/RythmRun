import 'reflect-metadata';

const mockProductionController = {
  register: jest.fn(),
  login: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
  getUploadUrl: jest.fn(),
  confirmUpload: jest.fn(),
};

jest.mock('../config/container', () => ({
  container: {
    resolve: jest.fn(() => mockProductionController),
  },
}));

// AvatarController's typed error dependency imports AvatarService. Replace the
// unrelated S3 module before evaluation so this HTTP test constructs no AWS
// client while still using the real controller and AvatarServiceError class.
jest.mock('../services/s3.service', () => ({
  S3Service: class S3Service {},
}));

import http, { Server } from 'http';
import { AddressInfo } from 'net';
import { NextFunction, Request, Response, Router } from 'express';
import { createApp } from '../app';
import { AvatarController } from '../controllers/avatar.controller';
import { UserController } from '../controllers/user.controller';
import { createAvatarRouter } from '../routes/avatar.routes';
import { createUserRouter } from '../routes/user.routes';
import { AvatarServiceError } from '../services/avatar.service';

const USER_ID = 17;
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
    logout: jest.fn(),
    refreshToken: jest.fn(),
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

      req.user = { id: USER_ID };
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
      const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
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
