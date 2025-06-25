import { PrismaClient } from '../../generated/prisma';
import { RegisterUserDto } from '../models/dto/user.dto';
import * as bcrypt from 'bcrypt';

export class UserService {
    private prisma: PrismaClient;

    constructor() {
        this.prisma = new PrismaClient();
    }

    async register(userData: RegisterUserDto) {
        // Check if username already exists
        const existingUser = await this.prisma.user.findUnique({
            where: { username: userData.username }
        });

        if (existingUser) {
            throw new Error('Username already exists');
        }

        // Hash password
        const hashedPassword = await bcrypt.hash(userData.password, 10);

        // Create user
        const user = await this.prisma.user.create({
            data: {
                username: userData.username,
                password: hashedPassword,
                firstname: userData.firstname,
                lastname: userData.lastname
            },
            select: {
                id: true,
                username: true,
                firstname: true,
                lastname: true,
                createdAt: true
            }
        });

        return user;
    }
} 