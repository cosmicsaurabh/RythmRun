import 'reflect-metadata';

import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import {
  CreateActivityDto,
  CURRENT_METRICS_VERSION,
  LEGACY_METRICS_VERSION,
} from '../models/dto/activity.dto';

const validCreatePayload = {
  clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ab',
  type: 'running',
  startTime: '2026-03-22T10:00:00.000Z',
  endTime: '2026-03-22T10:30:00.000Z',
  distance: 5000,
  duration: 1800,
  avgSpeed: 2.78,
  maxSpeed: 4.5,
  locations: [],
};

async function validateCreatePayload(metricsVersion?: unknown) {
  const payload = {
    ...validCreatePayload,
    ...(metricsVersion === undefined ? {} : { metricsVersion }),
  };
  const dto = plainToInstance(CreateActivityDto, payload);

  return validate(dto, {
    forbidUnknownValues: true,
    whitelist: true,
  });
}

describe('CreateActivityDto metricsVersion', () => {
  it.each([
    ['an omitted version', undefined],
    ['a null version from an older client', null],
    ['the legacy version', LEGACY_METRICS_VERSION],
    ['the canonical version', CURRENT_METRICS_VERSION],
  ])('accepts %s', async (_label, metricsVersion) => {
    await expect(validateCreatePayload(metricsVersion)).resolves.toHaveLength(0);
  });

  it.each([
    ['zero', 0],
    ['an unsupported future version', 3],
    ['a fractional version', 1.5],
    ['a numeric string', '2'],
  ])('rejects %s', async (_label, metricsVersion) => {
    const errors = await validateCreatePayload(metricsVersion);

    expect(errors).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ property: 'metricsVersion' }),
      ]),
    );
  });
});
