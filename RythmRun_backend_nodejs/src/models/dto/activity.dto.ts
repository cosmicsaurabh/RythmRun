import { IsString, IsOptional, IsBoolean, IsNumber, IsDateString, Min, IsArray, IsIn, IsInt } from 'class-validator';

export const LEGACY_METRICS_VERSION = 1;
export const CURRENT_METRICS_VERSION = 2;
export const SUPPORTED_METRICS_VERSIONS = [
    LEGACY_METRICS_VERSION,
    CURRENT_METRICS_VERSION,
] as const;

export class CreateActivityDto {
    @IsString()
    clientSyncId!: string;

    @IsInt()
    @IsIn(SUPPORTED_METRICS_VERSIONS)
    @IsOptional()
    metricsVersion?: number;

    @IsString()
    type!: string;

    @IsDateString()
    startTime!: string;

    @IsDateString()
    endTime!: string;

    @IsNumber()
    @Min(0)
    distance!: number;

    @IsNumber()
    @Min(0)
    duration!: number;

    @IsNumber()
    @Min(0)
    avgSpeed!: number;

    @IsNumber()
    @Min(0)
    maxSpeed!: number;

    @IsNumber()
    @IsOptional()
    @Min(0)
    calories?: number;

    @IsString()
    @IsOptional()
    description?: string;

    @IsBoolean()
    @IsOptional()
    isPublic?: boolean;

    @IsNumber()
    @IsOptional()
    @Min(0)
    pausedDuration?: number;

    @IsString()
    @IsOptional()
    name?: string;

    @IsNumber()
    @IsOptional()
    elevationGain?: number;

    @IsNumber()
    @IsOptional()
    elevationLoss?: number;

    @IsArray()
    @IsOptional()
    statusChanges?: StatusChangeDto[];

    @IsArray()
    locations!: LocationDto[];
}

export class LocationDto {
    @IsNumber()
    latitude!: number;

    @IsNumber()
    longitude!: number;

    @IsNumber()
    @IsOptional()
    altitude?: number;

    @IsDateString()
    timestamp!: string;

    @IsNumber()
    @IsOptional()
    accuracy?: number;

    @IsNumber()
    @IsOptional()
    speed?: number;

    @IsNumber()
    @IsOptional()
    heading?: number;
}

export class StatusChangeDto {
    @IsString()
    status!: string;

    @IsDateString()
    timestamp!: string;
}

export class GetActivitiesQueryDto {
    @IsNumber()
    @IsOptional()
    @Min(1)
    page?: number;

    @IsNumber()
    @IsOptional()
    @Min(1)
    limit?: number;

    @IsString()
    @IsOptional()
    type?: string;

    @IsDateString()
    @IsOptional()
    startDate?: string;

    @IsDateString()
    @IsOptional()
    endDate?: string;
}

export class UpdateActivityDto {
    @IsString()
    @IsOptional()
    type?: string;

    @IsDateString()
    @IsOptional()
    startTime?: string;

    @IsDateString()
    @IsOptional()
    endTime?: string;

    @IsNumber()
    @IsOptional()
    @Min(0)
    distance?: number;

    @IsNumber()
    @IsOptional()
    @Min(0)
    duration?: number;

    @IsNumber()
    @IsOptional()
    @Min(0)
    avgSpeed?: number;

    @IsNumber()
    @IsOptional()
    @Min(0)
    maxSpeed?: number;

    @IsNumber()
    @IsOptional()
    @Min(0)
    calories?: number;

    @IsString()
    @IsOptional()
    description?: string;

    @IsBoolean()
    @IsOptional()
    isPublic?: boolean;

    @IsNumber()
    @IsOptional()
    @Min(0)
    pausedDuration?: number;

    @IsString()
    @IsOptional()
    name?: string;

    @IsNumber()
    @IsOptional()
    elevationGain?: number;

    @IsNumber()
    @IsOptional()
    elevationLoss?: number;

    @IsArray()
    @IsOptional()
    statusChanges?: StatusChangeDto[];

    @IsArray()
    @IsOptional()
    locations?: LocationDto[];
} 
