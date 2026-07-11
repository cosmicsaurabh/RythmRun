import { Type } from 'class-transformer';
import {
    ArrayMaxSize,
    IsArray,
    IsBoolean,
    IsDateString,
    IsIn,
    IsInt,
    IsNumber,
    IsOptional,
    IsString,
    Matches,
    Max,
    MaxLength,
    Min,
    MinLength,
    ValidateIf,
    ValidateNested,
} from 'class-validator';

export const LEGACY_METRICS_VERSION = 1;
export const CURRENT_METRICS_VERSION = 2;
export const SUPPORTED_METRICS_VERSIONS = [
    LEGACY_METRICS_VERSION,
    CURRENT_METRICS_VERSION,
] as const;

export const ACTIVITY_TYPES = [
    'running',
    'walking',
    'cycling',
    'hiking',
] as const;

export const ACTIVITY_STATUSES = [
    'notStarted',
    'active',
    'paused',
    'completed',
] as const;

export const MAX_ACTIVITY_LOCATIONS = 12_000;
export const MAX_ACTIVITY_STATUS_CHANGES = 1_000;
export const MAX_ACTIVITY_DURATION_SECONDS = 7 * 24 * 60 * 60;
export const MAX_ACTIVITY_DISTANCE_METERS = 20_000_000;

const MAX_CLIENT_SYNC_ID_LENGTH = 128;
const MAX_ACTIVITY_NAME_LENGTH = 120;
const MAX_ACTIVITY_DESCRIPTION_LENGTH = 4_000;
const MAX_LEGACY_AVERAGE_SPEED = 720;
export const MAX_ACTIVITY_SPEED_METERS_PER_SECOND = 200;
const MAX_CALORIES = 1_000_000;
const MAX_ELEVATION_CHANGE_METERS = 100_000;
export const MIN_ACTIVITY_ALTITUDE_METERS = -1_000;
export const MAX_ACTIVITY_ALTITUDE_METERS = 20_000;
export const MAX_ACTIVITY_ACCURACY_METERS = 10_000;

const isPresent = (_object: object, value: unknown) => value !== undefined;

export class LocationDto {
    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(-90)
    @Max(90)
    latitude!: number;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(-180)
    @Max(180)
    longitude!: number;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(MIN_ACTIVITY_ALTITUDE_METERS)
    @Max(MAX_ACTIVITY_ALTITUDE_METERS)
    @IsOptional()
    altitude?: number | null;

    @IsDateString({ strict: true })
    timestamp!: string;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_ACCURACY_METERS)
    @IsOptional()
    accuracy?: number | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_SPEED_METERS_PER_SECOND)
    @IsOptional()
    speed?: number | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(360)
    @IsOptional()
    heading?: number | null;
}

export class StatusChangeDto {
    @IsString()
    @IsIn(ACTIVITY_STATUSES)
    status!: string;

    @IsDateString({ strict: true })
    timestamp!: string;
}

export class CreateActivityDto {
    @IsString()
    @MinLength(1)
    @MaxLength(MAX_CLIENT_SYNC_ID_LENGTH)
    @Matches(/\S/, { message: 'clientSyncId must contain a non-whitespace character' })
    clientSyncId!: string;

    @IsInt()
    @IsIn(SUPPORTED_METRICS_VERSIONS)
    @IsOptional()
    metricsVersion?: number | null;

    @IsString()
    @IsIn(ACTIVITY_TYPES)
    type!: string;

    @IsDateString({ strict: true })
    startTime!: string;

    @IsDateString({ strict: true })
    endTime!: string;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_DISTANCE_METERS)
    distance!: number;

    @IsInt()
    @Min(0)
    @Max(MAX_ACTIVITY_DURATION_SECONDS)
    duration!: number;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_LEGACY_AVERAGE_SPEED)
    avgSpeed!: number;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_SPEED_METERS_PER_SECOND)
    maxSpeed!: number;

    @IsInt()
    @Min(0)
    @Max(MAX_CALORIES)
    @IsOptional()
    calories?: number | null;

    @IsString()
    @MaxLength(MAX_ACTIVITY_DESCRIPTION_LENGTH)
    @IsOptional()
    description?: string | null;

    @ValidateIf(isPresent)
    @IsBoolean()
    isPublic?: boolean;

    @IsInt()
    @Min(0)
    @Max(MAX_ACTIVITY_DURATION_SECONDS)
    @IsOptional()
    pausedDuration?: number | null;

    @IsString()
    @MaxLength(MAX_ACTIVITY_NAME_LENGTH)
    @IsOptional()
    name?: string | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ELEVATION_CHANGE_METERS)
    @IsOptional()
    elevationGain?: number | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ELEVATION_CHANGE_METERS)
    @IsOptional()
    elevationLoss?: number | null;

    @ValidateIf(isPresent)
    @IsArray()
    @ArrayMaxSize(MAX_ACTIVITY_STATUS_CHANGES)
    @ValidateNested({ each: true })
    @Type(() => StatusChangeDto)
    statusChanges?: StatusChangeDto[];

    @IsArray()
    @ArrayMaxSize(MAX_ACTIVITY_LOCATIONS)
    @ValidateNested({ each: true })
    @Type(() => LocationDto)
    locations!: LocationDto[];
}

export class GetActivitiesQueryDto {
    @IsInt()
    @IsOptional()
    @Min(1)
    page?: number;

    @IsInt()
    @IsOptional()
    @Min(1)
    @Max(50)
    limit?: number;

    @IsString()
    @IsIn(ACTIVITY_TYPES)
    @IsOptional()
    type?: string;

    @IsDateString({ strict: true })
    @IsOptional()
    startDate?: string;

    @IsDateString({ strict: true })
    @IsOptional()
    endDate?: string;
}

export class UpdateActivityDto {
    @ValidateIf(isPresent)
    @IsString()
    @IsIn(ACTIVITY_TYPES)
    type?: string;

    @ValidateIf(isPresent)
    @IsDateString({ strict: true })
    startTime?: string;

    @ValidateIf(isPresent)
    @IsDateString({ strict: true })
    endTime?: string;

    @ValidateIf(isPresent)
    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_DISTANCE_METERS)
    distance?: number;

    @ValidateIf(isPresent)
    @IsInt()
    @Min(0)
    @Max(MAX_ACTIVITY_DURATION_SECONDS)
    duration?: number;

    @ValidateIf(isPresent)
    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_LEGACY_AVERAGE_SPEED)
    avgSpeed?: number;

    @ValidateIf(isPresent)
    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ACTIVITY_SPEED_METERS_PER_SECOND)
    maxSpeed?: number;

    @IsInt()
    @Min(0)
    @Max(MAX_CALORIES)
    @IsOptional()
    calories?: number | null;

    @IsString()
    @MaxLength(MAX_ACTIVITY_DESCRIPTION_LENGTH)
    @IsOptional()
    description?: string | null;

    @ValidateIf(isPresent)
    @IsBoolean()
    isPublic?: boolean;

    @IsInt()
    @Min(0)
    @Max(MAX_ACTIVITY_DURATION_SECONDS)
    @IsOptional()
    pausedDuration?: number | null;

    @IsString()
    @MaxLength(MAX_ACTIVITY_NAME_LENGTH)
    @IsOptional()
    name?: string | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ELEVATION_CHANGE_METERS)
    @IsOptional()
    elevationGain?: number | null;

    @IsNumber({ allowNaN: false, allowInfinity: false })
    @Min(0)
    @Max(MAX_ELEVATION_CHANGE_METERS)
    @IsOptional()
    elevationLoss?: number | null;

    @ValidateIf(isPresent)
    @IsArray()
    @ArrayMaxSize(MAX_ACTIVITY_STATUS_CHANGES)
    @ValidateNested({ each: true })
    @Type(() => StatusChangeDto)
    statusChanges?: StatusChangeDto[];

    @ValidateIf(isPresent)
    @IsArray()
    @ArrayMaxSize(MAX_ACTIVITY_LOCATIONS)
    @ValidateNested({ each: true })
    @Type(() => LocationDto)
    locations?: LocationDto[];
}
