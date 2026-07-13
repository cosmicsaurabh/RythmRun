import 'reflect-metadata';
import { jest } from '@jest/globals';

jest.unstable_mockModule('bcrypt', () => ({
  hash: jest.fn(),
  compare: jest.fn(),
}));

const bcrypt = await import('bcrypt');
const { UserService } = await import('../services/user.service.js');

const user = {
  id: 7,
  username: 'runner@example.com',
  password: 'stored-hash',
  firstname: 'Ada',
  lastname: 'Runner',
  profilePicturePath: null,
  profilePictureType: null,
  createdAt: new Date('2026-07-13T00:00:00.000Z'),
  updatedAt: new Date('2026-07-13T00:00:00.000Z'),
};

const authResponse = {
  id: user.id,
  username: user.username,
  firstname: user.firstname,
  lastname: user.lastname,
  profilePicturePath: null,
  profilePictureType: null,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
};

function harness() {
  const transaction = {
    user: {
      create: jest.fn().mockResolvedValue(user),
      findUnique: jest.fn().mockResolvedValue(user),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
  };
  const prisma = {
    user: {
      findUnique: jest.fn(),
      updateMany: jest.fn(),
    },
  };
  const authSessions = {
    withSerializableTransaction: jest.fn(
      async (operation: (value: typeof transaction) => Promise<unknown>) =>
        operation(transaction),
    ),
    issueSessionInTransaction: jest.fn().mockResolvedValue(authResponse),
    issueSession: jest.fn().mockResolvedValue(authResponse),
    rotateRefreshToken: jest.fn(),
    revokeSession: jest.fn(),
    revokeAllUserSessionsInTransaction: jest.fn().mockResolvedValue(undefined),
  };
  return {
    transaction,
    prisma,
    authSessions,
    service: new UserService(prisma as never, authSessions as never),
  };
}

describe('UserService authentication lifecycle', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('creates the user and its first session in one transaction', async () => {
    const { service, transaction, authSessions } = harness();
    jest.mocked(bcrypt.hash).mockResolvedValue('new-hash' as never);

    const result = await service.register({
      username: user.username,
      password: 'correct-horse-battery-staple',
      firstname: user.firstname ?? undefined,
      lastname: user.lastname ?? undefined,
    });

    expect(result).toEqual(authResponse);
    expect(transaction.user.create).toHaveBeenCalledWith({
      data: {
        username: user.username,
        password: 'new-hash',
        firstname: user.firstname,
        lastname: user.lastname,
      },
    });
    expect(authSessions.issueSessionInTransaction).toHaveBeenCalledWith(
      transaction,
      user,
    );
  });

  it('creates a separate session on valid login', async () => {
    const { service, prisma, transaction, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(user);
    jest.mocked(bcrypt.compare).mockResolvedValue(true as never);

    await expect(
      service.login({ username: user.username, password: 'valid-password' }),
    ).resolves.toEqual(authResponse);

    expect(authSessions.issueSessionInTransaction).toHaveBeenCalledWith(
      transaction,
      user,
    );
  });

  it.each([
    ['unknown username', null, true],
    ['wrong password', user, false],
  ])('uses one safe credential error for %s', async (_name, found, matches) => {
    const { service, prisma, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(found);
    jest.mocked(bcrypt.compare).mockResolvedValue(matches as never);

    await expect(
      service.login({ username: user.username, password: 'invalid-password' }),
    ).rejects.toMatchObject({
      code: 'AUTH_INVALID_CREDENTIALS',
      statusCode: 401,
      message: 'Invalid username or password',
    });
    expect(authSessions.issueSession).not.toHaveBeenCalled();
  });

  it('rejects a stale credential check if the password changes before issuance', async () => {
    const { service, prisma, transaction, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(user);
    transaction.user.findUnique.mockResolvedValue({
      ...user,
      password: 'concurrently-replaced-hash',
    });
    jest.mocked(bcrypt.compare).mockResolvedValue(true as never);

    await expect(
      service.login({ username: user.username, password: 'old-password' }),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });

    expect(authSessions.issueSessionInTransaction).not.toHaveBeenCalled();
  });

  it('updates the password and revokes every session in one transaction', async () => {
    const { service, prisma, transaction, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(user);
    jest.mocked(bcrypt.compare).mockResolvedValue(true as never);
    jest.mocked(bcrypt.hash).mockResolvedValue('replacement-hash' as never);

    await service.changePassword(user.id, {
      currentPassword: 'old-password',
      newPassword: 'new-password',
    });

    expect(transaction.user.updateMany).toHaveBeenCalledWith({
      where: { id: user.id, password: user.password },
      data: { password: 'replacement-hash' },
    });
    expect(
      authSessions.revokeAllUserSessionsInTransaction,
    ).toHaveBeenCalledWith(transaction, user.id);
  });

  it('does not write or revoke when the current password is wrong', async () => {
    const { service, prisma, transaction, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(user);
    jest.mocked(bcrypt.compare).mockResolvedValue(false as never);

    await expect(
      service.changePassword(user.id, {
        currentPassword: 'wrong-password',
        newPassword: 'new-password',
      }),
    ).rejects.toMatchObject({ code: 'AUTH_PASSWORD_INVALID' });

    expect(transaction.user.updateMany).not.toHaveBeenCalled();
    expect(authSessions.withSerializableTransaction).not.toHaveBeenCalled();
    expect(
      authSessions.revokeAllUserSessionsInTransaction,
    ).not.toHaveBeenCalled();
  });
});
