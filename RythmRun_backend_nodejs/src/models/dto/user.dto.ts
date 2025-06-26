import { IsString, IsOptional, MinLength, MaxLength, Matches } from 'class-validator';

export class RegisterUserDto {
    @IsString()
    @MinLength(3)
    @MaxLength(30)
    @Matches(/^[a-zA-Z0-9_]+$/, {
        message: 'Username can only contain letters, numbers and underscore'
    })
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
    @MinLength(3)
    @MaxLength(30)
    username!: string;

    @IsString()
    @MinLength(8)
    @MaxLength(50)
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