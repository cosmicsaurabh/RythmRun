import 'reflect-metadata';

import { Request, Response } from 'express';
import { ActivityController } from '../controllers/activity.controller';
import {
  ActivityDomainValidationError,
  ActivityNotFoundError,
} from '../services/activity.service';
import { MAX_ACTIVITY_LOCATIONS } from '../models/dto/activity.dto';
import {
  MAX_DTO_ISSUE_MESSAGE_LENGTH,
  MAX_DTO_ISSUE_PATH_LENGTH,
} from '../middleware/validation.middleware';

function createResponse() {
  const response = {
    status: jest.fn(),
    json: jest.fn(),
  };
  response.status.mockReturnValue(response);
  response.json.mockReturnValue(response);
  return response as unknown as Response & {
    status: jest.Mock;
    json: jest.Mock;
  };
}

function createRequest(body: unknown, activityId = '42'): Request {
  return {
    body,
    params: { activityId },
    user: { id: 17 },
  } as unknown as Request;
}

function validCreatePayload(locationCount = 1) {
  const startTime = Date.parse('2026-03-22T10:00:00.000Z');

  return {
    clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ab',
    metricsVersion: 2,
    type: 'running',
    startTime: new Date(startTime).toISOString(),
    endTime: new Date(startTime + 1800_000).toISOString(),
    distance: 5000,
    duration: 1800,
    avgSpeed: 5000 / 1800,
    maxSpeed: 4.5,
    calories: null,
    description: 'x'.repeat(4000),
    isPublic: false,
    pausedDuration: null,
    name: 'n'.repeat(120),
    elevationGain: null,
    elevationLoss: null,
    locations: Array.from({ length: locationCount }, (_, index) => ({
      latitude: 28.6139,
      longitude: 77.209,
      altitude: 216,
      timestamp: new Date(startTime + index * 1000).toISOString(),
      accuracy: 5,
      speed: 2.5,
      heading: 90,
    })),
    statusChanges: [
      { status: 'active', timestamp: new Date(startTime).toISOString() },
      {
        status: 'completed',
        timestamp: new Date(startTime + 1800_000).toISOString(),
      },
    ],
  };
}

describe('ActivityController payload validation', () => {
  const activityService = {
    createActivity: jest.fn(),
    updateActivity: jest.fn(),
  };
  const controller = new ActivityController(activityService as any);

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('accepts the audited 750-point request and dispatches the transformed DTO', async () => {
    const payload = validCreatePayload(750);
    expect(Buffer.byteLength(JSON.stringify(payload))).toBeGreaterThan(100 * 1024);
    activityService.createActivity.mockResolvedValue({ id: 9 });
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).toHaveBeenCalledWith(
      17,
      expect.objectContaining({
        clientSyncId: payload.clientSyncId,
        locations: expect.arrayContaining([
          expect.objectContaining({ latitude: 28.6139 }),
        ]),
      }),
    );
    expect(response.status).toHaveBeenCalledWith(201);
  });

  it('rejects invalid nested route data before service dispatch', async () => {
    const payload = validCreatePayload();
    payload.locations[0].latitude = 91;
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    expect(response.status).toHaveBeenCalledWith(400);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        code: 'ACTIVITY_REQUEST_INVALID',
        retryable: false,
        issuesTruncated: false,
        issues: expect.arrayContaining([
          expect.objectContaining({
            code: 'ACTIVITY_FIELD_INVALID',
            path: 'locations.0.latitude',
          }),
        ]),
      }),
    );
  });

  it('returns a specific permanent code when the location cap is exceeded', async () => {
    const payload = validCreatePayload();
    payload.locations = Array.from(
      { length: MAX_ACTIVITY_LOCATIONS + 1 },
      () => payload.locations[0],
    );
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    expect(response.status).toHaveBeenCalledWith(400);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({
        code: 'ACTIVITY_REQUEST_INVALID',
        issues: expect.arrayContaining([
          expect.objectContaining({
            code: 'ACTIVITY_LOCATION_LIMIT_EXCEEDED',
            path: 'locations',
          }),
        ]),
      }),
    );
  });

  it('preserves collection omission when dispatching a name-only PATCH', async () => {
    activityService.updateActivity.mockResolvedValue({ id: 42, name: 'Renamed' });
    const response = createResponse();

    await controller.updateActivity(
      createRequest({ name: 'Renamed' }),
      response,
    );

    const dto = activityService.updateActivity.mock.calls[0][2];
    expect(dto).toMatchObject({ name: 'Renamed' });
    expect(Object.prototype.hasOwnProperty.call(dto, 'locations')).toBe(false);
    expect(Object.prototype.hasOwnProperty.call(dto, 'statusChanges')).toBe(false);
    expect(response.status).toHaveBeenCalledWith(200);
  });

  it('rejects a null PATCH collection before service dispatch', async () => {
    const response = createResponse();

    await controller.updateActivity(
      createRequest({ statusChanges: null }),
      response,
    );

    expect(activityService.updateActivity).not.toHaveBeenCalled();
    expect(response.status).toHaveBeenCalledWith(400);
    expect(response.json).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'ACTIVITY_REQUEST_INVALID' }),
    );
  });

  it('maps domain validation failures to a stable non-retryable 422', async () => {
    activityService.updateActivity.mockRejectedValue(
      new ActivityDomainValidationError([
        {
          code: 'ACTIVITY_DURATION_INVALID',
          property: 'duration',
          message: 'Active and paused duration must match the workout window',
        },
      ]),
    );
    const response = createResponse();

    await controller.updateActivity(
      createRequest({ duration: 120 }),
      response,
    );

    expect(response.status).toHaveBeenCalledWith(422);
    expect(response.json).toHaveBeenCalledWith({
      status: 'error',
      code: 'ACTIVITY_DOMAIN_INVALID',
      message: 'Activity payload is invalid',
      retryable: false,
      issuesTruncated: false,
      issues: [
        {
          code: 'ACTIVITY_DURATION_INVALID',
          path: 'duration',
          message: 'Active and paused duration must match the workout window',
        },
      ],
    });
  });

  it('maps an owner-scoped missing/raced PATCH to a stable 404', async () => {
    activityService.updateActivity.mockRejectedValue(new ActivityNotFoundError());
    const response = createResponse();

    await controller.updateActivity(
      createRequest({ name: 'Renamed' }),
      response,
    );

    expect(response.status).toHaveBeenCalledWith(404);
    expect(response.json).toHaveBeenCalledWith({
      status: 'error',
      code: 'ACTIVITY_NOT_FOUND',
      message: 'Activity not found or unauthorized',
      retryable: false,
    });
  });

  it.each(['42junk', '42.9', '0', '-1', '9007199254740992'])(
    'rejects the non-exact activity ID %s before service dispatch',
    async activityId => {
      const response = createResponse();

      await controller.updateActivity(
        createRequest({ name: 'Must not dispatch' }, activityId),
        response,
      );

      expect(activityService.updateActivity).not.toHaveBeenCalled();
      expect(response.status).toHaveBeenCalledWith(400);
    },
  );

  it('bounds an adversarial nested validation response', async () => {
    const payload = validCreatePayload();
    payload.locations = Array.from(
      { length: MAX_ACTIVITY_LOCATIONS },
      () =>
        ({
          latitude: 'invalid',
          longitude: 'invalid',
          timestamp: 'invalid',
          unexpected: true,
        }) as any,
    );
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    const errorBody = response.json.mock.calls[0][0];
    expect(errorBody.issues).toHaveLength(1);
    expect(errorBody.issuesTruncated).toBe(false);
    expect(Buffer.byteLength(JSON.stringify(errorBody))).toBeLessThan(16 * 1024);
  });

  it('rejects a wide unknown-root payload before transformation', async () => {
    const payload: Record<string, unknown> = validCreatePayload();
    for (let index = 0; index < 100_000; index += 1) {
      payload[`unknown${index}`] = index;
    }
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    const errorBody = response.json.mock.calls[0][0];
    expect(errorBody.issues).toHaveLength(1);
    expect(errorBody.issues[0]).toMatchObject({
      code: 'ACTIVITY_FIELD_NOT_ALLOWED',
      path: '$root',
      message: 'object contains an unsupported field',
    });
    expect(Buffer.byteLength(JSON.stringify(errorBody))).toBeLessThan(16 * 1024);
  });

  it('rejects a deeply nested scalar value without recursive traversal', async () => {
    const payload: Record<string, unknown> = validCreatePayload();
    let nested: Record<string, unknown> = {};
    for (let depth = 0; depth < 10_000; depth += 1) {
      nested = { child: nested };
    }
    payload.description = nested;
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    expect(response.status).toHaveBeenCalledWith(400);
    expect(response.json.mock.calls[0][0]).toMatchObject({
      code: 'ACTIVITY_REQUEST_INVALID',
      issues: [expect.objectContaining({ path: 'description' })],
    });
  });

  it('does not reflect an attacker-sized nested key in the response', async () => {
    const payload = validCreatePayload();
    payload.locations[0] = {
      ...payload.locations[0],
      ['x'.repeat(500_000)]: true,
    } as any;
    const response = createResponse();

    await controller.createActivity(createRequest(payload), response);

    expect(activityService.createActivity).not.toHaveBeenCalled();
    const errorBody = response.json.mock.calls[0][0];
    expect(errorBody.issues[0].path.length).toBeLessThanOrEqual(
      MAX_DTO_ISSUE_PATH_LENGTH,
    );
    expect(errorBody.issues[0].message.length).toBeLessThanOrEqual(
      MAX_DTO_ISSUE_MESSAGE_LENGTH,
    );
    expect(Buffer.byteLength(JSON.stringify(errorBody))).toBeLessThan(16 * 1024);
  });
});
