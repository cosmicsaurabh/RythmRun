import { createHash, randomUUID } from 'node:crypto';

import jwt from 'jsonwebtoken';
import { inject, injectable } from 'tsyringe';

import { getJwtSecrets, type AuthTimingEnvironment } from '../config/env.js';
import {
  Prisma,
  type PrismaClient,
  type User,
} from '../generated/prisma/client.js';
import {
  invalidAccessError,
  invalidRefreshError,
} from '../errors/auth.error.js';

export const REFRESH_DIGEST_ALGORITHM = 'sha256';

const MAX_SERIALIZABLE_ATTEMPTS = 3;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type TransactionClient = Prisma.TransactionClient;
type TokenType = 'access' | 'refresh';

interface TokenClaims {
  sub: string;
  sid: string;
  jti: string;
  typ: TokenType;
  iat: number;
  exp: number;
}

export interface SafeUserResponse {
  id: number;
  username: string;
  firstname: string | null;
  lastname: string | null;
  profilePicturePath: string | null;
  profilePictureType: string | null;
  hasPassword: boolean;
  emailVerified: boolean;
}

export interface AuthResponse extends SafeUserResponse {
  accessToken: string;
  refreshToken: string;
}

export interface AuthenticatedPrincipal {
  userId: number;
  sessionId: string;
  tokenId: string;
}

interface IssuedTokenPair {
  accessToken: string;
  refreshToken: string;
  refreshJti: string;
  refreshDigest: string;
}

type RotationResult =
  | { kind: 'invalid' | 'reused' }
  | { kind: 'success'; response: AuthResponse };

function isSerializationFailure(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'P2034'
  );
}

function isExactDigest(left: string, right: string): boolean {
  return left.length === 64 && right.length === 64 && left === right;
}

export function digestRefreshToken(token: string): string {
  return createHash(REFRESH_DIGEST_ALGORITHM).update(token).digest('hex');
}

export function toSafeUserResponse(user: User): SafeUserResponse {
  return {
    id: user.id,
    username: user.username,
    firstname: user.firstname,
    lastname: user.lastname,
    profilePicturePath: user.profilePicturePath,
    profilePictureType: user.profilePictureType,
    hasPassword: user.password !== null,
    emailVerified: user.emailVerified,
  };
}

@injectable()
export class AuthSessionService {
  constructor(
    @inject('PrismaClient') private readonly prisma: PrismaClient,
    @inject('AuthTiming') private readonly authTiming: AuthTimingEnvironment,
  ) {}

  async withSerializableTransaction<T>(
    operation: (transaction: TransactionClient) => Promise<T>,
  ): Promise<T> {
    for (let attempt = 0; attempt < MAX_SERIALIZABLE_ATTEMPTS; attempt += 1) {
      try {
        return await this.prisma.$transaction(operation, {
          isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        });
      } catch (error: unknown) {
        if (
          isSerializationFailure(error) &&
          attempt < MAX_SERIALIZABLE_ATTEMPTS - 1
        ) {
          continue;
        }
        throw error;
      }
    }

    throw new Error('Serializable authentication transaction did not finish');
  }

  async issueSession(user: User): Promise<AuthResponse> {
    return this.withSerializableTransaction((transaction) =>
      this.issueSessionInTransaction(transaction, user),
    );
  }

  async issueSessionInTransaction(
    transaction: TransactionClient,
    user: User,
    now = new Date(),
  ): Promise<AuthResponse> {
    await this.revokeExpiredSessionsInTransaction(
      transaction,
      user.id,
      now,
    );

    const activeSessions = await transaction.authSession.findMany({
      where: {
        userId: user.id,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: { gt: now },
      },
      orderBy: [{ lastUsedAt: 'asc' }, { createdAt: 'asc' }, { id: 'asc' }],
      select: { id: true },
    });
    const overflowCount =
      activeSessions.length - this.authTiming.maxActiveSessionsPerUser + 1;
    if (overflowCount > 0) {
      await this.revokeSessionIdsInTransaction(
        transaction,
        activeSessions
          .slice(0, overflowCount)
          .map((session: { id: string }) => session.id),
        now,
      );
    }

    const sessionId = randomUUID();
    const familyId = randomUUID();
    const expiresAt = new Date(
      now.getTime() + this.authTiming.refreshSessionTtlSeconds * 1000,
    );
    const tokenPair = this.createTokenPair(user.id, sessionId, expiresAt, now);

    await transaction.authSession.create({
      data: {
        id: sessionId,
        familyId,
        userId: user.id,
        createdAt: now,
        lastUsedAt: now,
        expiresAt,
      },
    });
    await transaction.refreshTokenRecord.create({
      data: {
        jti: tokenPair.refreshJti,
        sessionId,
        tokenDigest: tokenPair.refreshDigest,
        issuedAt: now,
        expiresAt,
      },
    });

    return {
      ...toSafeUserResponse(user),
      accessToken: tokenPair.accessToken,
      refreshToken: tokenPair.refreshToken,
    };
  }

  async rotateRefreshToken(rawRefreshToken: string): Promise<AuthResponse> {
    const claims = this.verifyToken(
      rawRefreshToken,
      'refresh',
      getJwtSecrets().refreshSecret,
    );
    if (claims === null) {
      throw invalidRefreshError();
    }

    const presentedDigest = digestRefreshToken(rawRefreshToken);
    const result = await this.withSerializableTransaction<RotationResult>(
      async (transaction) => {
        // Refresh this on every Serializable retry so an operation cannot use
        // a token that expired while waiting on a conflicting transaction.
        const now = new Date();
        const record = await transaction.refreshTokenRecord.findUnique({
          where: { jti: claims.jti },
          include: { session: { include: { user: true } } },
        });
        if (record === null) {
          return { kind: 'invalid' };
        }

        const digestMatches = isExactDigest(
          record.tokenDigest,
          presentedDigest,
        );
        const identityMatches =
          record.sessionId === claims.sid &&
          record.session.userId === Number(claims.sub);
        if (!digestMatches || !identityMatches) {
          return { kind: 'invalid' };
        }

        if (record.usedAt !== null) {
          if (
            record.session.status === 'ACTIVE' &&
            record.session.revokedAt === null
          ) {
            await this.revokeSessionFamilyInTransaction(
              transaction,
              record.session.id,
              now,
            );
          }
          return { kind: 'reused' };
        }

        if (
          record.revokedAt !== null ||
          record.expiresAt <= now ||
          record.session.status !== 'ACTIVE' ||
          record.session.revokedAt !== null ||
          record.session.expiresAt <= now
        ) {
          return { kind: 'invalid' };
        }

        const activeSession = await transaction.authSession.updateMany({
          where: {
            id: record.session.id,
            userId: record.session.userId,
            status: 'ACTIVE',
            revokedAt: null,
            expiresAt: { gt: now },
          },
          data: { lastUsedAt: now },
        });
        if (activeSession.count !== 1) {
          return { kind: 'invalid' };
        }

        const consumed = await transaction.refreshTokenRecord.updateMany({
          where: {
            jti: claims.jti,
            sessionId: claims.sid,
            tokenDigest: presentedDigest,
            usedAt: null,
            revokedAt: null,
            expiresAt: { gt: now },
          },
          data: { usedAt: now },
        });
        if (consumed.count !== 1) {
          const current = await transaction.refreshTokenRecord.findUnique({
            where: { jti: claims.jti },
          });
          if (
            current !== null &&
            current.usedAt !== null &&
            isExactDigest(current.tokenDigest, presentedDigest)
          ) {
            await this.revokeSessionFamilyInTransaction(
              transaction,
              record.session.id,
              now,
            );
            return { kind: 'reused' };
          }
          return { kind: 'invalid' };
        }

        const tokenPair = this.createTokenPair(
          record.session.userId,
          record.session.id,
          record.session.expiresAt,
          now,
        );
        await transaction.refreshTokenRecord.create({
          data: {
            jti: tokenPair.refreshJti,
            sessionId: record.session.id,
            tokenDigest: tokenPair.refreshDigest,
            issuedAt: now,
            expiresAt: record.session.expiresAt,
          },
        });
        const linked = await transaction.refreshTokenRecord.updateMany({
          where: {
            jti: claims.jti,
            usedAt: now,
            replacedByJti: null,
          },
          data: { replacedByJti: tokenPair.refreshJti },
        });
        if (linked.count !== 1) {
          throw new Error('Refresh rotation link invariant failed');
        }

        return {
          kind: 'success',
          response: {
            ...toSafeUserResponse(record.session.user),
            accessToken: tokenPair.accessToken,
            refreshToken: tokenPair.refreshToken,
          },
        };
      },
    );

    if (result.kind !== 'success') {
      // Reuse revocation must commit before the public error is thrown.
      throw invalidRefreshError();
    }
    return result.response;
  }

  async authenticateAccessToken(
    rawAccessToken: string,
  ): Promise<AuthenticatedPrincipal> {
    const claims = this.verifyToken(
      rawAccessToken,
      'access',
      getJwtSecrets().accessSecret,
    );
    if (claims === null) {
      throw invalidAccessError();
    }

    const userId = Number(claims.sub);
    const session = await this.prisma.authSession.findFirst({
      where: {
        id: claims.sid,
        userId,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: { id: true },
    });
    if (session === null) {
      throw invalidAccessError();
    }

    return {
      userId,
      sessionId: session.id,
      tokenId: claims.jti,
    };
  }

  async revokeSession(userId: number, sessionId: string): Promise<void> {
    await this.withSerializableTransaction(async (transaction) => {
      const session = await transaction.authSession.findFirst({
        where: { id: sessionId, userId },
        select: { id: true },
      });
      if (session !== null) {
        await this.revokeSessionIdsInTransaction(
          transaction,
          [session.id],
          new Date(),
        );
      }
    });
  }

  async revokeAllUserSessions(userId: number): Promise<void> {
    await this.withSerializableTransaction((transaction) =>
      this.revokeAllUserSessionsInTransaction(transaction, userId),
    );
  }

  async revokeAllUserSessionsInTransaction(
    transaction: TransactionClient,
    userId: number,
    now = new Date(),
  ): Promise<void> {
    const sessions = await transaction.authSession.findMany({
      where: { userId },
      select: { id: true },
    });
    await this.revokeSessionIdsInTransaction(
      transaction,
      sessions.map((session: { id: string }) => session.id),
      now,
    );
  }

  async purgeExpiredSessions(now = new Date()): Promise<number> {
    const result = await this.prisma.authSession.deleteMany({
      where: { expiresAt: { lte: now } },
    });
    return result.count;
  }

  private createTokenPair(
    userId: number,
    sessionId: string,
    sessionExpiresAt: Date,
    now: Date,
  ): IssuedTokenPair {
    const issuedAt = Math.floor(now.getTime() / 1000);
    const sessionExpiry = Math.floor(sessionExpiresAt.getTime() / 1000);
    if (sessionExpiry <= issuedAt) {
      throw invalidRefreshError();
    }

    const accessJti = randomUUID();
    const refreshJti = randomUUID();
    const accessClaims: TokenClaims = {
      sub: String(userId),
      sid: sessionId,
      jti: accessJti,
      typ: 'access',
      iat: issuedAt,
      exp: Math.min(
        issuedAt + this.authTiming.accessTokenTtlSeconds,
        sessionExpiry,
      ),
    };
    const refreshClaims: TokenClaims = {
      sub: String(userId),
      sid: sessionId,
      jti: refreshJti,
      typ: 'refresh',
      iat: issuedAt,
      exp: sessionExpiry,
    };
    const secrets = getJwtSecrets();
    const accessToken = jwt.sign(accessClaims, secrets.accessSecret, {
      algorithm: 'HS256',
    });
    const refreshToken = jwt.sign(refreshClaims, secrets.refreshSecret, {
      algorithm: 'HS256',
    });

    return {
      accessToken,
      refreshToken,
      refreshJti,
      refreshDigest: digestRefreshToken(refreshToken),
    };
  }

  private verifyToken(
    token: string,
    expectedType: TokenType,
    secret: string,
  ): TokenClaims | null {
    if (typeof token !== 'string' || token.length === 0) {
      return null;
    }

    try {
      const decoded = jwt.verify(token, secret, { algorithms: ['HS256'] });
      if (typeof decoded === 'string') {
        return null;
      }

      const subject = decoded.sub;
      const issuedAt = decoded.iat;
      const expiresAt = decoded.exp;
      const userId = typeof subject === 'string' ? Number(subject) : NaN;
      if (
        typeof subject !== 'string' ||
        !Number.isSafeInteger(userId) ||
        userId <= 0 ||
        String(userId) !== subject ||
        decoded.typ !== expectedType ||
        typeof decoded.sid !== 'string' ||
        !UUID_PATTERN.test(decoded.sid) ||
        typeof decoded.jti !== 'string' ||
        !UUID_PATTERN.test(decoded.jti) ||
        typeof issuedAt !== 'number' ||
        !Number.isInteger(issuedAt) ||
        typeof expiresAt !== 'number' ||
        !Number.isInteger(expiresAt) ||
        expiresAt <= issuedAt
      ) {
        return null;
      }

      return {
        sub: subject,
        sid: decoded.sid,
        jti: decoded.jti,
        typ: expectedType,
        iat: issuedAt,
        exp: expiresAt,
      };
    } catch {
      return null;
    }
  }

  private async revokeExpiredSessionsInTransaction(
    transaction: TransactionClient,
    userId: number,
    now: Date,
  ): Promise<void> {
    const expired = await transaction.authSession.findMany({
      where: {
        userId,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: { lte: now },
      },
      select: { id: true },
    });
    await this.revokeSessionIdsInTransaction(
      transaction,
      expired.map((session: { id: string }) => session.id),
      now,
    );
  }

  private async revokeSessionFamilyInTransaction(
    transaction: TransactionClient,
    sessionId: string,
    now: Date,
  ): Promise<void> {
    await this.revokeSessionIdsInTransaction(transaction, [sessionId], now);
  }

  private async revokeSessionIdsInTransaction(
    transaction: TransactionClient,
    sessionIds: string[],
    now: Date,
  ): Promise<void> {
    if (sessionIds.length === 0) {
      return;
    }

    await transaction.authSession.updateMany({
      where: {
        id: { in: sessionIds },
        status: 'ACTIVE',
        revokedAt: null,
      },
      data: { status: 'REVOKED', revokedAt: now },
    });
    await transaction.refreshTokenRecord.updateMany({
      where: {
        sessionId: { in: sessionIds },
        revokedAt: null,
      },
      data: { revokedAt: now },
    });
  }
}
