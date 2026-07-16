import * as bcrypt from 'bcrypt';
import { inject, injectable } from 'tsyringe';

import {
  AuthApplicationError,
  googleAccountConflictError,
  invalidCredentialsError,
  passwordUnavailableError,
} from '../errors/auth.error.js';
import type { PrismaClient } from '../generated/prisma/client.js';
import {
  ChangePasswordDto,
  GoogleAuthDto,
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
import type { GoogleIdentityVerifier } from './google-auth.service.js';

const SALT_ROUNDS = 10;

function canonicalizeUsername(username: string): string {
  return username.trim().toLowerCase();
}

function isUniqueConstraintFailure(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2002'
  );
}

function isRecordNotFoundFailure(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2025'
  );
}

@injectable()
export class UserService {
  constructor(
    @inject('PrismaClient') private readonly prisma: PrismaClient,
    @inject('AuthSessionService')
    private readonly authSessions: AuthSessionService,
    @inject('GoogleIdentityVerifier')
    private readonly googleIdentityVerifier?: GoogleIdentityVerifier,
  ) {}

  async register(registerDto: RegisterUserDto): Promise<AuthResponse> {
    const hashedPassword = await bcrypt.hash(registerDto.password, SALT_ROUNDS);
    const username = canonicalizeUsername(registerDto.username);

    try {
      return await this.authSessions.withSerializableTransaction(
        async (transaction) => {
          const user = await transaction.user.create({
            data: {
              username,
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
          where: { username },
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
    const username = canonicalizeUsername(loginDto.username);
    const user = await this.prisma.user.findUnique({
      where: { username },
    });
    if (user === null || user.password === null) {
      throw invalidCredentialsError();
    }

    const password = user.password;

    const passwordMatches = await bcrypt.compare(
      loginDto.password,
      password,
    );
    if (!passwordMatches) {
      throw invalidCredentialsError();
    }

    return this.authSessions.withSerializableTransaction(
      async (transaction) => {
        const currentUser = await transaction.user.findUnique({
          where: { id: user.id },
        });
        if (currentUser === null || currentUser.password !== password) {
          throw invalidCredentialsError();
        }
        return this.authSessions.issueSessionInTransaction(
          transaction,
          currentUser,
        );
      },
    );
  }

  async googleLogin(googleAuthDto: GoogleAuthDto): Promise<AuthResponse> {
    if (this.googleIdentityVerifier === undefined) {
      throw new Error('Google identity verifier is not configured');
    }

    const verifiedIdentity = await this.googleIdentityVerifier.verifyIdToken(
      googleAuthDto.idToken,
    );
    const identity = {
      ...verifiedIdentity,
      email: canonicalizeUsername(verifiedIdentity.email),
    };

    try {
      return await this.authSessions.withSerializableTransaction(
        async (transaction) => {
          const providerUser = await transaction.user.findUnique({
            where: { googleSubject: identity.subject },
          });
          if (providerUser !== null) {
            return this.authSessions.issueSessionInTransaction(
              transaction,
              providerUser,
            );
          }

          // A matching password account is not linked implicitly. Linking by
          // email alone could attach a Google identity to the wrong account;
          // an explicit, authenticated linking flow can be added separately.
          const emailOwner = await transaction.user.findFirst({
            where: {
              username: {
                equals: identity.email,
                mode: 'insensitive',
              },
            },
          });
          if (emailOwner !== null) {
            throw googleAccountConflictError();
          }

          const user = await transaction.user.create({
            data: {
              username: identity.email,
              password: null,
              googleSubject: identity.subject,
              firstname: identity.firstname,
              lastname: identity.lastname,
            },
          });
          return this.authSessions.issueSessionInTransaction(
            transaction,
            user,
          );
        },
      );
    } catch (error: unknown) {
      if (!isUniqueConstraintFailure(error)) {
        throw error;
      }

      // Concurrent first-sign-in calls with the same verified subject can
      // race on either unique key. Reuse only an exact provider-subject match;
      // an email collision with any other identity remains a hard conflict.
      const providerUser = await this.prisma.user.findUnique({
        where: { googleSubject: identity.subject },
      });
      if (providerUser === null) {
        throw googleAccountConflictError();
      }
      return this.authSessions.issueSession(providerUser);
    }
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

    if (user.password === null) {
      throw passwordUnavailableError();
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
  ): Promise<SafeUserResponse> {
    // Only the two declared profile fields are ever mapped into the update;
    // avatar fields stay owned by the dedicated upload pipeline (IP-0).
    try {
      const user = await this.prisma.user.update({
        where: { id: userId },
        data: {
          firstname: updateProfileDto.firstname,
          lastname: updateProfileDto.lastname,
        },
      });
      return toSafeUserResponse(user);
    } catch (error: unknown) {
      if (isRecordNotFoundFailure(error)) {
        throw new AuthApplicationError(
          'AUTH_USER_NOT_FOUND',
          404,
          'User account was not found',
        );
      }
      throw error;
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
