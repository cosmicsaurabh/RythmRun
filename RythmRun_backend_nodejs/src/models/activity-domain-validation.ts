import {
  CreateActivityDto,
  CURRENT_METRICS_VERSION,
  UpdateActivityDto,
} from './dto/activity.dto';

export const ACTIVE_DURATION_TRUNCATION_TOLERANCE_SECONDS = 1;
export const MAX_ACTIVITY_WALL_SECONDS = 7 * 24 * 60 * 60;

const AVERAGE_SPEED_ABSOLUTE_TOLERANCE = 0.05;
const AVERAGE_SPEED_RELATIVE_TOLERANCE = 0.02;
const ROUTE_DISTANCE_ABSOLUTE_TOLERANCE_METERS = 5;
const ROUTE_DISTANCE_RELATIVE_TOLERANCE = 0.02;
const MAXIMUM_HORIZONTAL_ACCURACY_METERS = 50;
const ACTIVE_ANCHOR_RESET_GAP_SECONDS = 30;
const EARTH_RADIUS_METERS = 6_371_000;

const MAXIMUM_SPEED_BY_TYPE: Readonly<Record<string, number>> = {
  running: 10,
  walking: 5,
  hiking: 5,
  cycling: 30,
};

export type ActivityDomainIssueCode =
  | 'ACTIVITY_INTERVAL_INVALID'
  | 'ACTIVITY_WINDOW_TOO_LONG'
  | 'ACTIVITY_DURATION_INVALID'
  | 'ACTIVITY_AVERAGE_SPEED_INVALID'
  | 'ACTIVITY_AVERAGE_SPEED_EXCEEDS_MAX'
  | 'ACTIVITY_ROUTE_DISTANCE_INVALID'
  | 'ACTIVITY_ROUTE_MAX_SPEED_INVALID'
  | 'ACTIVITY_TIMESTAMP_INVALID'
  | 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW'
  | 'ACTIVITY_TIMESTAMPS_UNORDERED'
  | 'ACTIVITY_GPS_ACCURACY_INVALID'
  | 'ACTIVITY_GPS_ZERO_COORDINATE'
  | 'ACTIVITY_GPS_SPEED_INVALID'
  | 'ACTIVITY_GPS_IMPLIED_SPEED_INVALID'
  | 'ACTIVITY_STATUS_SEQUENCE_INVALID'
  | 'ACTIVITY_PAUSED_DURATION_INVALID'
  | 'ACTIVITY_LOCATION_DURING_PAUSE';

export interface ActivityDomainIssue {
  code: ActivityDomainIssueCode;
  property: string;
  message: string;
}

export const MAX_ACTIVITY_DOMAIN_ISSUES = 25;

class BoundedActivityIssueList extends Array<ActivityDomainIssue> {
  issuesTruncated = false;

  override push(...items: ActivityDomainIssue[]): number {
    const remaining = Math.max(0, MAX_ACTIVITY_DOMAIN_ISSUES - this.length);
    if (items.length > remaining) {
      this.issuesTruncated = true;
    }
    return super.push(...items.slice(0, remaining));
  }
}

interface TimestampValue {
  timestamp: Date | string;
}

interface LocationValue extends TimestampValue {
  latitude?: number;
  longitude?: number;
  accuracy?: number | null;
  speed?: number | null;
}

interface StatusChangeValue extends TimestampValue {
  status?: string;
}

export interface PersistedActivityForUpdate {
  metricsVersion: number;
  type: string;
  startTime: Date;
  endTime: Date;
  distance: number;
  duration: number;
  avgSpeed: number;
  maxSpeed: number;
  pausedDuration: number | null;
  locations?: readonly LocationValue[];
  statusChanges?: readonly StatusChangeValue[];
}

type NullablePausedDurationUpdate = UpdateActivityDto & {
  pausedDuration?: number | null;
};

interface ActivityDomainState {
  metricsVersion: number;
  type: string;
  startTime: Date;
  endTime: Date;
  distance: number;
  duration: number;
  avgSpeed: number;
  maxSpeed: number;
  pausedDuration: number;
  locations?: readonly LocationValue[];
  statusChanges?: readonly StatusChangeValue[];
  routeStatusChanges?: readonly StatusChangeValue[];
}

interface ValidationScope {
  timeline: boolean;
  metrics: boolean;
  locations: boolean;
  statusChanges: boolean;
}

interface PauseWindow {
  start: number;
  end: number;
}

interface CanonicalRouteMetrics {
  distance: number;
  maximumImpliedSpeed: number;
}

export class ActivityDomainValidationError extends Error {
  readonly code = 'ACTIVITY_DOMAIN_INVALID';
  readonly statusCode = 422;
  readonly retryable = false;

  constructor(
    readonly issues: readonly ActivityDomainIssue[],
    readonly issuesTruncated = false,
  ) {
    super('Activity payload is invalid');
    this.name = 'ActivityDomainValidationError';
    Object.setPrototypeOf(this, ActivityDomainValidationError.prototype);
  }
}

export function validateActivityCreate(dto: CreateActivityDto): void {
  validateActivityState(
    {
      metricsVersion: dto.metricsVersion ?? 1,
      type: dto.type,
      startTime: new Date(dto.startTime),
      endTime: new Date(dto.endTime),
      distance: dto.distance,
      duration: dto.duration,
      avgSpeed: dto.avgSpeed,
      maxSpeed: dto.maxSpeed,
      pausedDuration: dto.pausedDuration ?? 0,
      locations: dto.locations,
      statusChanges: dto.statusChanges,
      routeStatusChanges: dto.statusChanges,
    },
    {
      timeline: true,
      metrics: true,
      locations: true,
      statusChanges: dto.statusChanges !== undefined,
    },
  );
}

export function validateMergedActivityUpdate(
  existing: PersistedActivityForUpdate,
  dto: UpdateActivityDto,
): void {
  const nullableDto = dto as NullablePausedDurationUpdate;
  const windowChanged =
    dto.startTime !== undefined || dto.endTime !== undefined;
  const timingChanged =
    windowChanged ||
    dto.duration !== undefined ||
    nullableDto.pausedDuration !== undefined;
  const metricsChanged =
    dto.distance !== undefined ||
    dto.duration !== undefined ||
    dto.avgSpeed !== undefined ||
    dto.maxSpeed !== undefined ||
    dto.type !== undefined;
  const locationsChanged = dto.locations !== undefined;
  const statusChangesChanged = dto.statusChanges !== undefined;
  const typeChanged = dto.type !== undefined;
  const canonicalPolicyApplies =
    existing.metricsVersion === CURRENT_METRICS_VERSION;
  const needsLocationsForCanonicalStatus =
    canonicalPolicyApplies && statusChangesChanged;
  const needsStatusesForCanonicalLocations =
    canonicalPolicyApplies && locationsChanged;
  const validateLocations =
    locationsChanged ||
    windowChanged ||
    needsLocationsForCanonicalStatus ||
    (canonicalPolicyApplies && (typeChanged || metricsChanged));
  const validateStatusChanges =
    statusChangesChanged ||
    windowChanged ||
    nullableDto.pausedDuration !== undefined ||
    needsStatusesForCanonicalLocations ||
    (canonicalPolicyApplies && (typeChanged || metricsChanged));

  const locations = locationsChanged
    ? dto.locations
    : validateLocations
      ? existing.locations ?? []
      : undefined;
  const statusChanges = statusChangesChanged
    ? dto.statusChanges
    : validateStatusChanges
      ? existing.statusChanges ?? []
      : undefined;
  const routeStatusChanges =
    canonicalPolicyApplies &&
    statusChangesChanged &&
    dto.statusChanges?.length === 0 &&
    !locationsChanged
      ? existing.statusChanges ?? []
      : statusChanges;

  validateActivityState(
    {
      metricsVersion: existing.metricsVersion,
      type: dto.type ?? existing.type,
      startTime:
        dto.startTime === undefined
          ? existing.startTime
          : new Date(dto.startTime),
      endTime:
        dto.endTime === undefined ? existing.endTime : new Date(dto.endTime),
      distance: dto.distance ?? existing.distance,
      duration: dto.duration ?? existing.duration,
      avgSpeed: dto.avgSpeed ?? existing.avgSpeed,
      maxSpeed: dto.maxSpeed ?? existing.maxSpeed,
      pausedDuration:
        nullableDto.pausedDuration === undefined
          ? existing.pausedDuration ?? 0
          : nullableDto.pausedDuration ?? 0,
      locations,
      statusChanges,
      routeStatusChanges,
    },
    {
      timeline:
        timingChanged ||
        (locations?.length ?? 0) > 0 ||
        (statusChanges?.length ?? 0) > 0,
      metrics: metricsChanged,
      locations: validateLocations,
      statusChanges: validateStatusChanges,
    },
  );
}

function validateActivityState(
  state: ActivityDomainState,
  scope: ValidationScope,
): void {
  const issues = new BoundedActivityIssueList();
  const start = state.startTime.getTime();
  const end = state.endTime.getTime();
  const hasValidInterval =
    Number.isFinite(start) && Number.isFinite(end) && end > start;

  if (scope.timeline && !hasValidInterval) {
    issues.push({
      code: 'ACTIVITY_INTERVAL_INVALID',
      property: 'endTime',
      message: 'End time must be after start time',
    });
  }

  if (scope.timeline && hasValidInterval) {
    const wallSeconds = Math.floor((end - start) / 1000);

    if (end - start > MAX_ACTIVITY_WALL_SECONDS * 1000) {
      issues.push({
        code: 'ACTIVITY_WINDOW_TOO_LONG',
        property: 'endTime',
        message: 'Workout window cannot exceed seven days',
      });
    }

    const representedSeconds = state.duration + state.pausedDuration;
    if (
      !Number.isFinite(representedSeconds) ||
      Math.abs(representedSeconds - wallSeconds) >
        ACTIVE_DURATION_TRUNCATION_TOLERANCE_SECONDS
    ) {
      issues.push({
        code: 'ACTIVITY_DURATION_INVALID',
        property: 'duration',
        message: 'Active and paused duration must match the workout window',
      });
    }
  }

  if (
    scope.metrics &&
    state.metricsVersion === CURRENT_METRICS_VERSION
  ) {
    validateCanonicalMetrics(state, issues);
  }

  if (scope.locations && state.locations !== undefined && hasValidInterval) {
    validateTimestamps(
      state.locations,
      'locations',
      state.startTime,
      state.endTime,
      state.metricsVersion === CURRENT_METRICS_VERSION,
      issues,
    );
  }

  if (
    scope.statusChanges &&
    state.statusChanges !== undefined &&
    hasValidInterval
  ) {
    validateTimestamps(
      state.statusChanges,
      'statusChanges',
      state.startTime,
      state.endTime,
      false,
      issues,
    );
  }

  let pauseWindows: readonly PauseWindow[] = [];
  if (
    state.metricsVersion === CURRENT_METRICS_VERSION &&
    scope.statusChanges &&
    hasValidInterval
  ) {
    if ((state.statusChanges?.length ?? 0) > 0) {
      pauseWindows = validateCanonicalStatusChanges(state, issues);
    }
  }

  if (
    state.metricsVersion === CURRENT_METRICS_VERSION &&
    state.routeStatusChanges !== state.statusChanges
  ) {
    pauseWindows = derivePauseWindows(state.routeStatusChanges ?? []);
  }

  let routeMetrics: CanonicalRouteMetrics | undefined;
  if (
    state.metricsVersion === CURRENT_METRICS_VERSION &&
    scope.locations &&
    state.locations !== undefined
  ) {
    routeMetrics = validateCanonicalLocations(
      state,
      pauseWindows,
      (state.routeStatusChanges?.length ?? 0) > 0,
      issues,
    );
  }

  if (
    routeMetrics !== undefined &&
    (state.locations?.length ?? 0) >= 2
  ) {
    validateCanonicalRouteSummary(state, routeMetrics, issues);
  }

  if (issues.length > 0) {
    throw new ActivityDomainValidationError(issues, issues.issuesTruncated);
  }
}

function validateCanonicalMetrics(
  state: ActivityDomainState,
  issues: ActivityDomainIssue[],
): void {
  const expectedAverageSpeed =
    state.duration > 0
      ? state.distance / state.duration
      : state.distance === 0
        ? 0
        : Number.NaN;

  if (
    !Number.isFinite(expectedAverageSpeed) ||
    !approximatelyEqualAverageSpeed(state.avgSpeed, expectedAverageSpeed)
  ) {
    issues.push({
      code: 'ACTIVITY_AVERAGE_SPEED_INVALID',
      property: 'avgSpeed',
      message: 'Average speed must match distance divided by active duration',
    });
  }

  if (
    !Number.isFinite(state.avgSpeed) ||
    !Number.isFinite(state.maxSpeed) ||
    state.avgSpeed > state.maxSpeed
  ) {
    issues.push({
      code: 'ACTIVITY_AVERAGE_SPEED_EXCEEDS_MAX',
      property: 'avgSpeed',
      message: 'Average speed cannot exceed maximum speed',
    });
  }

  const workoutTypeMaximum = MAXIMUM_SPEED_BY_TYPE[state.type];
  if (
    workoutTypeMaximum !== undefined &&
    state.maxSpeed > workoutTypeMaximum
  ) {
    issues.push({
      code: 'ACTIVITY_GPS_SPEED_INVALID',
      property: 'maxSpeed',
      message: 'Maximum speed exceeds the workout-type limit',
    });
  }
}

function validateTimestamps(
  values: readonly TimestampValue[],
  property: 'locations' | 'statusChanges',
  startTime: Date,
  endTime: Date,
  strictlyIncreasing: boolean,
  issues: ActivityDomainIssue[],
): void {
  let previousTimestamp: number | undefined;

  values.forEach((value, index) => {
    const timestamp = toTimestamp(value.timestamp);
    const itemProperty = `${property}[${index}].timestamp`;

    if (!Number.isFinite(timestamp)) {
      issues.push({
        code: 'ACTIVITY_TIMESTAMP_INVALID',
        property: itemProperty,
        message: 'Timestamp must be a valid ISO-8601 date',
      });
      return;
    }

    if (timestamp < startTime.getTime() || timestamp > endTime.getTime()) {
      issues.push({
        code: 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW',
        property: itemProperty,
        message: 'Timestamp must be inside the workout window',
      });
    }

    if (
      previousTimestamp !== undefined &&
      (strictlyIncreasing
        ? timestamp <= previousTimestamp
        : timestamp < previousTimestamp)
    ) {
      issues.push({
        code: 'ACTIVITY_TIMESTAMPS_UNORDERED',
        property: itemProperty,
        message: strictlyIncreasing
          ? 'Timestamps must be strictly increasing'
          : 'Timestamps must be in chronological order',
      });
    }

    previousTimestamp = timestamp;
  });
}

function validateCanonicalLocations(
  state: ActivityDomainState,
  pauseWindows: readonly PauseWindow[],
  reconcileRoute: boolean,
  issues: ActivityDomainIssue[],
): CanonicalRouteMetrics | undefined {
  const locations = state.locations ?? [];
  const maximumSpeed = MAXIMUM_SPEED_BY_TYPE[state.type];
  let previousLocation: LocationValue | undefined;
  let containingPauseIndex = 0;
  let crossedPauseIndex = 0;
  let routeDistance = 0;
  let maximumImpliedSpeed = 0;

  locations.forEach((location, index) => {
    const property = `locations[${index}]`;
    const accuracy = location.accuracy;

    if (
      accuracy === undefined ||
      accuracy === null ||
      !Number.isFinite(accuracy) ||
      accuracy < 0 ||
      accuracy > MAXIMUM_HORIZONTAL_ACCURACY_METERS
    ) {
      issues.push({
        code: 'ACTIVITY_GPS_ACCURACY_INVALID',
        property: `${property}.accuracy`,
        message: 'Location accuracy must be between 0 and 50 metres',
      });
    }

    if (location.latitude === 0 && location.longitude === 0) {
      issues.push({
        code: 'ACTIVITY_GPS_ZERO_COORDINATE',
        property: `${property}.latitude`,
        message: 'The zero-coordinate sentinel is not a valid location',
      });
    }

    if (
      maximumSpeed !== undefined &&
      location.speed !== undefined &&
      location.speed !== null &&
      (!Number.isFinite(location.speed) ||
        location.speed < 0 ||
        location.speed > maximumSpeed)
    ) {
      issues.push({
        code: 'ACTIVITY_GPS_SPEED_INVALID',
        property: `${property}.speed`,
        message: 'Reported speed exceeds the workout-type limit',
      });
    }

    const timestamp = toTimestamp(location.timestamp);
    while (
      containingPauseIndex < pauseWindows.length &&
      timestamp >= pauseWindows[containingPauseIndex].end
    ) {
      containingPauseIndex += 1;
    }
    const containingPause = pauseWindows[containingPauseIndex];
    if (
      Number.isFinite(timestamp) &&
      containingPause !== undefined &&
      // A sample exactly at the pause boundary was accepted immediately
      // before that transition; a sample at resume starts the new segment.
      timestamp > containingPause.start &&
      timestamp < containingPause.end
    ) {
      issues.push({
        code: 'ACTIVITY_LOCATION_DURING_PAUSE',
        property: `${property}.timestamp`,
        message: 'Route locations cannot occur during a paused interval',
      });
    }

    if (
      reconcileRoute &&
      previousLocation !== undefined &&
      maximumSpeed !== undefined
    ) {
      const previousTimestamp = toTimestamp(previousLocation.timestamp);
      const deltaSeconds = (timestamp - previousTimestamp) / 1000;
      while (
        crossedPauseIndex < pauseWindows.length &&
        pauseWindows[crossedPauseIndex].start < previousTimestamp
      ) {
        crossedPauseIndex += 1;
      }
      const nextPause = pauseWindows[crossedPauseIndex];
      const crossesPauseBoundary =
        nextPause !== undefined && nextPause.start < timestamp;
      if (
        Number.isFinite(deltaSeconds) &&
        deltaSeconds > 0 &&
        deltaSeconds <= ACTIVE_ANCHOR_RESET_GAP_SECONDS &&
        !crossesPauseBoundary &&
        hasCoordinates(previousLocation) &&
        hasCoordinates(location)
      ) {
        const impliedSpeed =
          haversineDistanceMeters(previousLocation, location) / deltaSeconds;
        if (Number.isFinite(impliedSpeed)) {
          routeDistance += impliedSpeed * deltaSeconds;
          maximumImpliedSpeed = Math.max(maximumImpliedSpeed, impliedSpeed);
        }
        if (!Number.isFinite(impliedSpeed) || impliedSpeed > maximumSpeed) {
          issues.push({
            code: 'ACTIVITY_GPS_IMPLIED_SPEED_INVALID',
            property: `${property}.timestamp`,
            message: 'Implied speed exceeds the workout-type limit',
          });
        }
      }
    }

    previousLocation = location;
  });

  return reconcileRoute
    ? { distance: routeDistance, maximumImpliedSpeed }
    : undefined;
}

function validateCanonicalRouteSummary(
  state: ActivityDomainState,
  route: CanonicalRouteMetrics,
  issues: ActivityDomainIssue[],
): void {
  const distanceTolerance = Math.max(
    ROUTE_DISTANCE_ABSOLUTE_TOLERANCE_METERS,
    Math.abs(route.distance) * ROUTE_DISTANCE_RELATIVE_TOLERANCE,
  );
  if (Math.abs(state.distance - route.distance) > distanceTolerance) {
    issues.push({
      code: 'ACTIVITY_ROUTE_DISTANCE_INVALID',
      property: 'distance',
      message: 'Distance must match the contributing canonical route segments',
    });
  }

  const speedTolerance = Math.max(
    AVERAGE_SPEED_ABSOLUTE_TOLERANCE,
    Math.abs(route.maximumImpliedSpeed) * AVERAGE_SPEED_RELATIVE_TOLERANCE,
  );
  if (state.maxSpeed + speedTolerance < route.maximumImpliedSpeed) {
    issues.push({
      code: 'ACTIVITY_ROUTE_MAX_SPEED_INVALID',
      property: 'maxSpeed',
      message: 'Maximum speed must cover the canonical route maximum',
    });
  }
}

function validateCanonicalStatusChanges(
  state: ActivityDomainState,
  issues: ActivityDomainIssue[],
): readonly PauseWindow[] {
  const statuses = state.statusChanges ?? [];
  const pauseWindows: PauseWindow[] = [];
  let previousStatus: string | undefined;
  let openPause: number | undefined;

  statuses.forEach((change, index) => {
    const property = `statusChanges[${index}].status`;
    const timestamp = toTimestamp(change.timestamp);
    const status = change.status;

    if (index === 0 && status !== 'active') {
      issues.push({
        code: 'ACTIVITY_STATUS_SEQUENCE_INVALID',
        property,
        message: 'The first status change must start the workout as active',
      });
    }

    if (index === 0 && timestamp !== state.startTime.getTime()) {
      issues.push({
        code: 'ACTIVITY_STATUS_SEQUENCE_INVALID',
        property: `statusChanges[${index}].timestamp`,
        message: 'The first active status must match the workout start time',
      });
    }

    if (previousStatus !== undefined && !isAllowedTransition(previousStatus, status)) {
      issues.push({
        code: 'ACTIVITY_STATUS_SEQUENCE_INVALID',
        property,
        message: 'Status changes must follow the active/paused lifecycle',
      });
    }

    if (status === 'paused' && Number.isFinite(timestamp)) {
      openPause = timestamp;
    } else if (
      openPause !== undefined &&
      (status === 'active' || status === 'completed') &&
      Number.isFinite(timestamp)
    ) {
      pauseWindows.push({ start: openPause, end: timestamp });
      openPause = undefined;
    }

    previousStatus = status;
  });

  const finalStatus = statuses[statuses.length - 1];
  if (
    finalStatus?.status !== 'completed' ||
    toTimestamp(finalStatus.timestamp) !== state.endTime.getTime()
  ) {
    issues.push({
      code: 'ACTIVITY_STATUS_SEQUENCE_INVALID',
      property: `statusChanges[${Math.max(0, statuses.length - 1)}]`,
      message: 'The final status must complete the workout at its end time',
    });
  }

  const pausedSeconds = Math.floor(
    pauseWindows.reduce((total, pause) => total + pause.end - pause.start, 0) /
      1000,
  );
  if (
    Math.abs(pausedSeconds - state.pausedDuration) >
    ACTIVE_DURATION_TRUNCATION_TOLERANCE_SECONDS
  ) {
    issues.push({
      code: 'ACTIVITY_PAUSED_DURATION_INVALID',
      property: 'pausedDuration',
      message: 'Paused duration must match the status-change timeline',
    });
  }

  return pauseWindows;
}

function derivePauseWindows(
  statuses: readonly StatusChangeValue[],
): readonly PauseWindow[] {
  const pauseWindows: PauseWindow[] = [];
  let openPause: number | undefined;

  for (const change of statuses) {
    const timestamp = toTimestamp(change.timestamp);
    if (!Number.isFinite(timestamp)) {
      continue;
    }
    if (change.status === 'paused') {
      openPause = timestamp;
    } else if (
      openPause !== undefined &&
      (change.status === 'active' || change.status === 'completed')
    ) {
      pauseWindows.push({ start: openPause, end: timestamp });
      openPause = undefined;
    }
  }

  return pauseWindows;
}

function isAllowedTransition(
  from: string,
  to: string | undefined,
): boolean {
  if (from === 'active') {
    return to === 'paused' || to === 'completed';
  }
  if (from === 'paused') {
    return to === 'active' || to === 'completed';
  }
  return false;
}

function approximatelyEqualAverageSpeed(
  actual: number,
  expected: number,
): boolean {
  const tolerance = Math.max(
    AVERAGE_SPEED_ABSOLUTE_TOLERANCE,
    Math.abs(expected) * AVERAGE_SPEED_RELATIVE_TOLERANCE,
  );
  return Number.isFinite(actual) && Math.abs(actual - expected) <= tolerance;
}

function toTimestamp(value: Date | string): number {
  return value instanceof Date ? value.getTime() : new Date(value).getTime();
}

function hasCoordinates(
  location: LocationValue,
): location is LocationValue & { latitude: number; longitude: number } {
  return (
    location.latitude !== undefined &&
    location.longitude !== undefined &&
    Number.isFinite(location.latitude) &&
    Number.isFinite(location.longitude)
  );
}

function haversineDistanceMeters(
  first: LocationValue & { latitude: number; longitude: number },
  second: LocationValue & { latitude: number; longitude: number },
): number {
  const firstLatitude = degreesToRadians(first.latitude);
  const secondLatitude = degreesToRadians(second.latitude);
  const latitudeDelta = degreesToRadians(second.latitude - first.latitude);
  const longitudeDelta = degreesToRadians(second.longitude - first.longitude);
  const sinLatitude = Math.sin(latitudeDelta / 2);
  const sinLongitude = Math.sin(longitudeDelta / 2);
  const a =
    sinLatitude * sinLatitude +
    Math.cos(firstLatitude) *
      Math.cos(secondLatitude) *
      sinLongitude *
      sinLongitude;
  const clamped = Math.min(1, Math.max(0, a));
  return 2 * EARTH_RADIUS_METERS * Math.atan2(
    Math.sqrt(clamped),
    Math.sqrt(1 - clamped),
  );
}

function degreesToRadians(value: number): number {
  return (value * Math.PI) / 180;
}
