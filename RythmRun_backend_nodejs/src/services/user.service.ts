import * as bcrypt from 'bcrypt';
import { inject, injectable } from 'tsyringe';

import {
  AuthApplicationError,
  invalidCredentialsError,
} from '../errors/auth.error.js';
import type { PrismaClient } from '../generated/prisma/client.js';
import {
  ChangePasswordDto,
  LoginUserDto,
  RegisterUserDto,
  UpdateProfileDto,
} from '../models/dto/user.dto.js';
import {
  AuthSessionService,
  type AuthResponse,
  type SafeUserResponse,
  toSafeUserResponse,
} from './auth-session.service.js';

const SALT_ROUNDS = 10;

function isUniqueConstraintFailure(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2002'
  );
}

@injectable()
export class UserService {
  constructor(
    @inject('PrismaClient') private readonly prisma: PrismaClient,
    @inject('AuthSessionService')
    private readonly authSessions: AuthSessionService,
  ) {}

  async register(registerDto: RegisterUserDto): Promise<AuthResponse> {
    const hashedPassword = await bcrypt.hash(registerDto.password, SALT_ROUNDS);

    try {
      return await this.authSessions.withSerializableTransaction(
        async (transaction) => {
          const user = await transaction.user.create({
            data: {
              username: registerDto.username,
              password: hashedPassword,
              firstname: registerDto.firstname,
              lastname: registerDto.lastname,
            },
          });
          return this.authSessions.issueSessionInTransaction(
            transaction,
            user,
          );
        },
      );
    } catch (error: unknown) {
      if (isUniqueConstraintFailure(error)) {
        const existingUser = await this.prisma.user.findUnique({
          where: { username: registerDto.username },
          select: { id: true },
        });
        if (existingUser !== null) {
          throw new AuthApplicationError(
            'AUTH_USERNAME_TAKEN',
            409,
            'Username is already registered',
          );
        }
      }
      throw error;
    }
  }

  async login(loginDto: LoginUserDto): Promise<AuthResponse> {
    const user = await this.prisma.user.findUnique({
      where: { username: loginDto.username },
    });
    if (user === null) {
      throw invalidCredentialsError();
    }

    const passwordMatches = await bcrypt.compare(
      loginDto.password,
      user.password,
    );
    if (!passwordMatches) {
      throw invalidCredentialsError();
    }

    return this.authSessions.withSerializableTransaction(
      async (transaction) => {
        const currentUser = await transaction.user.findUnique({
          where: { id: user.id },
        });
        if (currentUser === null || currentUser.password !== user.password) {
          throw invalidCredentialsError();
        }
        return this.authSessions.issueSessionInTransaction(
          transaction,
          currentUser,
        );
      },
    );
  }

  async refreshToken(refreshToken: string): Promise<AuthResponse> {
    return this.authSessions.rotateRefreshToken(refreshToken);
  }

  async logout(userId: number, sessionId: string): Promise<void> {
    await this.authSessions.revokeSession(userId, sessionId);
  }

  async changePassword(
    userId: number,
    changePasswordDto: ChangePasswordDto,
  ): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user === null) {
      throw new AuthApplicationError(
        'AUTH_USER_NOT_FOUND',
        404,
        'User account was not found',
      );
    }

    const passwordMatches = await bcrypt.compare(
      changePasswordDto.currentPassword,
      user.password,
    );
    if (!passwordMatches) {
      throw new AuthApplicationError(
        'AUTH_PASSWORD_INVALID',
        400,
        'Current password is incorrect',
      );
    }

    const hashedPassword = await bcrypt.hash(
      changePasswordDto.newPassword,
      SALT_ROUNDS,
    );
    await this.authSessions.withSerializableTransaction(
      async (transaction) => {
        const updated = await transaction.user.updateMany({
          where: { id: userId, password: user.password },
          data: { password: hashedPassword },
        });
        if (updated.count !== 1) {
          throw new AuthApplicationError(
            'AUTH_PASSWORD_INVALID',
            400,
            'Current password is incorrect',
          );
        }
        await this.authSessions.revokeAllUserSessionsInTransaction(
          transaction,
          userId,
        );
      },
    );
  }

  async updateProfile(
    userId: number,
    updateProfileDto: UpdateProfileDto,
  ): Promise<void> {
    const updated = await this.prisma.user.updateMany({
      where: { id: userId },
      data: {
        firstname: updateProfileDto.firstname,
        lastname: updateProfileDto.lastname,
      },
    });
    if (updated.count !== 1) {
      throw new AuthApplicationError(
        'AUTH_USER_NOT_FOUND',
        404,
        'User account was not found',
      );
    }
  }

  async getMe(userId: number): Promise<SafeUserResponse> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user === null) {
      throw new AuthApplicationError(
        'AUTH_USER_NOT_FOUND',
        404,
        'User account was not found',
      );
    }
    return toSafeUserResponse(user);
  }
}
