import { isISO8601 } from 'class-validator';
import {
  ACTIVITY_STATUSES,
  CreateActivityDto,
  MAX_ACTIVITY_ACCURACY_METERS,
  MAX_ACTIVITY_ALTITUDE_METERS,
  MAX_ACTIVITY_LOCATIONS,
  MAX_ACTIVITY_SPEED_METERS_PER_SECOND,
  MAX_ACTIVITY_STATUS_CHANGES,
  MIN_ACTIVITY_ALTITUDE_METERS,
  UpdateActivityDto,
} from '../models/dto/activity.dto.js';
import {
  DtoValidationError,
  type DtoValidationIssue,
  validateDto,
} from './validation.middleware.js';

const LOCATION_PROPERTIES = new Set([
  'latitude',
  'longitude',
  'altitude',
  'timestamp',
  'accuracy',
  'speed',
  'heading',
]);
const STATUS_CHANGE_PROPERTIES = new Set(['status', 'timestamp']);
const CREATE_ACTIVITY_PROPERTIES = new Set([
  'clientSyncId',
  'metricsVersion',
  'type',
  'startTime',
  'endTime',
  'distance',
  'duration',
  'avgSpeed',
  'maxSpeed',
  'calories',
  'description',
  'isPublic',
  'pausedDuration',
  'name',
  'elevationGain',
  'elevationLoss',
  'statusChanges',
  'locations',
]);
const UPDATE_ACTIVITY_PROPERTIES = new Set([
  'type',
  'startTime',
  'endTime',
  'distance',
  'duration',
  'avgSpeed',
  'maxSpeed',
  'calories',
  'description',
  'isPublic',
  'pausedDuration',
  'name',
  'elevationGain',
  'elevationLoss',
  'statusChanges',
  'locations',
]);
const COLLECTION_PROPERTIES = new Set(['locations', 'statusChanges']);

function fail(
  property: string,
  constraintCode: string,
  message: string,
): never {
  const issue: DtoValidationIssue = {
    property,
    constraintCodes: [constraintCode],
    constraints: [message],
  };
  throw new DtoValidationError([issue]);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }

  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function validateAllowedProperties(
  value: Record<string, unknown>,
  allowedProperties: ReadonlySet<string>,
  path: string,
): void {
  for (const property in value) {
    if (
      Object.prototype.hasOwnProperty.call(value, property) &&
      !allowedProperties.has(property)
    ) {
      fail(
        path,
        'whitelistValidation',
        'object contains an unsupported field',
      );
    }
  }
}

function validateScalarContainers(
  value: Record<string, unknown>,
  allowedProperties: ReadonlySet<string>,
): void {
  for (const property of allowedProperties) {
    if (COLLECTION_PROPERTIES.has(property)) {
      continue;
    }

    const descriptor = Object.getOwnPropertyDescriptor(value, property);
    if (descriptor === undefined) {
      continue;
    }
    if (!('value' in descriptor)) {
      fail('$root', 'isPlainObject', 'request fields must be data properties');
    }

    const candidate = descriptor.value;
    if (typeof candidate === 'object' && candidate !== null) {
      fail(
        property,
        'isPrimitive',
        'field must be a scalar JSON value',
      );
    }
  }
}

function validateNumber(
  value: Record<string, unknown>,
  property: string,
  path: string,
  minimum: number,
  maximum: number,
  required: boolean,
): void {
  const candidate = value[property];
  if (candidate === undefined || candidate === null) {
    if (required) {
      fail(`${path}.${property}`, 'isNumber', `${property} must be a number`);
    }
    return;
  }

  if (
    typeof candidate !== 'number' ||
    !Number.isFinite(candidate) ||
    candidate < minimum ||
    candidate > maximum
  ) {
    fail(
      `${path}.${property}`,
      'isNumber',
      `${property} must be a finite number from ${minimum} to ${maximum}`,
    );
  }
}

function validateTimestamp(
  value: Record<string, unknown>,
  path: string,
): void {
  const timestamp = value.timestamp;
  if (
    typeof timestamp !== 'string' ||
    !isISO8601(timestamp, { strict: true })
  ) {
    fail(
      `${path}.timestamp`,
      'isDateString',
      'timestamp must be a valid ISO 8601 date string',
    );
  }
}

function validateLocation(value: unknown, index: number): void {
  const path = `locations.${index}`;
  if (!isPlainRecord(value)) {
    fail(path, 'nestedValidation', 'each location must be a plain object');
  }

  validateAllowedProperties(value, LOCATION_PROPERTIES, path);
  validateNumber(value, 'latitude', path, -90, 90, true);
  validateNumber(value, 'longitude', path, -180, 180, true);
  validateNumber(
    value,
    'altitude',
    path,
    MIN_ACTIVITY_ALTITUDE_METERS,
    MAX_ACTIVITY_ALTITUDE_METERS,
    false,
  );
  validateTimestamp(value, path);
  validateNumber(
    value,
    'accuracy',
    path,
    0,
    MAX_ACTIVITY_ACCURACY_METERS,
    false,
  );
  validateNumber(
    value,
    'speed',
    path,
    0,
    MAX_ACTIVITY_SPEED_METERS_PER_SECOND,
    false,
  );
  validateNumber(value, 'heading', path, 0, 360, false);
}

function validateStatusChange(value: unknown, index: number): void {
  const path = `statusChanges.${index}`;
  if (!isPlainRecord(value)) {
    fail(path, 'nestedValidation', 'each status change must be a plain object');
  }

  validateAllowedProperties(value, STATUS_CHANGE_PROPERTIES, path);
  if (
    typeof value.status !== 'string' ||
    !ACTIVITY_STATUSES.includes(
      value.status as (typeof ACTIVITY_STATUSES)[number],
    )
  ) {
    fail(
      `${path}.status`,
      'isIn',
      'status must be an allowed workout status',
    );
  }
  validateTimestamp(value, path);
}

function preflightActivityBody(
  body: unknown,
  locationsRequired: boolean,
  allowedProperties: ReadonlySet<string>,
): void {
  if (!isPlainRecord(body)) {
    return;
  }

  validateAllowedProperties(body, allowedProperties, '$root');
  validateScalarContainers(body, allowedProperties);

  const locations = body.locations;
  if (locations === undefined) {
    if (locationsRequired) {
      fail('locations', 'isArray', 'locations must be an array');
    }
  } else if (!Array.isArray(locations)) {
    fail('locations', 'isArray', 'locations must be an array');
  } else {
    if (locations.length > MAX_ACTIVITY_LOCATIONS) {
      fail(
        'locations',
        'arrayMaxSize',
        `locations must contain no more than ${MAX_ACTIVITY_LOCATIONS} entries`,
      );
    }
    locations.forEach(validateLocation);
  }

  const statusChanges = body.statusChanges;
  if (statusChanges === undefined) {
    return;
  }
  if (!Array.isArray(statusChanges)) {
    fail('statusChanges', 'isArray', 'statusChanges must be an array');
  }
  if (statusChanges.length > MAX_ACTIVITY_STATUS_CHANGES) {
    fail(
      'statusChanges',
      'arrayMaxSize',
      `statusChanges must contain no more than ${MAX_ACTIVITY_STATUS_CHANGES} entries`,
    );
  }
  statusChanges.forEach(validateStatusChange);
}

export async function validateCreateActivityDto(
  body: unknown,
): Promise<CreateActivityDto> {
  preflightActivityBody(body, true, CREATE_ACTIVITY_PROPERTIES);
  return validateDto(CreateActivityDto, body);
}

export async function validateUpdateActivityDto(
  body: unknown,
): Promise<UpdateActivityDto> {
  preflightActivityBody(body, false, UPDATE_ACTIVITY_PROPERTIES);
  return validateDto(UpdateActivityDto, body);
}
