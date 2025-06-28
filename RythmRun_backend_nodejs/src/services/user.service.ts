import { PrismaClient, User } from '../../generated/prisma';
import { RegisterUserDto, LoginUserDto, ChangePasswordDto, UpdateProfileDto } from '../models/dto/user.dto';
import * as bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { injectable, inject } from "tsyringe";

interface ProfilePictureUpdate {
    profilePicturePath: string;
    profilePictureType: string;
}

@injectable()
export class UserService {
    private readonly SALT_ROUNDS = 10;
    private readonly JWT_EXPIRATION = '1h';
    private readonly REFRESH_EXPIRATION = '7d';
    private readonly REFRESH_EXPIRATION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

    constructor(
        @inject("PrismaClient") private prisma: PrismaClient
    ) {}

    async register(registerDto: RegisterUserDto) {
        // Check if username already exists
        const existingUser = await this.prisma.user.findUnique({
            where: { username: registerDto.username }
        });

        if (existingUser) {
            throw new Error('Username already exists');
        }

        // Hash password
        const hashedPassword = await bcrypt.hash(registerDto.password, this.SALT_ROUNDS);

        // Create user
        const user = await this.prisma.user.create({
            data: {
                ...registerDto,
                password: hashedPassword
            }
        });

        // Generate tokens
        const accessToken = this.generateAccessToken(user.id);
        const refreshToken = this.generateRefreshToken(user.id);

        return {
            ...this.getUserResponseData(user, accessToken, refreshToken)
        };
    }

    async login(loginDto: LoginUserDto) {
        // Find user
        const user = await this.prisma.user.findUnique({
            where: { username: loginDto.username }
        });

        if (!user) {
            throw new Error('Invalid username or password');
        }

        // Verify password
        const isPasswordValid = await bcrypt.compare(loginDto.password, user.password);
        if (!isPasswordValid) {
            throw new Error('Invalid username or password');
        }

        // Generate tokens
        const accessToken = this.generateAccessToken(user.id);
        const refreshToken = this.generateRefreshToken(user.id);

        // Store refresh token in database
        await this.prisma.refreshToken.upsert({
            where: {
                userId: user.id
            },
            update: {
                token: refreshToken,
                expiryDate: new Date(Date.now() + this.REFRESH_EXPIRATION_MS)
            },
            create: {
                userId: user.id,
                token: refreshToken,
                expiryDate: new Date(Date.now() + this.REFRESH_EXPIRATION_MS)
            }
        });

        return {
            id: user.id,
            username: user.username,
            firstname: user.firstname,
            lastname: user.lastname,
            accessToken,
            refreshToken
        };
    }

    async changePassword(userId: number, changePasswordDto: ChangePasswordDto) {
        // Find user
        const user = await this.prisma.user.findUnique({
            where: { id: userId }
        });

        if (!user) {
            throw new Error('User not found');
        }

        // Verify current password
        const isPasswordValid = await bcrypt.compare(changePasswordDto.currentPassword, user.password);
        if (!isPasswordValid) {
            throw new Error('Current password is incorrect');
        }

        // Hash new password
        const hashedPassword = await bcrypt.hash(changePasswordDto.newPassword, this.SALT_ROUNDS);

        // Update password
        await this.prisma.user.update({
            where: { id: userId },
            data: { password: hashedPassword }
        });
    }

    async updateProfile(userId: number, updateProfileDto: UpdateProfileDto) {
        // Find user
        const user = await this.prisma.user.findUnique({
            where: { id: userId }
        });

        if (!user) {
            throw new Error('User not found');
        }

        // Update profile
        await this.prisma.user.update({
            where: { id: userId },
            data: updateProfileDto
        });
    }

    async findById(userId: number) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId }
        });

        if (!user) {
            throw new Error('User not found');
        }

        return user;
    }

    async updateProfilePicture(userId: number, update: ProfilePictureUpdate) {
        // Find user
        const user = await this.prisma.user.findUnique({
            where: { id: userId }
        });

        if (!user) {
            throw new Error('User not found');
        }

        // Update profile picture path
        await this.prisma.user.update({
            where: { id: userId },
            data: {
                profilePicturePath: update.profilePicturePath,
                profilePictureType: update.profilePictureType
            }
        });
    }

    private getUserResponseData(user: User, accessToken: string, refreshToken: string) {

        return {
            id: user.id,
            username: user.username,
            firstname: user.firstname,
            lastname: user.lastname,
            profilePicturePath: user.profilePicturePath,
            profilePictureType: user.profilePictureType,
            accessToken,
            refreshToken
        };
    }

    private generateAccessToken(userId: number): string {
        return jwt.sign(
            { userId },
            process.env.JWT_SECRET || 'your-secret-key',
            { expiresIn: this.JWT_EXPIRATION }
        );
    }

    private generateRefreshToken(userId: number): string {
        return jwt.sign(
            { userId },
            process.env.REFRESH_TOKEN_SECRET || 'your-refresh-secret-key',
            { expiresIn: this.REFRESH_EXPIRATION }
        );
    }

    async logout(userId: number): Promise<void> {
        // Delete the refresh token for this user
        await this.prisma.refreshToken.deleteMany({
            where: {
                userId: userId
            }
        });
    }

    async refreshToken(userId: number, refreshToken: string) {
        // Find the refresh token in the database
        const storedToken = await this.prisma.refreshToken.findFirst({
            where: {
                userId: userId,
                token: refreshToken
            }
        });

        if (!storedToken) {
            throw new Error('Invalid refresh token');
        }

        // Check if the token has expired
        if (new Date() > storedToken.expiryDate) {
            // Delete the expired token
            await this.prisma.refreshToken.delete({
                where: {
                    id: storedToken.id
                }
            });
            throw new Error('Refresh token has expired');
        }

        // Generate new tokens
        const newAccessToken = this.generateAccessToken(userId);
        const newRefreshToken = this.generateRefreshToken(userId);

        // Update the refresh token in the database
        await this.prisma.refreshToken.update({
            where: {
                id: storedToken.id
            },
            data: {
                token: newRefreshToken,
                expiryDate: new Date(Date.now() + this.REFRESH_EXPIRATION_MS)
            }
        });

        return {
            accessToken: newAccessToken,
            refreshToken: newRefreshToken
        };
    }
} 