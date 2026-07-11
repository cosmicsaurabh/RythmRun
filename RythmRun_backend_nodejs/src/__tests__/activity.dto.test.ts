import 'reflect-metadata';

import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import {
    CreateActivityDto,
    CURRENT_METRICS_VERSION,
    LEGACY_METRICS_VERSION,
    LocationDto,
    MAX_ACTIVITY_LOCATIONS,
    MAX_ACTIVITY_STATUS_CHANGES,
    UpdateActivityDto,
} from '../models/dto/activity.dto';
import { validateDto } from '../middleware/validation.middleware';
import { validateCreateActivityDto } from '../middleware/activity-validation.middleware';

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

describe('activity payload structure', () => {
  const canonicalPayload = {
    ...validCreatePayload,
    metricsVersion: CURRENT_METRICS_VERSION,
    calories: null,
    description: null,
    pausedDuration: null,
    name: null,
    elevationGain: null,
    elevationLoss: null,
    isPublic: false,
    locations: [
      {
        latitude: 28.6139,
        longitude: 77.209,
        altitude: 216,
        timestamp: '2026-03-22T10:00:00.000Z',
        accuracy: 5,
        speed: 2.5,
        heading: 90,
      },
    ],
    statusChanges: [
      { status: 'active', timestamp: '2026-03-22T10:00:00.000Z' },
      { status: 'completed', timestamp: '2026-03-22T10:30:00.000Z' },
    ],
  };

  it('accepts the nullable fields emitted by Flutter and transforms nested rows', async () => {
    const dto = await validateDto(CreateActivityDto, canonicalPayload);

    expect(dto.locations[0]).toBeInstanceOf(LocationDto);
    expect(dto.statusChanges).toHaveLength(2);
  });

  it('keeps the declared collection maxima inside the structural budget', async () => {
    const dto = await validateCreateActivityDto({
      ...canonicalPayload,
      locations: Array.from(
        { length: MAX_ACTIVITY_LOCATIONS },
        () => canonicalPayload.locations[0],
      ),
      statusChanges: Array.from(
        { length: MAX_ACTIVITY_STATUS_CHANGES },
        () => canonicalPayload.statusChanges[0],
      ),
    });

    expect(dto.locations).toHaveLength(MAX_ACTIVITY_LOCATIONS);
    expect(dto.statusChanges).toHaveLength(MAX_ACTIVITY_STATUS_CHANGES);
  });

  it.each([
    ['unknown activity type', { type: 'swimming' }],
    [
      'invalid nested latitude',
      { locations: [{ ...canonicalPayload.locations[0], latitude: 91 }] },
    ],
    [
      'invalid nested status',
      { statusChanges: [{ status: 'deleted', timestamp: canonicalPayload.startTime }] },
    ],
    ['fractional duration', { duration: 10.5 }],
    ['null visibility', { isPublic: null }],
  ])('rejects %s', async (_label, override) => {
    await expect(
      validateDto(CreateActivityDto, { ...canonicalPayload, ...override }),
    ).rejects.toMatchObject({ name: 'DtoValidationError' });
  });

  it('rejects unknown fields inside nested collection entries', async () => {
    await expect(
      validateDto(CreateActivityDto, {
        ...canonicalPayload,
        locations: [
          {
            ...canonicalPayload.locations[0],
            serverManaged: true,
          },
        ],
      }),
    ).rejects.toMatchObject({
      name: 'DtoValidationError',
      issues: expect.arrayContaining([
        expect.objectContaining({
          property: 'locations.0',
          constraints: ['field is not allowed'],
        }),
      ]),
    });
  });

  it.each([
    ['startTime', { startTime: '2026-02-31T10:00:00.000Z' }],
    [
      'locations.0.timestamp',
      {
        locations: [
          {
            ...canonicalPayload.locations[0],
            timestamp: '2026-02-31T10:00:00.000Z',
          },
        ],
      },
    ],
  ])('rejects the impossible calendar date at %s', async (property, override) => {
    await expect(
      validateCreateActivityDto({ ...canonicalPayload, ...override }),
    ).rejects.toMatchObject({
      name: 'DtoValidationError',
      issues: expect.arrayContaining([
        expect.objectContaining({ property }),
      ]),
    });
  });

  it.each([
    [
      'Dart microseconds with UTC',
      '2026-03-22T10:00:00.123456Z',
      '2026-03-22T10:30:00.123456Z',
    ],
    [
      'legacy offset-less local time',
      '2026-03-22T10:00:00.123456',
      '2026-03-22T10:30:00.123456',
    ],
  ])('accepts %s during the compatibility window', async (_label, start, end) => {
    await expect(
      validateCreateActivityDto({
        ...canonicalPayload,
        startTime: start,
        endTime: end,
        locations: [
          { ...canonicalPayload.locations[0], timestamp: start },
        ],
        statusChanges: [
          { status: 'active', timestamp: start },
          { status: 'completed', timestamp: end },
        ],
      }),
    ).resolves.toBeInstanceOf(CreateActivityDto);
  });

  it.each([
    [
      'locations',
      Array.from({ length: MAX_ACTIVITY_LOCATIONS + 1 }, () =>
        canonicalPayload.locations[0]),
    ],
    [
      'statusChanges',
      Array.from({ length: MAX_ACTIVITY_STATUS_CHANGES + 1 }, () =>
        canonicalPayload.statusChanges[0]),
    ],
  ])('rejects a %s collection over its domain cap', async (property, values) => {
    await expect(
      validateDto(CreateActivityDto, {
        ...canonicalPayload,
        [property]: values,
      }),
    ).rejects.toMatchObject({
      name: 'DtoValidationError',
      issues: expect.arrayContaining([
        expect.objectContaining({ property }),
      ]),
    });
  });
});

describe('UpdateActivityDto presence contract', () => {
  it('accepts omitted and explicitly empty collections', async () => {
    await expect(validateDto(UpdateActivityDto, { name: 'Renamed' }))
      .resolves.toMatchObject({ name: 'Renamed' });
    await expect(
      validateDto(UpdateActivityDto, { locations: [], statusChanges: [] }),
    ).resolves.toMatchObject({ locations: [], statusChanges: [] });
  });

  it.each([
    ['locations', { locations: null }],
    ['statusChanges', { statusChanges: null }],
    ['type', { type: null }],
    ['startTime', { startTime: null }],
    ['distance', { distance: null }],
  ])('rejects null for non-nullable %s', async (_property, payload) => {
    await expect(validateDto(UpdateActivityDto, payload)).rejects.toMatchObject({
      name: 'DtoValidationError',
    });
  });

  it('allows null only for fields that intentionally clear nullable columns', async () => {
    await expect(
      validateDto(UpdateActivityDto, {
        calories: null,
        description: null,
        pausedDuration: null,
        name: null,
        elevationGain: null,
        elevationLoss: null,
      }),
    ).resolves.toMatchObject({
      calories: null,
      description: null,
      pausedDuration: null,
      name: null,
    });
  });
});
