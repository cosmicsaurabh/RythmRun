import 'reflect-metadata';

import {
  ACTIVE_DURATION_TRUNCATION_TOLERANCE_SECONDS,
  ActivityDomainValidationError,
  MAX_ACTIVITY_DOMAIN_ISSUES,
  MAX_ACTIVITY_WALL_SECONDS,
  validateActivityCreate,
  validateMergedActivityUpdate,
} from '../models/activity-domain-validation';
import {
  CreateActivityDto,
  CURRENT_METRICS_VERSION,
  LEGACY_METRICS_VERSION,
} from '../models/dto/activity.dto';

const startTime = new Date('2026-03-22T10:00:00.000Z');
const endTime = new Date('2026-03-22T10:10:00.000Z');
const earthRadiusMeters = 6_371_000;

function latitudeDeltaForMeters(metres: number): number {
  return metres / earthRadiusMeters * 180 / Math.PI;
}

function canonicalRouteLocations() {
  const offsets: number[] = [
    ...Array.from({ length: 16 }, (_, index) => index * 20),
    ...Array.from({ length: 13 }, (_, index) => 360 + index * 20),
  ];
  let latitude = 28.6139;

  return offsets.map((offset, index) => {
    if (index > 0 && offset !== 360) {
      latitude += latitudeDeltaForMeters(100);
    }
    return {
      latitude,
      longitude: 77.209,
      timestamp: new Date(startTime.getTime() + offset * 1000).toISOString(),
      accuracy: 5,
      speed: 5,
    };
  });
}

function canonicalCreate(
  overrides: Partial<CreateActivityDto> = {},
): CreateActivityDto {
  return {
    clientSyncId: 'rr-domain-validation',
    metricsVersion: CURRENT_METRICS_VERSION,
    type: 'running',
    startTime: startTime.toISOString(),
    endTime: endTime.toISOString(),
    distance: 2700,
    duration: 540,
    pausedDuration: 60,
    avgSpeed: 5,
    maxSpeed: 6,
    locations: canonicalRouteLocations(),
    statusChanges: [
      { status: 'active', timestamp: startTime.toISOString() },
      {
        status: 'paused',
        timestamp: new Date(startTime.getTime() + 300_000).toISOString(),
      },
      {
        status: 'active',
        timestamp: new Date(startTime.getTime() + 360_000).toISOString(),
      },
      { status: 'completed', timestamp: endTime.toISOString() },
    ],
    ...overrides,
  };
}

function captureIssues(callback: () => void) {
  try {
    callback();
  } catch (error) {
    expect(error).toBeInstanceOf(ActivityDomainValidationError);
    return (error as ActivityDomainValidationError).issues;
  }
  throw new Error('Expected activity domain validation to fail');
}

describe('activity domain validation', () => {
  it('accepts a complete canonical create fixture', () => {
    expect(() => validateActivityCreate(canonicalCreate())).not.toThrow();
  });

  it('accepts a representative three-hour canonical route with 6,000 points', () => {
    const wallSeconds = 3 * 60 * 60;
    const pointCount = 6000;
    const locations = Array.from({ length: pointCount }, (_, index) => ({
      latitude: 28.6139 + index * latitudeDeltaForMeters(1),
      longitude: 77.209,
      timestamp: new Date(
        startTime.getTime() +
          Math.floor((index * wallSeconds * 1000) / (pointCount - 1)),
      ).toISOString(),
      accuracy: 5,
      speed: 1,
    }));
    const multiHour = canonicalCreate({
      endTime: new Date(startTime.getTime() + wallSeconds * 1000).toISOString(),
      distance: pointCount - 1,
      duration: wallSeconds,
      pausedDuration: 0,
      avgSpeed: (pointCount - 1) / wallSeconds,
      maxSpeed: 2,
      locations,
      statusChanges: [
        { status: 'active', timestamp: startTime.toISOString() },
        {
          status: 'completed',
          timestamp: new Date(
            startTime.getTime() + wallSeconds * 1000,
          ).toISOString(),
        },
      ],
    });

    expect(() => validateActivityCreate(multiHour)).not.toThrow();
  });

  it('allows one second for independent Dart Duration truncation', () => {
    const start = new Date('2026-03-22T10:00:00.900Z');
    const end = new Date('2026-03-22T10:00:10.800Z');
    const dto = canonicalCreate({
      metricsVersion: LEGACY_METRICS_VERSION,
      startTime: start.toISOString(),
      endTime: end.toISOString(),
      duration: 4,
      pausedDuration: 4,
      locations: [],
      statusChanges: undefined,
    });

    expect(ACTIVE_DURATION_TRUNCATION_TOLERANCE_SECONDS).toBe(1);
    expect(() => validateActivityCreate(dto)).not.toThrow();

    const issues = captureIssues(() =>
      validateActivityCreate({ ...dto, duration: 3 }),
    );
    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'ACTIVITY_DURATION_INVALID' }),
      ]),
    );
  });

  it('rejects a workout window longer than seven days', () => {
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          metricsVersion: LEGACY_METRICS_VERSION,
          endTime: new Date(
            startTime.getTime() + (MAX_ACTIVITY_WALL_SECONDS + 1) * 1000,
          ).toISOString(),
          duration: MAX_ACTIVITY_WALL_SECONDS + 1,
          pausedDuration: 0,
          locations: [],
          statusChanges: undefined,
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_WINDOW_TOO_LONG',
          property: 'endTime',
        }),
      ]),
    );
  });

  it('uses the compatibility speed tolerance and enforces average <= maximum', () => {
    expect(() =>
      validateActivityCreate(canonicalCreate({ avgSpeed: 5.049 })),
    ).not.toThrow();

    const mismatch = captureIssues(() =>
      validateActivityCreate(canonicalCreate({ avgSpeed: 5.101 })),
    );
    expect(mismatch).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'ACTIVITY_AVERAGE_SPEED_INVALID' }),
      ]),
    );

    const overMaximum = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({ avgSpeed: 5, maxSpeed: 4.99 }),
      ),
    );
    expect(overMaximum).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_AVERAGE_SPEED_EXCEEDS_MAX',
        }),
      ]),
    );

    const overTypeLimit = captureIssues(() =>
      validateActivityCreate(canonicalCreate({ maxSpeed: 10.001 })),
    );
    expect(overTypeLimit).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_GPS_SPEED_INVALID',
          property: 'maxSpeed',
        }),
      ]),
    );
  });

  it.each([
    ['walking', 5],
    ['hiking', 5],
    ['running', 10],
    ['cycling', 30],
  ])('enforces the %s canonical speed ceiling', (type, maximumSpeed) => {
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({ type, maxSpeed: maximumSpeed + 0.001 }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_GPS_SPEED_INVALID',
          property: 'maxSpeed',
        }),
      ]),
    );
  });

  it('rejects unordered and out-of-window nested timestamps', () => {
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          locations: [
            {
              latitude: 28.6139,
              longitude: 77.209,
              timestamp: new Date(startTime.getTime() + 120_000).toISOString(),
              accuracy: 5,
            },
            {
              latitude: 28.614,
              longitude: 77.21,
              timestamp: new Date(startTime.getTime() - 1).toISOString(),
              accuracy: 5,
            },
          ],
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW',
          property: 'locations[1].timestamp',
        }),
        expect.objectContaining({
          code: 'ACTIVITY_TIMESTAMPS_UNORDERED',
          property: 'locations[1].timestamp',
        }),
      ]),
    );
  });

  it.each([
    [
      'missing accuracy',
      { accuracy: undefined },
      'ACTIVITY_GPS_ACCURACY_INVALID',
    ],
    [
      'accuracy over 50m',
      { accuracy: 50.001 },
      'ACTIVITY_GPS_ACCURACY_INVALID',
    ],
    [
      'zero coordinate sentinel',
      { latitude: 0, longitude: 0 },
      'ACTIVITY_GPS_ZERO_COORDINATE',
    ],
    [
      'reported speed over the type limit',
      { speed: 10.001 },
      'ACTIVITY_GPS_SPEED_INVALID',
    ],
  ])('rejects canonical GPS input with %s', (_label, patch, issueCode) => {
    const firstLocation = canonicalCreate().locations[0];
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          locations: [{ ...firstLocation, ...patch }],
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: issueCode })]),
    );
  });

  it('rejects a canonical route jump above the type-specific implied speed', () => {
    const first = canonicalCreate().locations[0];
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          locations: [
            first,
            {
              ...first,
              longitude: first.longitude + 1,
              timestamp: new Date(startTime.getTime() + 10_000).toISOString(),
            },
          ],
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_GPS_IMPLIED_SPEED_INVALID',
          property: 'locations[1].timestamp',
        }),
      ]),
    );
  });

  it('rejects canonical summary distance and max speed below its route', () => {
    const distanceIssues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({ distance: 0, avgSpeed: 0 }),
      ),
    );
    expect(distanceIssues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_ROUTE_DISTANCE_INVALID',
          property: 'distance',
        }),
      ]),
    );

    const speedIssues = captureIssues(() =>
      validateActivityCreate(canonicalCreate({ maxSpeed: 4.8 })),
    );
    expect(speedIssues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_ROUTE_MAX_SPEED_INVALID',
          property: 'maxSpeed',
        }),
      ]),
    );
  });

  it('caps semantic issue collection for a maximum-size invalid route', () => {
    const locations = Array.from({ length: 12_000 }, (_, index) => ({
      latitude: 28.6139,
      longitude: 77.209,
      timestamp: new Date(startTime.getTime() + index * 40).toISOString(),
      accuracy: 51,
      speed: 0,
    }));

    try {
      validateActivityCreate(canonicalCreate({ locations }));
      throw new Error('Expected the invalid route to be rejected');
    } catch (error) {
      expect(error).toBeInstanceOf(ActivityDomainValidationError);
      const validationError = error as ActivityDomainValidationError;
      expect(validationError.issues).toHaveLength(
        MAX_ACTIVITY_DOMAIN_ISSUES,
      );
      expect(validationError.issuesTruncated).toBe(true);
      expect(
        Buffer.byteLength(JSON.stringify(validationError.issues)),
      ).toBeLessThan(16 * 1024);
    }
  });

  it('validates canonical status transitions and paused duration', () => {
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          pausedDuration: 10,
          duration: 590,
          statusChanges: [
            { status: 'active', timestamp: startTime.toISOString() },
            {
              status: 'active',
              timestamp: new Date(startTime.getTime() + 300_000).toISOString(),
            },
            { status: 'completed', timestamp: endTime.toISOString() },
          ],
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'ACTIVITY_STATUS_SEQUENCE_INVALID' }),
        expect.objectContaining({ code: 'ACTIVITY_PAUSED_DURATION_INVALID' }),
      ]),
    );
  });

  it('allows omitted or cleared status history while retaining aggregate pause time', () => {
    expect(() =>
      validateActivityCreate(canonicalCreate({ statusChanges: undefined })),
    ).not.toThrow();
    expect(() =>
      validateActivityCreate(canonicalCreate({ statusChanges: [] })),
    ).not.toThrow();
  });

  it('clears short-pause history without reinterpreting the preserved route bridge', () => {
    const shortStart = new Date('2026-03-22T10:00:00.000Z');
    const shortEnd = new Date(shortStart.getTime() + 30_000);
    const existing = {
      metricsVersion: CURRENT_METRICS_VERSION,
      type: 'running',
      startTime: shortStart,
      endTime: shortEnd,
      distance: 0,
      duration: 20,
      pausedDuration: 10,
      avgSpeed: 0,
      maxSpeed: 0,
      locations: [
        {
          latitude: 28.6139,
          longitude: 77.209,
          timestamp: new Date(shortStart.getTime() + 9_000),
          accuracy: 5,
          speed: 0,
        },
        {
          latitude: 28.6139,
          longitude: 78.209,
          timestamp: new Date(shortStart.getTime() + 20_000),
          accuracy: 5,
          speed: 0,
        },
      ],
      statusChanges: [
        { status: 'active', timestamp: shortStart },
        {
          status: 'paused',
          timestamp: new Date(shortStart.getTime() + 10_000),
        },
        {
          status: 'active',
          timestamp: new Date(shortStart.getTime() + 20_000),
        },
        { status: 'completed', timestamp: shortEnd },
      ],
    };

    expect(() =>
      validateMergedActivityUpdate(existing, { statusChanges: [] }),
    ).not.toThrow();

    expect(() =>
      validateMergedActivityUpdate(
        { ...existing, statusChanges: [] },
        { maxSpeed: 0 },
      ),
    ).not.toThrow();
  });

  it('rejects canonical route locations that occur in a paused window', () => {
    const issues = captureIssues(() =>
      validateActivityCreate(
        canonicalCreate({
          locations: [
            canonicalCreate().locations[0],
            {
              latitude: 28.614,
              longitude: 77.2091,
              timestamp: new Date(startTime.getTime() + 330_000).toISOString(),
              accuracy: 5,
              speed: 0,
            },
          ],
        }),
      ),
    );

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          code: 'ACTIVITY_LOCATION_DURING_PAUSE',
          property: 'locations[1].timestamp',
        }),
      ]),
    );
  });

  it('resets implied-speed comparison across a short paused interval', () => {
    const pauseAt = new Date(startTime.getTime() + 300_000);
    const resumeAt = new Date(startTime.getTime() + 310_000);
    const dto = canonicalCreate({
      distance: 0,
      duration: 590,
      pausedDuration: 10,
      avgSpeed: 0,
      maxSpeed: 0,
      locations: [
        {
          latitude: 28.6139,
          longitude: 77.209,
          timestamp: new Date(pauseAt.getTime() - 1_000).toISOString(),
          accuracy: 5,
          speed: 0,
        },
        {
          latitude: 28.6139,
          longitude: 78.209,
          timestamp: resumeAt.toISOString(),
          accuracy: 5,
          speed: 0,
        },
      ],
      statusChanges: [
        { status: 'active', timestamp: startTime.toISOString() },
        { status: 'paused', timestamp: pauseAt.toISOString() },
        { status: 'active', timestamp: resumeAt.toISOString() },
        { status: 'completed', timestamp: endTime.toISOString() },
      ],
    });

    expect(() => validateActivityCreate(dto)).not.toThrow();
  });

  it('merges relevant PATCH fields while ignoring unrelated legacy defects', () => {
    const legacy = {
      metricsVersion: LEGACY_METRICS_VERSION,
      type: 'running',
      startTime,
      endTime,
      distance: 2700,
      duration: 600,
      avgSpeed: 16.2,
      maxSpeed: 6,
      pausedDuration: 60,
      locations: [
        {
          latitude: 28.6139,
          longitude: 77.209,
          accuracy: null,
          timestamp: new Date(startTime.getTime() - 1),
        },
      ],
      statusChanges: [
        { status: 'completed', timestamp: endTime },
        { status: 'active', timestamp: startTime },
      ],
    };

    expect(() =>
      validateMergedActivityUpdate(legacy, { name: 'metadata only' }),
    ).not.toThrow();

    const issues = captureIssues(() =>
      validateMergedActivityUpdate(legacy, {
        startTime: new Date(startTime.getTime() + 1_000).toISOString(),
        duration: 539,
      }),
    );
    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW' }),
        expect.objectContaining({ code: 'ACTIVITY_TIMESTAMPS_UNORDERED' }),
      ]),
    );
  });
});
