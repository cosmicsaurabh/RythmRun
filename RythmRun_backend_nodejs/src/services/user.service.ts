import { PrismaClient } from '../../generated/prisma';
import { RegisterUserDto, LoginUserDto } from '../models/dto/user.dto';
import * as bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

export class UserService {
    private prisma: PrismaClient;
    private readonly SALT_ROUNDS = 10;
    private readonly JWT_EXPIRATION = '1h';
    private readonly REFRESH_EXPIRATION = '7d';
    private readonly REFRESH_EXPIRATION_MS = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

    constructor() {
        this.prisma = new PrismaClient();
    }

    private generateToken(user: { id: number }) {
        return jwt.sign(
            { id: user.id },
            process.env.JWT_SECRET || 'your-secret-key',
            { expiresIn: this.JWT_EXPIRATION }
        );
    }

    private generateRefreshToken(user: { id: number }) {
        return jwt.sign(
            { id: user.id },
            process.env.JWT_REFRESH_SECRET || 'your-refresh-secret-key',
            { expiresIn: this.REFRESH_EXPIRATION }
        );
    }

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
                username: registerDto.username,
                password: hashedPassword,
                firstname: registerDto.firstname,
                lastname: registerDto.lastname
            }
        });

        // Generate tokens
        const token = this.generateToken(user);
        const refreshToken = this.generateRefreshToken(user);

        // Store refresh token
        await this.prisma.refreshToken.create({
            data: {
                userId: user.id,
                token: refreshToken,
                expiryDate: new Date(Date.now() + this.REFRESH_EXPIRATION_MS)
            }
        });

        // Remove password from response
        const { password, ...userWithoutPassword } = user;
        return { user: userWithoutPassword, token, refreshToken };
    }

    async login(loginDto: LoginUserDto) {
        // Find user by username
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
        const token = this.generateToken(user);
        const refreshToken = this.generateRefreshToken(user);

        // Update or create refresh token
        await this.prisma.refreshToken.upsert({
            where: { userId: user.id },
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

        // Remove password from response
        const { password, ...userWithoutPassword } = user;
        return { user: userWithoutPassword, token, refreshToken };
    }

    async refreshToken(userId: number, oldRefreshToken: string) {
        // Verify old refresh token exists and matches
        const storedToken = await this.prisma.refreshToken.findFirst({
            where: {
                userId,
                token: oldRefreshToken,
                expiryDate: {
                    gt: new Date()
                }
            }
        });

        if (!storedToken) {
            throw new Error('Invalid refresh token');
        }

        // Generate new tokens
        const user = { id: userId };
        const token = this.generateToken(user);
        const refreshToken = this.generateRefreshToken(user);

        // Update refresh token
        await this.prisma.refreshToken.update({
            where: { userId },
            data: {
                token: refreshToken,
                expiryDate: new Date(Date.now() + this.REFRESH_EXPIRATION_MS)
            }
        });

        return { token, refreshToken };
    }

    async logout(userId: number) {
        // Delete refresh token
        await this.prisma.refreshToken.delete({
            where: { userId }
        }).catch(() => {
            // Ignore error if token doesn't exist
        });
    }
} 