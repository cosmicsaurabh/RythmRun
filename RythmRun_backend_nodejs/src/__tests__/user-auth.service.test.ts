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
      update: jest.fn().mockResolvedValue(user),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    verificationToken: {
      upsert: jest.fn().mockResolvedValue({}),
      findUnique: jest.fn().mockResolvedValue(null),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
  };
  const prisma = {
    user: {
      findUnique: jest.fn(),
      updateMany: jest.fn(),
    },
    verificationToken: {
      findUnique: jest.fn().mockResolvedValue(null),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
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
  const emailSender = {
    enabled: true,
    sendEmailVerification: jest.fn().mockResolvedValue(undefined),
  };
  return {
    transaction,
    prisma,
    authSessions,
    googleIdentityVerifier,
    emailSender,
    service: new UserService(
      prisma as never,
      authSessions as never,
      googleIdentityVerifier,
      emailSender as never,
    ),
  };
}

describe('UserService authentication lifecycle', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('creates the user and its first session in one transaction', async () => {
    const { service, transaction, authSessions, emailSender } = harness();
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
    // A verification token is issued in-transaction and the email is sent
    // afterwards (post-commit, best-effort).
    expect(transaction.verificationToken.upsert).toHaveBeenCalledTimes(1);
    expect(emailSender.sendEmailVerification).toHaveBeenCalledTimes(1);
  });

  it('still registers when the post-commit verification email fails', async () => {
    const { service, emailSender } = harness();
    jest.mocked(bcrypt.hash).mockResolvedValue('new-hash' as never);
    emailSender.sendEmailVerification.mockRejectedValueOnce(
      new Error('SMTP down'),
    );

    await expect(
      service.register({
        username: 'runner@example.com',
        password: 'correct-horse-battery-staple',
      }),
    ).resolves.toEqual(authResponse);
  });

  it('verifies an email with a valid unconsumed token', async () => {
    const { service, transaction } = harness();
    transaction.verificationToken.findUnique.mockResolvedValueOnce({
      userId: user.id,
      tokenDigest: 'digest',
      consumedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });
    transaction.verificationToken.updateMany.mockResolvedValueOnce({
      count: 1,
    });

    await expect(service.verifyEmail('raw-token')).resolves.toBe('verified');
    expect(transaction.user.update).toHaveBeenCalledWith({
      where: { id: user.id },
      data: { emailVerified: true },
    });
  });

  it('is idempotent for a consumed token on an already-verified user', async () => {
    const { service, transaction } = harness();
    transaction.verificationToken.findUnique.mockResolvedValueOnce({
      userId: user.id,
      consumedAt: new Date(),
      expiresAt: new Date(Date.now() + 60_000),
    });
    transaction.user.findUnique.mockResolvedValueOnce({ emailVerified: true });

    await expect(service.verifyEmail('raw-token')).resolves.toBe(
      'already_verified',
    );
    expect(transaction.user.update).not.toHaveBeenCalled();
  });

  it('rejects an unknown verification token', async () => {
    const { service, transaction } = harness();
    transaction.verificationToken.findUnique.mockResolvedValueOnce(null);

    await expect(service.verifyEmail('raw-token')).rejects.toMatchObject({
      code: 'AUTH_VERIFICATION_TOKEN_INVALID',
    });
  });

  it('rejects an empty token without touching the database', async () => {
    const { service, authSessions } = harness();

    await expect(service.verifyEmail('')).rejects.toMatchObject({
      code: 'AUTH_VERIFICATION_TOKEN_INVALID',
    });
    expect(authSessions.withSerializableTransaction).not.toHaveBeenCalled();
  });

  it('resends verification and rotates the token for an unverified user', async () => {
    const { service, prisma, transaction, emailSender } = harness();
    prisma.user.findUnique.mockResolvedValueOnce({
      ...user,
      emailVerified: false,
    });
    prisma.verificationToken.findUnique.mockResolvedValueOnce({
      lastSentAt: null,
    });

    await service.resendVerification(user.id);

    expect(transaction.verificationToken.upsert).toHaveBeenCalledTimes(1);
    expect(emailSender.sendEmailVerification).toHaveBeenCalledTimes(1);
  });

  it('does not resend for an already-verified account', async () => {
    const { service, prisma, authSessions, emailSender } = harness();
    prisma.user.findUnique.mockResolvedValueOnce({
      ...user,
      emailVerified: true,
    });

    await service.resendVerification(user.id);

    expect(authSessions.withSerializableTransaction).not.toHaveBeenCalled();
    expect(emailSender.sendEmailVerification).not.toHaveBeenCalled();
  });

  it('throttles a resend inside the cooldown window', async () => {
    const { service, prisma, emailSender } = harness();
    prisma.user.findUnique.mockResolvedValueOnce({
      ...user,
      emailVerified: false,
    });
    prisma.verificationToken.findUnique.mockResolvedValueOnce({
      lastSentAt: new Date(),
    });

    await expect(service.resendVerification(user.id)).rejects.toMatchObject({
      code: 'AUTH_VERIFICATION_RATE_LIMITED',
      statusCode: 429,
    });
    expect(emailSender.sendEmailVerification).not.toHaveBeenCalled();
  });

  it('purges expired verification tokens', async () => {
    const { service, prisma } = harness();
    prisma.verificationToken.deleteMany.mockResolvedValueOnce({ count: 3 });

    await expect(service.purgeExpiredVerificationTokens()).resolves.toBe(3);
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
        emailVerified: true,
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

  it('refuses to link Google to an unverified existing email account', async () => {
    const { service, transaction, authSessions } = harness();
    transaction.user.findUnique.mockResolvedValueOnce(null);
    transaction.user.findFirst.mockResolvedValueOnce({
      ...user,
      username: 'Google.Runner@Example.com',
      emailVerified: false,
      googleSubject: null,
    });

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).rejects.toMatchObject({
      code: 'AUTH_EMAIL_UNVERIFIED_CONFLICT',
      statusCode: 409,
    });

    expect(transaction.user.create).not.toHaveBeenCalled();
    expect(transaction.user.updateMany).not.toHaveBeenCalled();
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

  it('auto-links Google to a verified email account and revokes other sessions', async () => {
    const { service, transaction, authSessions } = harness();
    const verifiedOwner = {
      ...user,
      username: googleIdentity.email,
      emailVerified: true,
      googleSubject: null,
    };
    transaction.user.findUnique.mockResolvedValueOnce(null);
    transaction.user.findFirst.mockResolvedValueOnce(verifiedOwner);
    transaction.user.updateMany.mockResolvedValueOnce({ count: 1 });
    authSessions.issueSessionInTransaction.mockResolvedValueOnce(
      googleAuthResponse,
    );

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).resolves.toEqual(googleAuthResponse);

    expect(transaction.user.updateMany).toHaveBeenCalledWith({
      where: { id: verifiedOwner.id, googleSubject: null },
      data: { googleSubject: googleIdentity.subject },
    });
    expect(
      authSessions.revokeAllUserSessionsInTransaction,
    ).toHaveBeenCalledWith(transaction, verifiedOwner.id);
    expect(transaction.user.create).not.toHaveBeenCalled();
    expect(authSessions.issueSessionInTransaction).toHaveBeenCalledWith(
      transaction,
      { ...verifiedOwner, googleSubject: googleIdentity.subject },
    );
  });

  it('keeps a hard conflict when a verified account is already linked', async () => {
    const { service, transaction, authSessions } = harness();
    transaction.user.findUnique.mockResolvedValueOnce(null);
    transaction.user.findFirst.mockResolvedValueOnce({
      ...user,
      username: googleIdentity.email,
      emailVerified: true,
      googleSubject: 'a-different-google-subject',
    });

    await expect(
      service.googleLogin({ idToken: 'google-id-token' }),
    ).rejects.toMatchObject({
      code: 'AUTH_EMAIL_UNVERIFIED_CONFLICT',
      statusCode: 409,
    });

    expect(transaction.user.updateMany).not.toHaveBeenCalled();
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
