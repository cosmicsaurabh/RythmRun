import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export const AVATAR_CONTENT_TYPES = [
  'image/jpeg',
  'image/png',
  'image/webp',
] as const;

export const MAX_AVATAR_SIZE_BYTES = 10 * 1024 * 1024;

export class RequestAvatarUploadDto {
  @IsString()
  @IsIn([...AVATAR_CONTENT_TYPES])
  contentType!: string;

  @IsInt()
  @Min(1)
  @Max(MAX_AVATAR_SIZE_BYTES)
  sizeBytes!: number;

  // Deprecated compatibility input. The server always derives the stored
  // extension from contentType and only checks this field for consistency.
  @IsString()
  @IsOptional()
  @MaxLength(8)
  ext?: string;
}

export class ConfirmAvatarUploadDto {
  @IsString()
  @MaxLength(255)
  key!: string;

  @IsString()
  @IsIn([...AVATAR_CONTENT_TYPES])
  contentType!: string;
}
