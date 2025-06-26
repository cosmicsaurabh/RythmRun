import { IsString, IsOptional, IsBoolean, IsNumber, IsDateString, Min, IsArray } from 'class-validator';

export class CreateActivityDto {
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

    @IsArray()
    @IsOptional()
    locations?: LocationDto[];
} 