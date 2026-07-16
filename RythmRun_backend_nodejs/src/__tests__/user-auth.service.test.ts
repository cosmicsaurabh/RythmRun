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
  googleSubject: null,
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
  hasPassword: true,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
};

const googleIdentity = {
  subject: 'google-subject-123',
  email: 'google.runner@example.com',
  firstname: 'Grace',
  lastname: 'Runner',
};

const googleUser = {
  ...user,
  username: googleIdentity.email,
  password: null,
  googleSubject: googleIdentity.subject,
  firstname: googleIdentity.firstname,
  lastname: googleIdentity.lastname,
};

const googleAuthResponse = {
  ...authResponse,
  username: googleUser.username,
  firstname: googleUser.firstname,
  lastname: googleUser.lastname,
  hasPassword: false,
};

function harness() {
  const transaction = {
    user: {
      create: jest.fn().mockResolvedValue(user),
      findUnique: jest.fn().mockResolvedValue(user),
      findFirst: jest.fn().mockResolvedValue(null),
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
  const googleIdentityVerifier = {
    verifyIdToken: jest.fn().mockResolvedValue(googleIdentity),
  };
  return {
    transaction,
    prisma,
    authSessions,
    googleIdentityVerifier,
    service: new UserService(
      prisma as never,
      authSessions as never,
      googleIdentityVerifier,
    ),
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
      username: ' Runner@Example.COM ',
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
      service.login({
        username: ' Runner@Example.COM ',
        password: 'valid-password',
      }),
    ).resolves.toEqual(authResponse);

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { username: user.username },
    });
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

  it('creates a Google-only account and its first session atomically', async () => {
    const {
      service,
      transaction,
      authSessions,
      googleIdentityVerifier,
    } = harness();
    transaction.user.findUnique.mockResolvedValueOnce(null);
    transaction.user.create.mockResolvedValueOnce(googleUser);
    authSessions.issueSessionInTransaction.mockResolvedValueOnce(
      googleAuthResponse,
    );

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).resolves.toEqual(googleAuthResponse);

    expect(googleIdentityVerifier.verifyIdToken).toHaveBeenCalledWith(
      'google-id-token',
    );
    expect(transaction.user.create).toHaveBeenCalledWith({
      data: {
        username: googleIdentity.email,
        password: null,
        googleSubject: googleIdentity.subject,
        firstname: googleIdentity.firstname,
        lastname: googleIdentity.lastname,
      },
    });
    expect(authSessions.issueSessionInTransaction).toHaveBeenCalledWith(
      transaction,
      googleUser,
    );
  });

  it('signs in the account bound to the verified Google subject', async () => {
    const { service, transaction, authSessions } = harness();
    transaction.user.findUnique.mockResolvedValueOnce(googleUser);
    authSessions.issueSessionInTransaction.mockResolvedValueOnce(
      googleAuthResponse,
    );

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).resolves.toEqual(googleAuthResponse);

    expect(transaction.user.findUnique).toHaveBeenCalledWith({
      where: { googleSubject: googleIdentity.subject },
    });
    expect(transaction.user.create).not.toHaveBeenCalled();
    expect(authSessions.issueSessionInTransaction).toHaveBeenCalledWith(
      transaction,
      googleUser,
    );
  });

  it('does not auto-link a Google identity to an existing email account', async () => {
    const { service, transaction, authSessions } = harness();
    transaction.user.findUnique.mockResolvedValueOnce(null);
    transaction.user.findFirst.mockResolvedValueOnce({
      ...user,
      username: 'Google.Runner@Example.com',
    });

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).rejects.toMatchObject({
      code: 'AUTH_GOOGLE_ACCOUNT_CONFLICT',
      statusCode: 409,
    });

    expect(transaction.user.create).not.toHaveBeenCalled();
    expect(transaction.user.findFirst).toHaveBeenCalledWith({
      where: {
        username: {
          equals: googleIdentity.email,
          mode: 'insensitive',
        },
      },
    });
    expect(authSessions.issueSessionInTransaction).not.toHaveBeenCalled();
  });

  it('recovers a concurrent first sign-in only by exact Google subject', async () => {
    const { service, prisma, authSessions } = harness();
    authSessions.withSerializableTransaction.mockRejectedValueOnce({
      code: 'P2002',
    });
    prisma.user.findUnique.mockResolvedValueOnce(googleUser);
    authSessions.issueSession.mockResolvedValueOnce(googleAuthResponse);

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).resolves.toEqual(googleAuthResponse);

    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { googleSubject: googleIdentity.subject },
    });
    expect(authSessions.issueSession).toHaveBeenCalledWith(googleUser);
  });

  it('rejects a case-variant password registration after Google sign-in', async () => {
    const { service, prisma, transaction } = harness();
    jest.mocked(bcrypt.hash).mockResolvedValue('new-hash' as never);
    transaction.user.create.mockRejectedValueOnce({ code: 'P2002' });
    prisma.user.findUnique.mockResolvedValueOnce(googleUser);

    await expect(
      service.register({
        username: ' Google.Runner@Example.COM ',
        password: 'correct-horse-battery-staple',
      }),
    ).rejects.toMatchObject({
      code: 'AUTH_USERNAME_TAKEN',
      statusCode: 409,
    });

    expect(transaction.user.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ username: googleIdentity.email }),
    });
    expect(prisma.user.findUnique).toHaveBeenCalledWith({
      where: { username: googleIdentity.email },
      select: { id: true },
    });
  });

  it('rejects password authentication for a Google-only account', async () => {
    const { service, prisma } = harness();
    prisma.user.findUnique.mockResolvedValue(googleUser);

    await expect(
      service.login({
        username: googleUser.username,
        password: 'not-a-provider-password',
      }),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });

    expect(bcrypt.compare).not.toHaveBeenCalled();
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

  it('rejects password changes for a Google-only account', async () => {
    const { service, prisma, authSessions } = harness();
    prisma.user.findUnique.mockResolvedValue(googleUser);

    await expect(
      service.changePassword(googleUser.id, {
        currentPassword: 'not-a-provider-password',
        newPassword: 'new-password',
      }),
    ).rejects.toMatchObject({
      code: 'AUTH_PASSWORD_UNAVAILABLE',
      statusCode: 409,
    });

    expect(bcrypt.compare).not.toHaveBeenCalled();
    expect(authSessions.withSerializableTransaction).not.toHaveBeenCalled();
  });
});
