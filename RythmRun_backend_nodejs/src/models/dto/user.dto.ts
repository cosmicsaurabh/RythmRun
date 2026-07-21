import { IsString, IsOptional, MinLength, MaxLength, IsEmail } from 'class-validator';
import { Transform } from 'class-transformer';

function canonicalUsername(value: unknown): unknown {
    return typeof value === 'string' ? value.trim().toLowerCase() : value;
}

export class RegisterUserDto {
    @Transform(({ value }) => canonicalUsername(value))
    @IsString()
    @IsEmail()
    @MinLength(3)
    @MaxLength(255)
    username!: string;

    @IsString()
    @MinLength(8)
    @MaxLength(50)
    password!: string;

    @IsString()
    @IsOptional()
    @MaxLength(50)
    firstname?: string;

    @IsString()
    @IsOptional()
    @MaxLength(50)
    lastname?: string;
}

export class LoginUserDto {
    @Transform(({ value }) => canonicalUsername(value))
    @IsString()
    @IsEmail()
    // @MinLength(3)
    // @MaxLength(255)
    username!: string;

    @IsString()
    // @MinLength(8)
    // @MaxLength(50)
    password!: string;
}

export class GoogleAuthDto {
    @IsString()
    @MinLength(1)
    @MaxLength(8192)
    idToken!: string;
}

export class RefreshTokenDto {
    @IsString()
    @MinLength(1)
    @MaxLength(4096)
    refreshToken!: string;
}

export class ChangePasswordDto {
    @IsString()
    @MinLength(8)
    @MaxLength(50)
    currentPassword!: string;

    @IsString()
    @MinLength(8)
    @MaxLength(50)
    newPassword!: string;
} 

export class UpdateProfileDto {
    @IsString()
    @IsOptional()
    @MaxLength(50)
    firstname?: string;

    @IsString()
    @IsOptional()
    @MaxLength(50)
    lastname?: string;
}

export class PasswordResetRequestDto {
    @Transform(({ value }) => canonicalUsername(value))
    @IsString()
    @IsEmail()
    @MaxLength(255)
    username!: string;
}

export class PasswordResetConfirmDto {
    @IsString()
    @MinLength(1)
    @MaxLength(512)
    token!: string;

    @IsString()
    @MinLength(8)
    @MaxLength(50)
    newPassword!: string;
}
