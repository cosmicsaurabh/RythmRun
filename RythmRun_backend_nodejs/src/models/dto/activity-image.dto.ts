import {
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class RequestActivityImageUploadUrlDto {
  @IsString()
  @MaxLength(160)
  clientImageId!: string;

  @IsString()
  contentType!: string;

  @IsInt()
  @Min(1)
  @Max(10 * 1024 * 1024)
  sizeBytes!: number;

  @IsString()
  @IsOptional()
  @MaxLength(128)
  checksumSha256?: string;

  @IsInt()
  @IsOptional()
  @Min(1)
  width?: number;

  @IsInt()
  @IsOptional()
  @Min(1)
  height?: number;

  @IsInt()
  @IsOptional()
  @Min(0)
  sortOrder?: number;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  caption?: string;
}

export class ConfirmActivityImageUploadDto extends RequestActivityImageUploadUrlDto {
  @IsString()
  key!: string;
}
