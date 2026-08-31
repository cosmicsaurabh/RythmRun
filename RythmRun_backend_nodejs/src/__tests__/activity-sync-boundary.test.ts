import 'reflect-metadata';
import { jest } from '@jest/globals';

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

const mockGetActivityImageReadUrl = jest.fn(async (_key: string) => ({
  url: 'https://signed.example.invalid/activity-image',
  urlExpiresAt: '2026-08-31T12:15:00.000Z',
}));
const mockDeleteObject = jest.fn(async (_key: string) => undefined);

jest.unstable_mockModule('../services/s3.service.js', () => ({
  S3Service: class S3Service {},
  default: {
    getActivityImageReadUrl: mockGetActivityImageReadUrl,
    deleteObject: mockDeleteObject,
  },
}));

import http, { type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';

const { createApp } = await import('../app.js');
const { ActivityController } = await import(
  '../controllers/activity.controller.js'
);
const { createActivityRouter } = await import('../routes/activity.routes.js');
const { ActivityService } = await import('../services/activity.service.js');

const USER_ID = 17;
const ACTIVITY_ID = 41;
const AUTHORIZATION = 'Bearer activity-boundary-test-token';
const INTERNAL_IMAGE_KEY = 'activity-images/test/activity.jpg';

interface HttpResponse {
  statusCode: number;
  body: unknown;
}

const mockPrisma = {
  activity: {
    findMany: jest.fn(),
    count: jest.fn(),
    findFirst: jest.fn(),
    delete: jest.fn(),
  },
};

function activityRecord() {
  return {
    id: ACTIVITY_ID,
    userId: USER_ID,
    clientSyncId: 'rr-test-sync-id',
    metricsVersion: 2,
    type: 'running',
    startTime: new Date('2026-08-31T10:00:00.000Z'),
    endTime: new Date('2026-08-31T10:30:00.000Z'),
    distance: 5000,
    duration: 1800,
    avgSpeed: 2.78,
    maxSpeed: 4.2,
    isPublic: false,
    locations: [],
    statusChanges: [],
    images: [
      {
        id: 7,
        activityId: ACTIVITY_ID,
        userId: USER_ID,
        clientImageId: 'image-test-id',
        s3Key: INTERNAL_IMAGE_KEY,
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        sortOrder: 0,
        status: 'UPLOADED',
      },
    ],
    _count: { comments: 0, likes: 0 },
  };
}

const authenticate = (
  req: Request,
  res: Response,
  next: NextFunction,
) => {
  if (req.headers.authorization !== AUTHORIZATION) {
    res.status(401).json({ status: 'error', message: 'No token provided' });
    return;
  }

  req.user = { id: USER_ID };
  next();
};

function request(
  server: Server,
  method: string,
  path: string,
): Promise<HttpResponse> {
  const { port } = server.address() as AddressInfo;

  return new Promise((resolve, reject) => {
    const outbound = http.request(
      {
        host: '127.0.0.1',
        port,
        method,
        path,
        headers: { authorization: AUTHORIZATION },
      },
      response => {
        const chunks: Buffer[] = [];
        response.on('data', chunk => chunks.push(Buffer.from(chunk)));
        response.on('error', reject);
        response.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          const body = text ? JSON.parse(text) : undefined;
          resolve({
            statusCode: response.statusCode ?? 0,
            body,
          });
        });
      },
    );

    outbound.on('error', reject);
    outbound.end();
  });
}

async function startTestServer(): Promise<Server> {
  const service = new ActivityService(mockPrisma as any);
  const controller = new ActivityController(service);
  const activities = createActivityRouter({ controller, authenticate });
  const app = createApp({
    users: Router(),
    friends: Router(),
    avatar: Router(),
    activityImages: Router(),
    activities,
    comments: Router(),
    likes: Router(),
  });

  return new Promise((resolve, reject) => {
    const listener = app.listen(0, '127.0.0.1', (error?: Error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(listener);
    });
    listener.on('error', reject);
  });
}

async function stopTestServer(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close(error => (error ? reject(error) : resolve()));
  });
}

describe('activity sync HTTP boundary', () => {
  let server: Server | undefined;
  let activityDeleted = false;

  beforeEach(async () => {
    jest.clearAllMocks();
    activityDeleted = false;
    mockPrisma.activity.findMany.mockResolvedValue([activityRecord()]);
    mockPrisma.activity.count.mockResolvedValue(1);
    mockPrisma.activity.findFirst.mockImplementation(async () =>
      activityDeleted ? null : activityRecord(),
    );
    mockPrisma.activity.delete.mockImplementation(async () => {
      activityDeleted = true;
      return { id: ACTIVITY_ID };
    });
    server = await startTestServer();
  });

  afterEach(async () => {
    try {
      if (server) {
        await stopTestServer(server);
      }
    } finally {
      server = undefined;
      jest.restoreAllMocks();
    }
  });

  it('returns awaited signed image fields without exposing the storage key', async () => {
    const response = await request(
      server!,
      'GET',
      '/api/activities?page=1&limit=10',
    );

    expect(response.statusCode).toBe(200);
    expect(mockPrisma.activity.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId: USER_ID },
        orderBy: [{ startTime: 'desc' }, { id: 'desc' }],
        skip: 0,
        take: 10,
      }),
    );
    expect(mockGetActivityImageReadUrl).toHaveBeenCalledWith(INTERNAL_IMAGE_KEY);

    const body = response.body as {
      data: { activities: Array<{ images: Array<Record<string, unknown>> }> };
    };
    const image = body.data.activities[0].images[0];
    expect(image).toMatchObject({
      id: 7,
      url: 'https://signed.example.invalid/activity-image',
      urlExpiresAt: '2026-08-31T12:15:00.000Z',
    });
    expect(image).not.toHaveProperty('s3Key');
  });

  it.each([
    ['list', '/api/activities?page=1&limit=10', 'Get activities error (Error)'],
    ['detail', `/api/activities/${ACTIVITY_ID}`, 'Get activity error (Error)'],
  ])(
    'fails the %s response without logging signing details',
    async (_endpoint, path, expectedLog) => {
      const consoleError = jest
        .spyOn(console, 'error')
        .mockImplementation(() => {});
      mockGetActivityImageReadUrl.mockRejectedValueOnce(
        new Error('SECRET_SIGNED_URL'),
      );

      const response = await request(server!, 'GET', path);

      expect(response).toEqual({
        statusCode: 500,
        body: {
          status: 'error',
          message: 'Internal server error',
        },
      });
      expect(consoleError).toHaveBeenCalledWith(expectedLog);
      expect(JSON.stringify(consoleError.mock.calls)).not.toContain(
        'SECRET_SIGNED_URL',
      );
    },
  );

  it('returns success followed by typed not-found for sequential deletes', async () => {
    const first = await request(
      server!,
      'DELETE',
      `/api/activities/${ACTIVITY_ID}`,
    );
    const second = await request(
      server!,
      'DELETE',
      `/api/activities/${ACTIVITY_ID}`,
    );

    expect(first.statusCode).toBe(200);
    expect(first.body).toEqual({
      status: 'success',
      data: { message: 'Activity deleted successfully' },
    });
    expect(second.statusCode).toBe(404);
    expect(second.body).toEqual({
      status: 'error',
      code: 'ACTIVITY_NOT_FOUND',
      message: 'Activity not found or unauthorized',
      retryable: false,
    });
    expect(mockPrisma.activity.delete).toHaveBeenCalledTimes(1);
    expect(mockDeleteObject).toHaveBeenCalledTimes(1);
    expect(mockDeleteObject).toHaveBeenCalledWith(INTERNAL_IMAGE_KEY);
  });
});
