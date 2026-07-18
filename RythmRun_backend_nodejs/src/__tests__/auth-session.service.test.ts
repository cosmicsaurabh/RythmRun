import 'reflect-metadata';
import { randomUUID } from 'node:crypto';

import { jest } from '@jest/globals';
import jwt from 'jsonwebtoken';

import type { User } from '../generated/prisma/client.js';
import {
  ACCESS_TOKEN_LIFETIME_SECONDS,
  AuthSessionService,
  MAX_ACTIVE_SESSIONS_PER_USER,
  REFRESH_SESSION_LIFETIME_SECONDS,
  digestRefreshToken,
} from '../services/auth-session.service.js';

const ACCESS_SECRET = 'unit-access-secret-0123456789-abcdefgh';
const REFRESH_SECRET = 'unit-refresh-secret-0123456789-abcdefg';
const NOW = new Date('2026-07-13T10:00:00.000Z');

const user: User = {
  id: 7,
  username: 'runner@example.com',
  password: 'hashed-password',
  googleSubject: null,
  emailVerified: true,
  firstname: 'Ada',
  lastname: 'Runner',
  profilePicturePath: null,
  profilePictureType: null,
  createdAt: NOW,
  updatedAt: NOW,
};

function tokenPayload(token: string): jwt.JwtPayload {
  const decoded = jwt.decode(token);
  if (decoded === null || typeof decoded === 'string') {
    throw new Error('Expected a JWT payload');
  }
  return decoded;
}

function createTransaction(overrides: Record<string, unknown> = {}) {
  return {
    user: {
      create: jest.fn(),
      updateMany: jest.fn(),
    },
    authSession: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn(),
      create: jest.fn().mockResolvedValue(undefined),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    refreshTokenRecord: {
      findUnique: jest.fn(),
      create: jest.fn().mockResolvedValue(undefined),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    ...overrides,
  };
}

function createPrisma(transaction: ReturnType<typeof createTransaction>) {
  return {
    $transaction: jest.fn(
      async (operation: (value: typeof transaction) => Promise<unknown>) =>
        operation(transaction),
    ),
    authSession: {
      findFirst: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
}

function signRefresh(
  claims: Partial<jwt.JwtPayload> = {},
  secret = REFRESH_SECRET,
): string {
  const now = Math.floor(NOW.getTime() / 1000);
  return jwt.sign(
    {
      sub: String(user.id),
      sid: randomUUID(),
      jti: randomUUID(),
      typ: 'refresh',
      iat: now,
      exp: now + REFRESH_SESSION_LIFETIME_SECONDS,
      ...claims,
    },
    secret,
    { algorithm: 'HS256' },
  );
}

describe('AuthSessionService', () => {
  const originalAccessSecret = process.env.JWT_SECRET;
  const originalRefreshSecret = process.env.REFRESH_TOKEN_SECRET;

  beforeAll(() => {
    process.env.JWT_SECRET = ACCESS_SECRET;
    process.env.REFRESH_TOKEN_SECRET = REFRESH_SECRET;
  });

  beforeEach(() => {
    jest.useFakeTimers();
    jest.setSystemTime(NOW);
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  afterAll(() => {
    if (originalAccessSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = originalAccessSecret;
    if (originalRefreshSecret === undefined) {
      delete process.env.REFRESH_TOKEN_SECRET;
    } else {
      process.env.REFRESH_TOKEN_SECRET = originalRefreshSecret;
    }
  });

  it('issues standard claims and persists only a refresh digest', async () => {
    const transaction = createTransaction();
    const prisma = createPrisma(transaction);
    const service = new AuthSessionService(prisma as never);

    const response = await service.issueSession(user);
    const access = tokenPayload(response.accessToken);
    const refresh = tokenPayload(response.refreshToken);

    expect(Object.keys(response).sort()).toEqual([
      'accessToken',
      'emailVerified',
      'firstname',
      'hasPassword',
      'id',
      'lastname',
      'profilePicturePath',
      'profilePictureType',
      'refreshToken',
      'username',
    ]);
    expect(response.hasPassword).toBe(true);
    expect(access).toMatchObject({
      sub: String(user.id),
      sid: refresh.sid,
      typ: 'access',
    });
    expect(refresh).toMatchObject({
      sub: String(user.id),
      typ: 'refresh',
    });
    expect(access.jti).not.toBe(refresh.jti);
    expect(access.exp! - access.iat!).toBe(ACCESS_TOKEN_LIFETIME_SECONDS);
    expect(refresh.exp! - refresh.iat!).toBe(
      REFRESH_SESSION_LIFETIME_SECONDS,
    );

    const persisted = transaction.refreshTokenRecord.create.mock.calls[0][0];
    expect(persisted.data).toMatchObject({
      jti: refresh.jti,
      sessionId: refresh.sid,
      tokenDigest: digestRefreshToken(response.refreshToken),
    });
    expect(
      JSON.stringify({
        create: transaction.refreshTokenRecord.create.mock.calls,
        updateMany: transaction.refreshTokenRecord.updateMany.mock.calls,
      }),
    ).not.toContain(response.refreshToken);
  });

  it('evicts the least recently used session before creating session six', async () => {
    const transaction = createTransaction();
    const existing = Array.from(
      { length: MAX_ACTIVE_SESSIONS_PER_USER },
      () => ({ id: randomUUID() }),
    );
    transaction.authSession.findMany.mockResolvedValueOnce([]);
    transaction.authSession.findMany.mockResolvedValueOnce(existing);
    const prisma = createPrisma(transaction);
    const service = new AuthSessionService(prisma as never);

    await service.issueSession(user);

    expect(transaction.authSession.updateMany).toHaveBeenCalledWith({
      where: {
        id: { in: [existing[0].id] },
        status: 'ACTIVE',
        revokedAt: null,
      },
      data: { status: 'REVOKED', revokedAt: NOW },
    });
    expect(transaction.refreshTokenRecord.updateMany).toHaveBeenCalledWith({
      where: {
        sessionId: { in: [existing[0].id] },
        revokedAt: null,
      },
      data: { revokedAt: NOW },
    });
  });

  it('rotates once, links the successor, and preserves absolute expiry', async () => {
    const sid = randomUUID();
    const jti = randomUUID();
    const sessionExpiry = new Date(NOW.getTime() + 30 * 60 * 1000);
    const rawToken = signRefresh({ sid, jti, exp: sessionExpiry.getTime() / 1000 });
    const record = {
      jti,
      sessionId: sid,
      tokenDigest: digestRefreshToken(rawToken),
      issuedAt: NOW,
      expiresAt: sessionExpiry,
      usedAt: null,
      revokedAt: null,
      replacedByJti: null,
      session: {
        id: sid,
        userId: user.id,
        familyId: randomUUID(),
        status: 'ACTIVE',
        createdAt: NOW,
        lastUsedAt: NOW,
        expiresAt: sessionExpiry,
        revokedAt: null,
        user,
      },
    };
    const transaction = createTransaction();
    transaction.refreshTokenRecord.findUnique.mockResolvedValue(record);
    const prisma = createPrisma(transaction);
    const service = new AuthSessionService(prisma as never);

    const response = await service.rotateRefreshToken(rawToken);
    const replacement = tokenPayload(response.refreshToken);

    expect(replacement.sid).toBe(sid);
    expect(replacement.jti).not.toBe(jti);
    expect(replacement.exp).toBe(Math.floor(sessionExpiry.getTime() / 1000));
    expect(transaction.refreshTokenRecord.updateMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        where: expect.objectContaining({
          jti,
          tokenDigest: digestRefreshToken(rawToken),
          usedAt: null,
          revokedAt: null,
        }),
        data: { usedAt: NOW },
      }),
    );
    expect(transaction.refreshTokenRecord.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        jti: replacement.jti,
        sessionId: sid,
        tokenDigest: digestRefreshToken(response.refreshToken),
        expiresAt: sessionExpiry,
      }),
    });
    expect(transaction.refreshTokenRecord.updateMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        data: { replacedByJti: replacement.jti },
      }),
    );
    const refreshDatabaseCalls = JSON.stringify({
      create: transaction.refreshTokenRecord.create.mock.calls,
      updateMany: transaction.refreshTokenRecord.updateMany.mock.calls,
    });
    expect(refreshDatabaseCalls).not.toContain(rawToken);
    expect(refreshDatabaseCalls).not.toContain(response.refreshToken);
  });

  it('commits exact-replay family revocation before returning one generic error', async () => {
    const sid = randomUUID();
    const jti = randomUUID();
    const rawToken = signRefresh({ sid, jti });
    const transaction = createTransaction();
    transaction.refreshTokenRecord.findUnique.mockResolvedValue({
      jti,
      sessionId: sid,
      tokenDigest: digestRefreshToken(rawToken),
      issuedAt: NOW,
      expiresAt: new Date(NOW.getTime() + 60_000),
      usedAt: new Date(NOW.getTime() - 1000),
      revokedAt: null,
      replacedByJti: randomUUID(),
      session: {
        id: sid,
        userId: user.id,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: new Date(NOW.getTime() + 60_000),
        user,
      },
    });
    let transactionCallbackRejected = false;
    const prisma = createPrisma(transaction);
    prisma.$transaction.mockImplementation(async (operation) => {
      try {
        return await operation(transaction);
      } catch (error) {
        transactionCallbackRejected = true;
        throw error;
      }
    });
    const service = new AuthSessionService(prisma as never);

    await expect(service.rotateRefreshToken(rawToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_INVALID',
      statusCode: 401,
      message: 'Refresh session is invalid',
    });
    expect(transactionCallbackRejected).toBe(false);
    expect(transaction.authSession.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: { in: [sid] } }),
        data: { status: 'REVOKED', revokedAt: NOW },
      }),
    );
    expect(transaction.refreshTokenRecord.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: { revokedAt: NOW } }),
    );
  });

  it('does not revoke a family for a digest mismatch', async () => {
    const sid = randomUUID();
    const jti = randomUUID();
    const rawToken = signRefresh({ sid, jti });
    const transaction = createTransaction();
    transaction.refreshTokenRecord.findUnique.mockResolvedValue({
      jti,
      sessionId: sid,
      tokenDigest: digestRefreshToken(`${rawToken}-different`),
      usedAt: NOW,
      revokedAt: null,
      expiresAt: new Date(NOW.getTime() + 60_000),
      session: {
        id: sid,
        userId: user.id,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: new Date(NOW.getTime() + 60_000),
        user,
      },
    });
    const service = new AuthSessionService(createPrisma(transaction) as never);

    await expect(service.rotateRefreshToken(rawToken)).rejects.toMatchObject({
      code: 'AUTH_REFRESH_INVALID',
    });
    expect(transaction.authSession.updateMany).not.toHaveBeenCalled();
    expect(transaction.refreshTokenRecord.updateMany).not.toHaveBeenCalled();
  });

  it.each([
    ['wrong signature', () => signRefresh({}, ACCESS_SECRET)],
    ['wrong type', () => signRefresh({ typ: 'access' })],
    ['wrong subject shape', () => signRefresh({ sub: 7 })],
    ['missing sid', () => signRefresh({ sid: undefined })],
    ['malformed sid', () => signRefresh({ sid: 'not-a-uuid' })],
    ['missing jti', () => signRefresh({ jti: undefined })],
    [
      'expired token',
      () =>
        signRefresh({
          iat: Math.floor(NOW.getTime() / 1000) - 120,
          exp: Math.floor(NOW.getTime() / 1000) - 60,
        }),
    ],
  ])('maps %s to the same safe refresh error', async (_name, makeToken) => {
    const transaction = createTransaction();
    const prisma = createPrisma(transaction);
    const service = new AuthSessionService(prisma as never);

    await expect(service.rotateRefreshToken(makeToken())).rejects.toMatchObject({
      code: 'AUTH_REFRESH_INVALID',
      statusCode: 401,
      message: 'Refresh session is invalid',
    });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('requires the access JWT session to remain active', async () => {
    const transaction = createTransaction();
    const prisma = createPrisma(transaction);
    const service = new AuthSessionService(prisma as never);
    const response = await service.issueSession(user);
    prisma.authSession.findFirst.mockResolvedValue(null);

    await expect(
      service.authenticateAccessToken(response.accessToken),
    ).rejects.toMatchObject({
      code: 'AUTH_ACCESS_INVALID',
      statusCode: 401,
    });
    expect(prisma.authSession.findFirst).toHaveBeenCalledWith({
      where: expect.objectContaining({
        id: tokenPayload(response.accessToken).sid,
        userId: user.id,
        status: 'ACTIVE',
        revokedAt: null,
      }),
      select: { id: true },
    });
  });
});
