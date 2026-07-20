import { randomBytes } from 'node:crypto';

import * as bcrypt from 'bcrypt';
import { inject, injectable } from 'tsyringe';

import {
  AuthApplicationError,
  emailUnverifiedConflictError,
  googleAccountConflictError,
  invalidCredentialsError,
  invalidVerificationTokenError,
  passwordUnavailableError,
  verificationRateLimitedError,
} from '../errors/auth.error.js';
import { Prisma, type PrismaClient } from '../generated/prisma/client.js';
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
  digestRefreshToken,
  toSafeUserResponse,
} from './auth-session.service.js';
import type { EmailSender } from './email.service.js';
import type { GoogleIdentityVerifier } from './google-auth.service.js';

const SALT_ROUNDS = 10;
const VERIFICATION_TOKEN_TTL_MS = 24 * 60 * 60 * 1000;
const VERIFICATION_RESEND_COOLDOWN_MS = 60 * 1000;
const EMAIL_VERIFICATION_PURPOSE = 'EMAIL_VERIFICATION' as const;

export type EmailVerificationResult = 'verified' | 'already_verified';

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
    @inject('EmailSender')
    private readonly emailSender?: EmailSender,
  ) {}

  async register(registerDto: RegisterUserDto): Promise<AuthResponse> {
    const hashedPassword = await bcrypt.hash(registerDto.password, SALT_ROUNDS);
    const username = canonicalizeUsername(registerDto.username);

    let registration: {
      response: AuthResponse;
      username: string;
      firstname: string | null;
      rawToken: string;
    };
    try {
      registration = await this.authSessions.withSerializableTransaction(
        async (transaction) => {
          const user = await transaction.user.create({
            data: {
              username,
              password: hashedPassword,
              firstname: registerDto.firstname,
              lastname: registerDto.lastname,
            },
          });
          const response = await this.authSessions.issueSessionInTransaction(
            transaction,
            user,
          );
          // Cheap, atomic DB work only; the SMTP call stays out of the
          // serializable transaction (it retries on P2034 and its latency
          // would hold locks / risk duplicate sends).
          const rawToken = await this.issueVerificationToken(
            transaction,
            user.id,
          );
          return {
            response,
            username: user.username,
            firstname: user.firstname,
            rawToken,
          };
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

    // Post-commit and best-effort: a send failure must never roll back an
    // already-registered user, who still receives a session either way.
    await this.deliverVerificationEmail(
      registration.username,
      registration.firstname,
      registration.rawToken,
    );
    return registration.response;
  }

  /**
   * Verifies an email using the raw token from a verification link. The
   * state transition is a single atomic update; re-presenting a consumed
   * token for an already-verified user is idempotent success (email
   * scanners and browsers routinely prefetch the GET link).
   */
  async verifyEmail(rawToken: string): Promise<EmailVerificationResult> {
    if (typeof rawToken !== 'string' || rawToken.length === 0) {
      throw invalidVerificationTokenError();
    }
    const tokenDigest = digestRefreshToken(rawToken);

    const outcome = await this.authSessions.withSerializableTransaction(
      async (transaction) => {
        const now = new Date();
        const token = await transaction.verificationToken.findUnique({
          where: { tokenDigest },
        });
        if (token === null) {
          return 'invalid' as const;
        }

        if (token.consumedAt !== null) {
          const owner = await transaction.user.findUnique({
            where: { id: token.userId },
            select: { emailVerified: true },
          });
          return owner?.emailVerified === true
            ? ('already_verified' as const)
            : ('invalid' as const);
        }

        const consumed = await transaction.verificationToken.updateMany({
          where: {
            tokenDigest,
            consumedAt: null,
            expiresAt: { gt: now },
          },
          data: { consumedAt: now },
        });
        if (consumed.count !== 1) {
          return 'invalid' as const;
        }

        await transaction.user.update({
          where: { id: token.userId },
          data: { emailVerified: true },
        });
        return 'verified' as const;
      },
    );

    if (outcome === 'invalid') {
      throw invalidVerificationTokenError();
    }
    return outcome;
  }

  /**
   * Re-sends the verification link for the authenticated owner. No-op when
   * already verified; DB-backed per-account cooldown throttles abuse; a
   * resend rotates the single outstanding token so old links stop working.
   */
  async resendVerification(userId: number): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user === null) {
      throw new AuthApplicationError(
        'AUTH_USER_NOT_FOUND',
        404,
        'User account was not found',
      );
    }
    if (user.emailVerified) {
      return;
    }

    const existing = await this.prisma.verificationToken.findUnique({
      where: {
        userId_purpose: { userId, purpose: EMAIL_VERIFICATION_PURPOSE },
      },
      select: { lastSentAt: true },
    });
    if (
      existing?.lastSentAt != null &&
      Date.now() - existing.lastSentAt.getTime() <
        VERIFICATION_RESEND_COOLDOWN_MS
    ) {
      throw verificationRateLimitedError();
    }

    const rawToken = await this.authSessions.withSerializableTransaction(
      (transaction) => this.issueVerificationToken(transaction, userId),
    );
    await this.deliverVerificationEmail(
      user.username,
      user.firstname,
      rawToken,
    );
  }

  async purgeExpiredVerificationTokens(now = new Date()): Promise<number> {
    const result = await this.prisma.verificationToken.deleteMany({
      where: { expiresAt: { lte: now } },
    });
    return result.count;
  }

  /**
   * Issues (or rotates) the single outstanding verification token for a user
   * inside an existing transaction. Only the SHA-256 digest is stored; the
   * returned raw token exists solely to be emailed.
   */
  private async issueVerificationToken(
    transaction: Prisma.TransactionClient,
    userId: number,
    now = new Date(),
  ): Promise<string> {
    const rawToken = randomBytes(32).toString('base64url');
    const tokenDigest = digestRefreshToken(rawToken);
    const expiresAt = new Date(now.getTime() + VERIFICATION_TOKEN_TTL_MS);

    await transaction.verificationToken.upsert({
      where: {
        userId_purpose: { userId, purpose: EMAIL_VERIFICATION_PURPOSE },
      },
      create: {
        userId,
        purpose: EMAIL_VERIFICATION_PURPOSE,
        tokenDigest,
        expiresAt,
        lastSentAt: now,
      },
      update: {
        tokenDigest,
        expiresAt,
        consumedAt: null,
        lastSentAt: now,
      },
    });
    return rawToken;
  }

  private async deliverVerificationEmail(
    to: string,
    firstname: string | null,
    rawToken: string,
  ): Promise<void> {
    if (this.emailSender === undefined || !this.emailSender.enabled) {
      return;
    }
    try {
      await this.emailSender.sendEmailVerification({ to, firstname, rawToken });
    } catch (error: unknown) {
      // Never log the token or recipient (PII); only the error category.
      const category = error instanceof Error ? error.name : 'UnknownError';
      console.error(`Verification email send failed (${category})`);
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

          // Safe automatic linking: a Google sign-in may merge onto an
          // existing local account ONLY when that account has independently
          // proven control of this email (emailVerified === true) and is not
          // already linked to a Google identity. Google itself already
          // enforced email_verified === true, so both sides then prove the
          // same mailbox and the link is safe. Any other case stays a hard
          // conflict — auto-linking an unverified account would let an
          // attacker pre-hijack it.
          const emailOwner = await transaction.user.findFirst({
            where: {
              username: {
                equals: identity.email,
                mode: 'insensitive',
              },
            },
          });
          if (emailOwner !== null) {
            if (
              emailOwner.emailVerified === true &&
              emailOwner.googleSubject === null
            ) {
              const linked = await transaction.user.updateMany({
                where: { id: emailOwner.id, googleSubject: null },
                data: { googleSubject: identity.subject },
              });
              if (linked.count === 1) {
                // Attaching a new sign-in method invalidates the account's
                // other sessions, mirroring a password change.
                await this.authSessions.revokeAllUserSessionsInTransaction(
                  transaction,
                  emailOwner.id,
                );
                return this.authSessions.issueSessionInTransaction(
                  transaction,
                  { ...emailOwner, googleSubject: identity.subject },
                );
              }
            }
            throw emailUnverifiedConflictError();
          }

          const user = await transaction.user.create({
            data: {
              username: identity.email,
              password: null,
              googleSubject: identity.subject,
              // Google already enforced email_verified === true, so a new
              // Google-origin account is verified at creation and needs no
              // verification email.
              emailVerified: true,
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
