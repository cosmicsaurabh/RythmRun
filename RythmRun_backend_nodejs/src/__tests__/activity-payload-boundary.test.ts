import 'reflect-metadata';
import { jest } from '@jest/globals';
import type { ActivityRouteController } from '../routes/activity.routes.js';

const mockProductionController = {
  listActivities: jest.fn(),
  getActivity: jest.fn(),
  createActivity: jest.fn(),
  updateActivity: jest.fn(),
  deleteActivity: jest.fn(),
};

jest.unstable_mockModule('../config/container.js', () => ({
  container: {
    resolve: jest.fn(() => mockProductionController),
  },
}));

import http, { type Server } from 'node:http';
import type { IncomingHttpHeaders } from 'node:http';
import { EventEmitter } from 'node:events';
import type { AddressInfo } from 'node:net';
import {
  type NextFunction,
  type Request,
  type RequestHandler,
  type Response,
  Router,
} from 'express';
import { createApp, DEFAULT_JSON_LIMIT_BYTES } from '../app.js';
import { validateDto } from '../middleware/validation.middleware.js';
import { validateActivityCreate } from '../models/activity-domain-validation.js';
import { CreateActivityDto } from '../models/dto/activity.dto.js';
const {
  ACTIVITY_BOUNDARY_ERROR_CODES,
  ACTIVITY_JSON_LIMIT_BYTES,
  createActivityMutationBoundary,
  createActivityRouter,
} = await import('../routes/activity.routes.js');

const AUTHORIZATION_PREFIX = 'Bearer user-';

interface HttpResponse {
  statusCode: number;
  headers: IncomingHttpHeaders;
  body: unknown;
}

interface RequestOptions {
  authorization?: string;
  includeContentLength?: boolean;
}

function requestRaw(
  server: Server,
  method: string,
  path: string,
  payload: string,
  {
    authorization,
    includeContentLength = true,
  }: RequestOptions = {},
): Promise<HttpResponse> {
  const { port } = server.address() as AddressInfo;

  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port,
        method,
        path,
        headers: {
          'content-type': 'application/json',
          ...(authorization === undefined ? {} : { authorization }),
          ...(includeContentLength
            ? { 'content-length': Buffer.byteLength(payload) }
            : {}),
        },
      },
      response => {
        const chunks: Buffer[] = [];
        response.on('data', chunk => chunks.push(Buffer.from(chunk)));
        response.on('error', reject);
        response.on('end', () => {
          const responseText = Buffer.concat(chunks).toString('utf8');
          let body: unknown = responseText;

          if (
            responseText &&
            response.headers['content-type']?.includes('json')
          ) {
            body = JSON.parse(responseText);
          }

          resolve({
            statusCode: response.statusCode ?? 0,
            headers: response.headers,
            body,
          });
        });
      },
    );

    request.on('error', reject);
    request.write(payload);
    request.end();
  });
}

function createDeferred() {
  let resolve!: () => void;
  const promise = new Promise<void>(complete => {
    resolve = complete;
  });
  return { promise, resolve };
}

function buildActivityPayload(
  locationCount: number,
  statusChangeCount = 4,
) {
  const startedAt = Date.parse('2026-03-22T10:00:00.123Z');
  const wallDurationSeconds = 6 * 60 * 60;
  const endedAt = startedAt + wallDurationSeconds * 1000;
  const pausedDuration = Math.max(0, Math.floor((statusChangeCount - 2) / 2));
  const duration = wallDurationSeconds - pausedDuration;
  const distance = 0;
  const routeStartedAt = startedAt + statusChangeCount * 1000;
  const routeWindowMilliseconds = endedAt - routeStartedAt;

  return {
    clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ab',
    metricsVersion: 2,
    type: 'cycling',
    startTime: new Date(startedAt).toISOString(),
    endTime: new Date(endedAt).toISOString(),
    distance,
    duration,
    avgSpeed: distance / duration,
    maxSpeed: 0,
    calories: 100000,
    description: 'x'.repeat(2000),
    name: 'n'.repeat(120),
    pausedDuration,
    elevationGain: 99999.123456789,
    elevationLoss: 99999.123456789,
    isPublic: false,
    locations: Array.from({ length: locationCount }, (_, index) => ({
      latitude: -89.12345678901234,
      longitude: -179.12345678901234,
      altitude: -499.1234567890123,
      timestamp: new Date(
        routeStartedAt + Math.floor(
          index * routeWindowMilliseconds / Math.max(1, locationCount - 1),
        ),
      ).toISOString(),
      accuracy: 49.1234567890123,
      speed: 19.12345678901234,
      heading: 359.1234567890123,
    })),
    statusChanges: Array.from({ length: statusChangeCount }, (_, index) => ({
      status:
        index === statusChangeCount - 1
          ? 'completed'
          : index % 2 === 0
            ? 'active'
            : 'paused',
      timestamp: new Date(
        index === statusChangeCount - 1
          ? endedAt
          : startedAt + index * 1000,
      ).toISOString(),
    })),
  };
}

function createEmptyRouter(): Router {
  return Router();
}

function createAdmissionResponse(): Response & EventEmitter {
  const response = new EventEmitter() as Response & EventEmitter;
  response.setHeader = jest.fn() as any;
  response.status = jest.fn(() => response) as any;
  response.json = jest.fn(() => response) as any;
  return response;
}

function createNestedBodyRouter(): Router {
  const router = Router({ mergeParams: true });
  router.post('/probe', (_req, res) => res.status(204).end());
  return router;
}

describe('activity payload HTTP boundary', () => {
  let server!: Server;
  let createRequestHandler: RequestHandler;
  let updateRequestHandler: RequestHandler;

  const authenticate = jest.fn(
    (req: Request, res: Response, next: NextFunction) => {
      const authorization = req.headers.authorization;
      if (!authorization?.startsWith(AUTHORIZATION_PREFIX)) {
        res.status(401).json({
          status: 'error',
          message: 'No token provided',
        });
        return;
      }

      const userId = Number(authorization.slice(AUTHORIZATION_PREFIX.length));
      if (!Number.isSafeInteger(userId)) {
        res.status(401).json({
          status: 'error',
          message: 'Invalid token',
        });
        return;
      }

      req.user = { id: userId };
      next();
    },
  );

  const controller: ActivityRouteController = {
    listActivities: jest.fn((_req, res) => res.status(200).json({ ok: true })),
    getActivity: jest.fn((_req, res) => res.status(200).json({ ok: true })),
    createActivity: jest.fn((req, res, next) =>
      createRequestHandler(req, res, next)),
    updateActivity: jest.fn((req, res, next) =>
      updateRequestHandler(req, res, next)),
    deleteActivity: jest.fn((_req, res) => res.status(204).end()),
  };

  const realMutationBoundary = createActivityMutationBoundary();
  const admit = jest.fn(realMutationBoundary.admit);
  const rejectOversizedContentLength = jest.fn(
    realMutationBoundary.rejectOversizedContentLength,
  );
  const parseJson = jest.fn(realMutationBoundary.parseJson);

  beforeAll(async () => {
    const users = Router();
    users.post('/probe', (_req, res) => res.status(204).end());

    const app = createApp({
      users,
      friends: createEmptyRouter(),
      avatar: createEmptyRouter(),
      activityImages: createNestedBodyRouter(),
      activities: createActivityRouter({
        controller,
        authenticate,
        mutationBoundary: {
          admit,
          rejectOversizedContentLength,
          parseJson,
        },
      }),
      comments: createNestedBodyRouter(),
      likes: createNestedBodyRouter(),
    });

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
    createRequestHandler = (_req, res) =>
      res.status(201).json({ status: 'success' });
    updateRequestHandler = (_req, res) =>
      res.status(200).json({ status: 'success' });
  });

  afterAll(async () => {
    if (!server) {
      return;
    }

    await new Promise<void>((resolve, reject) => {
      server.close(error => (error ? reject(error) : resolve()));
    });
  });

  it('keeps the audited maximum canonical fixture valid and below the exact 3 MiB limit', async () => {
    const payload = buildActivityPayload(12000, 1000);
    const payloadBytes = Buffer.byteLength(JSON.stringify(payload));

    expect(payloadBytes).toBeGreaterThan(2 * 1024 * 1024);
    expect(payloadBytes).toBeLessThan(ACTIVITY_JSON_LIMIT_BYTES);
    expect(ACTIVITY_JSON_LIMIT_BYTES).toBe(3 * 1024 * 1024);

    const dto = await validateDto(CreateActivityDto, payload);
    expect(() => validateActivityCreate(dto)).not.toThrow();

    const response = await requestRaw(
      server,
      'POST',
      '/api/activities',
      JSON.stringify(payload),
      { authorization: `${AUTHORIZATION_PREFIX}1` },
    );
    expect(response.statusCode).toBe(201);
    expect(controller.createActivity).toHaveBeenCalledTimes(1);
  });

  it('rejects an unauthenticated oversized activity before admission or parsing', async () => {
    const oversizedPayload = JSON.stringify({
      padding: 'x'.repeat(ACTIVITY_JSON_LIMIT_BYTES),
    });

    const response = await requestRaw(
      server,
      'POST',
      '/api/activities',
      oversizedPayload,
    );

    expect(response.statusCode).toBe(401);
    expect(admit).not.toHaveBeenCalled();
    expect(rejectOversizedContentLength).not.toHaveBeenCalled();
    expect(parseJson).not.toHaveBeenCalled();
    expect(controller.createActivity).not.toHaveBeenCalled();
  });

  it('keeps authentication before body parsing for case-insensitive Express routes', async () => {
    const payload = JSON.stringify(buildActivityPayload(750));
    expect(Buffer.byteLength(payload)).toBeGreaterThan(
      DEFAULT_JSON_LIMIT_BYTES,
    );

    const unauthenticated = await requestRaw(
      server,
      'POST',
      '/API/ACTIVITIES',
      payload,
    );
    expect(unauthenticated.statusCode).toBe(401);
    expect(admit).not.toHaveBeenCalled();
    expect(parseJson).not.toHaveBeenCalled();

    const authenticated = await requestRaw(
      server,
      'POST',
      '/API/ACTIVITIES',
      payload,
      { authorization: `${AUTHORIZATION_PREFIX}1` },
    );
    expect(authenticated.statusCode).toBe(201);
    expect(parseJson).toHaveBeenCalledTimes(1);
    expect(controller.createActivity).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['POST', '/api/activities', 'createActivity'],
    ['PATCH', '/api/activities/42', 'updateActivity'],
  ])('rejects authenticated oversized Content-Length at %s %s before JSON parsing', async (method, path, controllerMethod) => {
    const oversizedPayload = JSON.stringify({
      padding: 'x'.repeat(ACTIVITY_JSON_LIMIT_BYTES),
    });

    const response = await requestRaw(
      server,
      method,
      path,
      oversizedPayload,
      { authorization: `${AUTHORIZATION_PREFIX}1` },
    );

    expect(response).toMatchObject({
      statusCode: 413,
      body: {
        status: 'error',
        code: ACTIVITY_BOUNDARY_ERROR_CODES.tooLarge,
        retryable: false,
      },
    });
    expect(admit).toHaveBeenCalledTimes(1);
    expect(rejectOversizedContentLength).toHaveBeenCalledTimes(1);
    expect(parseJson).not.toHaveBeenCalled();
    expect(
      controller[controllerMethod as keyof ActivityRouteController],
    ).not.toHaveBeenCalled();
  });

  it('uses the parser as the authoritative limit for a chunked body', async () => {
    const oversizedPayload = JSON.stringify({
      padding: 'x'.repeat(ACTIVITY_JSON_LIMIT_BYTES),
    });

    const response = await requestRaw(
      server,
      'POST',
      '/api/activities',
      oversizedPayload,
      {
        authorization: `${AUTHORIZATION_PREFIX}1`,
        includeContentLength: false,
      },
    );

    expect(response).toMatchObject({
      statusCode: 413,
      body: {
        status: 'error',
        code: ACTIVITY_BOUNDARY_ERROR_CODES.tooLarge,
        retryable: false,
      },
    });
    expect(rejectOversizedContentLength).toHaveBeenCalledTimes(1);
    expect(parseJson).toHaveBeenCalledTimes(1);
    expect(controller.createActivity).not.toHaveBeenCalled();
  });

  it.each([
    ['POST', '/api/activities', 'createActivity'],
    ['PATCH', '/api/activities/42', 'updateActivity'],
  ])('returns a stable JSON code for malformed activity JSON at %s %s', async (method, path, controllerMethod) => {
    const response = await requestRaw(
      server,
      method,
      path,
      '{"locations":[}',
      { authorization: `${AUTHORIZATION_PREFIX}1` },
    );

    expect(response).toMatchObject({
      statusCode: 400,
      body: {
        status: 'error',
        code: ACTIVITY_BOUNDARY_ERROR_CODES.invalidJson,
        retryable: false,
      },
    });
    expect(parseJson).toHaveBeenCalledTimes(1);
    expect(
      controller[controllerMethod as keyof ActivityRouteController],
    ).not.toHaveBeenCalled();
  });

  it.each([
    ['POST', '/api/activities', 'createActivity'],
    ['PATCH', '/api/activities/42', 'updateActivity'],
  ])(
    'accepts an authenticated 750-point body at %s %s',
    async (method, path, controllerMethod) => {
      const payload = JSON.stringify(buildActivityPayload(750));
      expect(Buffer.byteLength(payload)).toBeGreaterThan(
        DEFAULT_JSON_LIMIT_BYTES,
      );

      const response = await requestRaw(server, method, path, payload, {
        authorization: `${AUTHORIZATION_PREFIX}1`,
      });

      expect(response.statusCode).toBe(method === 'POST' ? 201 : 200);
      expect(
        controller[controllerMethod as keyof ActivityRouteController],
      ).toHaveBeenCalledTimes(1);
      const request = (
        controller[controllerMethod as keyof ActivityRouteController] as jest.Mock
      ).mock.calls[0][0] as Request;
      expect(request.body.locations).toHaveLength(750);
    },
  );

  it.each([
    ['POST', '/api/users/probe'],
    ['POST', '/api/activities/1/images/probe'],
    ['POST', '/api/activities/1/comments/probe'],
    ['POST', '/api/activities/1/likes/probe'],
    ['GET', '/api/activities'],
    ['GET', '/api/activities/1'],
    ['DELETE', '/api/activities/1'],
  ])('retains the ordinary 100 KiB parser for %s %s', async (method, path) => {
    const payload = JSON.stringify({
      padding: 'x'.repeat(DEFAULT_JSON_LIMIT_BYTES),
    });

    const response = await requestRaw(server, method, path, payload);

    expect(response.statusCode).toBe(413);
  });

  it('rejects a second mutation for the same user without parsing it', async () => {
    const enteredController = createDeferred();
    const releaseController = createDeferred();
    createRequestHandler = async (_req, res) => {
      enteredController.resolve();
      await releaseController.promise;
      res.status(201).json({ status: 'success' });
    };

    const firstResponse = requestRaw(
      server,
      'POST',
      '/api/activities',
      '{}',
      { authorization: `${AUTHORIZATION_PREFIX}7` },
    );
    await enteredController.promise;

    const secondResponse = await requestRaw(
      server,
      'PATCH',
      '/api/activities/42',
      '{}',
      { authorization: `${AUTHORIZATION_PREFIX}7` },
    );

    expect(secondResponse).toMatchObject({
      statusCode: 429,
      headers: { 'retry-after': '1' },
      body: {
        status: 'error',
        code: ACTIVITY_BOUNDARY_ERROR_CODES.busy,
        retryable: true,
      },
    });
    expect(parseJson).toHaveBeenCalledTimes(1);
    expect(controller.updateActivity).not.toHaveBeenCalled();

    releaseController.resolve();
    await expect(firstResponse).resolves.toMatchObject({ statusCode: 201 });

    await expect(
      requestRaw(server, 'PATCH', '/api/activities/42', '{}', {
        authorization: `${AUTHORIZATION_PREFIX}7`,
      }),
    ).resolves.toMatchObject({ statusCode: 200 });
  });

  it('admits at most four activity mutations globally', async () => {
    const enteredControllers = Array.from({ length: 4 }, createDeferred);
    const releaseControllers = createDeferred();
    let enteredCount = 0;
    createRequestHandler = async (_req, res) => {
      enteredControllers[enteredCount].resolve();
      enteredCount += 1;
      await releaseControllers.promise;
      res.status(201).json({ status: 'success' });
    };

    const admittedResponses = Array.from({ length: 4 }, (_, index) =>
      requestRaw(server, 'POST', '/api/activities', '{}', {
        authorization: `${AUTHORIZATION_PREFIX}${index + 1}`,
      }),
    );
    await Promise.all(enteredControllers.map(deferred => deferred.promise));

    const rejectedResponse = await requestRaw(
      server,
      'POST',
      '/api/activities',
      '{}',
      { authorization: `${AUTHORIZATION_PREFIX}5` },
    );

    expect(rejectedResponse).toMatchObject({
      statusCode: 429,
      headers: { 'retry-after': '1' },
      body: {
        status: 'error',
        code: ACTIVITY_BOUNDARY_ERROR_CODES.busy,
        retryable: true,
      },
    });
    expect(parseJson).toHaveBeenCalledTimes(4);
    expect(controller.createActivity).toHaveBeenCalledTimes(4);

    releaseControllers.resolve();
    await Promise.all(admittedResponses);
  });

  it('releases an admission slot exactly once when the client closes', () => {
    const boundary = createActivityMutationBoundary({
      globalConcurrencyLimit: 1,
      userConcurrencyLimit: 1,
    });
    const request = { user: { id: 91 } } as Request;
    const firstResponse = createAdmissionResponse();
    const firstNext = jest.fn();

    boundary.admit(request, firstResponse, firstNext);
    expect(firstNext).toHaveBeenCalledTimes(1);
    firstResponse.emit('close');
    firstResponse.emit('finish');

    const secondResponse = createAdmissionResponse();
    const secondNext = jest.fn();
    boundary.admit(request, secondResponse, secondNext);
    expect(secondNext).toHaveBeenCalledTimes(1);

    const rejectedResponse = createAdmissionResponse();
    const rejectedNext = jest.fn();
    boundary.admit(request, rejectedResponse, rejectedNext);
    expect(rejectedNext).not.toHaveBeenCalled();
    expect(rejectedResponse.status).toHaveBeenCalledWith(429);
  });
});
