import { PrismaClient } from '../../generated/prisma';
import { RegisterUserDto, LoginUserDto } from '../models/dto/user.dto';
import * as bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

export class UserService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    private generateToken(user: { id: number; username: string }) {
        return jwt.sign(
            { id: user.id, username: user.username },
            process.env.JWT_SECRET || 'your-secret-key',
            { expiresIn: '24h' }
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
        const hashedPassword = await bcrypt.hash(registerDto.password, 10);

        // Create user
        const user = await this.prisma.user.create({
            data: {
                username: registerDto.username,
                password: hashedPassword,
                firstname: registerDto.firstname,
                lastname: registerDto.lastname
            }
        });

        // Generate token
        const token = this.generateToken(user);

        // Remove password from response
        const { password, ...userWithoutPassword } = user;
        return { user: userWithoutPassword, token };
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

        // Generate token
        const token = this.generateToken(user);

        // Remove password from response
        const { password, ...userWithoutPassword } = user;
        return { user: userWithoutPassword, token };
    }
} 