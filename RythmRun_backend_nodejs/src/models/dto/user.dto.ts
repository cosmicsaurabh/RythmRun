import { IsString, IsOptional, MinLength, MaxLength, IsEmail } from 'class-validator';

export class RegisterUserDto {
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