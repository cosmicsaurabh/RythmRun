import 'reflect-metadata';
import jwt from 'jsonwebtoken';

import {
  createDatabase,
  type DatabaseRuntime,
} from '../config/database.js';
import {
  AuthSessionService,
  digestRefreshToken,
} from '../services/auth-session.service.js';
import { UserService } from '../services/user.service.js';

const RUN_INTEGRATION = process.env.RUN_DATABASE_INTEGRATION === '1';
const integrationDescribe = RUN_INTEGRATION ? describe : describe.skip;
const ACCESS_SECRET = 'integration-access-secret-0123456789-abcdef';
const REFRESH_SECRET = 'integration-refresh-secret-0123456789-abcde';
const PASSWORD = 'correct-horse-battery-staple';

function requireTestDatabaseUrl(): string {
  const databaseUrl = process.env.DATABASE_URL;
  if (databaseUrl === undefined) {
    throw new Error('DATABASE_URL is required for database integration tests');
  }

  const parsed = new URL(databaseUrl);
  const databaseName = parsed.pathname.slice(1);
  const isLoopback = ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(
    parsed.hostname,
  );
  const isClearlyTestNamed = /(?:^|[_-])(?:test|ci)(?:$|[_-])/i.test(
    databaseName,
  );
  if (
    !['postgres:', 'postgresql:'].includes(parsed.protocol) ||
    !isLoopback ||
    !isClearlyTestNamed
  ) {
    throw new Error(
      'Refusing destructive auth integration tests outside a loopback test/CI database',
    );
  }
  return databaseUrl;
}

function claims(token: string): jwt.JwtPayload {
  const decoded = jwt.decode(token);
  if (decoded === null || typeof decoded === 'string') {
    throw new Error('Expected token claims');
  }
  return decoded;
}

integrationDescribe('auth sessions on PostgreSQL', () => {
  let databaseA!: DatabaseRuntime;
  let databaseB!: DatabaseRuntime;
  let sessionsA: AuthSessionService;
  let sessionsB: AuthSessionService;
  let usersA: UserService;
  let usersB: UserService;
  const originalAccessSecret = process.env.JWT_SECRET;
  const originalRefreshSecret = process.env.REFRESH_TOKEN_SECRET;

  beforeAll(() => {
    process.env.JWT_SECRET = ACCESS_SECRET;
    process.env.REFRESH_TOKEN_SECRET = REFRESH_SECRET;
    const databaseUrl = requireTestDatabaseUrl();
    databaseA = createDatabase(databaseUrl);
    databaseB = createDatabase(databaseUrl);
    sessionsA = new AuthSessionService(databaseA.client);
    sessionsB = new AuthSessionService(databaseB.client);
    usersA = new UserService(databaseA.client, sessionsA);
    usersB = new UserService(databaseB.client, sessionsB);
  });

  beforeEach(async () => {
    await databaseA.client.user.deleteMany();
  });

  afterEach(async () => {
    await databaseA?.client.user.deleteMany();
  });

  afterAll(async () => {
    await Promise.all([
      databaseA?.disconnect() ?? Promise.resolve(),
      databaseB?.disconnect() ?? Promise.resolve(),
    ]);
    if (originalAccessSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = originalAccessSecret;
    if (originalRefreshSecret === undefined) {
      delete process.env.REFRESH_TOKEN_SECRET;
    } else {
      process.env.REFRESH_TOKEN_SECRET = originalRefreshSecret;
    }
  });

  async function register(username = 'runner@example.com') {
    return usersA.register({
      username,
      password: PASSWORD,
      firstname: 'Ada',
      lastname: 'Runner',
    });
  }

  it('persists register/login sessions as digests and returns one flat contract', async () => {
    const registered = await register();
    const loggedIn = await usersB.login({
      username: ' Runner@Example.COM ',
      password: PASSWORD,
    });
    const expectedKeys = [
      'accessToken',
      'firstname',
      'hasPassword',
      'id',
      'lastname',
      'profilePicturePath',
      'profilePictureType',
      'refreshToken',
      'username',
    ];

    expect(Object.keys(registered).sort()).toEqual(expectedKeys);
    expect(Object.keys(loggedIn).sort()).toEqual(expectedKeys);
    expect(registered.hasPassword).toBe(true);
    expect(loggedIn.hasPassword).toBe(true);
    expect(claims(registered.accessToken)).toMatchObject({
      sub: String(registered.id),
      sid: claims(registered.refreshToken).sid,
      typ: 'access',
    });
    expect(claims(registered.refreshToken).typ).toBe('refresh');

    const records = await databaseA.client.refreshTokenRecord.findMany({
      orderBy: { issuedAt: 'asc' },
      select: { tokenDigest: true },
    });
    expect(records).toHaveLength(2);
    expect(records.map((record) => record.tokenDigest)).toEqual(
      expect.arrayContaining([
        digestRefreshToken(registered.refreshToken),
        digestRefreshToken(loggedIn.refreshToken),
      ]),
    );
    expect(JSON.stringify(records)).not.toContain(registered.refreshToken);
    expect(JSON.stringify(records)).not.toContain(loggedIn.refreshToken);
    await expect(
      usersB.register({
        username: registered.username,
        password: PASSWORD,
      }),
    ).rejects.toMatchObject({
      code: 'AUTH_USERNAME_TAKEN',
      statusCode: 409,
    });

    const legacyColumns = await databaseA.client.$queryRaw<
      Array<{ column_name: string }>
    >`SELECT column_name FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'RefreshToken'`;
    expect(legacyColumns).toEqual([]);
  });

  it('persists Google subject identity without a password and rejects email auto-linking', async () => {
    const googleIdentity = {
      subject: 'google-integration-subject',
      email: 'google.runner@example.com',
      firstname: 'Grace',
      lastname: 'Runner',
    };
    const googleUsers = new UserService(databaseA.client, sessionsA, {
      verifyIdToken: async () => googleIdentity,
    });

    const authenticated = await googleUsers.googleLogin({
      idToken: 'test-verifier-token',
    });
    expect(Object.keys(authenticated).sort()).toEqual([
      'accessToken',
      'firstname',
      'hasPassword',
      'id',
      'lastname',
      'profilePicturePath',
      'profilePictureType',
      'refreshToken',
      'username',
    ]);
    expect(authenticated.hasPassword).toBe(false);
    await expect(
      databaseA.client.user.findUniqueOrThrow({
        where: { id: authenticated.id },
        select: { googleSubject: true, password: true },
      }),
    ).resolves.toEqual({
      googleSubject: googleIdentity.subject,
      password: null,
    });
    await expect(
      googleUsers.login({
        username: authenticated.username,
        password: PASSWORD,
      }),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
    await expect(
      googleUsers.changePassword(authenticated.id, {
        currentPassword: PASSWORD,
        newPassword: 'replacement-password-123',
      }),
    ).rejects.toMatchObject({ code: 'AUTH_PASSWORD_UNAVAILABLE' });
    await expect(
      usersA.register({
        username: ' Google.Runner@Example.COM ',
        password: PASSWORD,
      }),
    ).rejects.toMatchObject({
      code: 'AUTH_USERNAME_TAKEN',
      statusCode: 409,
    });
    await expect(
      databaseA.client.$executeRaw`
        UPDATE "User"
        SET "username" = 'Google.Runner@Example.com'
        WHERE "id" = ${authenticated.id}
      `,
    ).rejects.toThrow();

    await register('collision@example.com');
    const conflictingGoogleUsers = new UserService(
      databaseA.client,
      sessionsA,
      {
        verifyIdToken: async () => ({
          ...googleIdentity,
          subject: 'different-google-subject',
          email: 'collision@example.com',
        }),
      },
    );
    await expect(
      conflictingGoogleUsers.googleLogin({ idToken: 'test-verifier-token' }),
    ).rejects.toMatchObject({
      code: 'AUTH_GOOGLE_ACCOUNT_CONFLICT',
      statusCode: 409,
    });
  });

  it('allows at most one concurrent rotation and commits replay revocation', async () => {
    const initial = await register();
    const attempts = await Promise.allSettled([
      sessionsA.rotateRefreshToken(initial.refreshToken),
      sessionsB.rotateRefreshToken(initial.refreshToken),
    ]);
    const winners = attempts.filter(
      (result): result is PromiseFulfilledResult<Awaited<typeof initial>> =>
        result.status === 'fulfilled',
    );

    expect(winners).toHaveLength(1);
    const sid = String(claims(initial.refreshToken).sid);
    const session = await databaseA.client.authSession.findUniqueOrThrow({
      where: { id: sid },
      include: { refreshTokens: true },
    });
    const initialJti = String(claims(initial.refreshToken).jti);
    const originalRecord = session.refreshTokens.find(
      (record) => record.jti === initialJti,
    );
    const replacementRecord = session.refreshTokens.find(
      (record) => record.jti === originalRecord?.replacedByJti,
    );
    expect(session.status).toBe('REVOKED');
    expect(session.revokedAt).not.toBeNull();
    expect(session.refreshTokens).toHaveLength(2);
    expect(originalRecord).toBeDefined();
    expect(replacementRecord).toBeDefined();
    expect(originalRecord!.usedAt).not.toBeNull();
    expect(originalRecord!.replacedByJti).toBe(replacementRecord!.jti);
    expect(session.refreshTokens.every((record) => record.revokedAt !== null)).toBe(
      true,
    );

    await expect(
      sessionsA.authenticateAccessToken(winners[0].value.accessToken),
    ).rejects.toMatchObject({ code: 'AUTH_ACCESS_INVALID' });
    await expect(
      sessionsA.rotateRefreshToken(winners[0].value.refreshToken),
    ).rejects.toMatchObject({ code: 'AUTH_REFRESH_INVALID' });
  });

  it('revokes only the presented session on logout and all sessions on password change', async () => {
    const deviceA = await register();
    const deviceB = await usersB.login({
      username: deviceA.username,
      password: PASSWORD,
    });
    const sidA = String(claims(deviceA.accessToken).sid);

    await usersA.logout(deviceA.id, sidA);
    await expect(
      sessionsA.authenticateAccessToken(deviceA.accessToken),
    ).rejects.toMatchObject({ code: 'AUTH_ACCESS_INVALID' });
    await expect(
      sessionsA.rotateRefreshToken(deviceA.refreshToken),
    ).rejects.toMatchObject({ code: 'AUTH_REFRESH_INVALID' });
    await expect(
      sessionsB.authenticateAccessToken(deviceB.accessToken),
    ).resolves.toMatchObject({ userId: deviceB.id });

    await usersB.changePassword(deviceB.id, {
      currentPassword: PASSWORD,
      newPassword: 'replacement-password-123',
    });
    await expect(
      sessionsB.authenticateAccessToken(deviceB.accessToken),
    ).rejects.toMatchObject({ code: 'AUTH_ACCESS_INVALID' });
    await expect(
      sessionsB.rotateRefreshToken(deviceB.refreshToken),
    ).rejects.toMatchObject({ code: 'AUTH_REFRESH_INVALID' });
    await expect(
      usersA.login({ username: deviceA.username, password: PASSWORD }),
    ).rejects.toMatchObject({ code: 'AUTH_INVALID_CREDENTIALS' });
    await expect(
      usersA.login({
        username: deviceA.username,
        password: 'replacement-password-123',
      }),
    ).resolves.toMatchObject({ id: deviceA.id });
  });

  it('never exceeds five active sessions under concurrent issuance', async () => {
    const initial = await register();
    const attempts = await Promise.allSettled(
      Array.from({ length: 8 }, (_value, index) =>
        (index % 2 === 0 ? usersA : usersB).login({
          username: initial.username,
          password: PASSWORD,
        }),
      ),
    );
    expect(attempts.some((attempt) => attempt.status === 'fulfilled')).toBe(true);

    const activeCount = await databaseA.client.authSession.count({
      where: {
        userId: initial.id,
        status: 'ACTIVE',
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
    });
    expect(activeCount).toBeLessThanOrEqual(5);
  });

  it('cannot issue from a stale password check after password-change revocation', async () => {
    const initial = await register();
    let markIssuanceReached!: () => void;
    let releaseIssuance!: () => void;
    const issuanceReached = new Promise<void>((resolve) => {
      markIssuanceReached = resolve;
    });
    const issuanceGate = new Promise<void>((resolve) => {
      releaseIssuance = resolve;
    });
    const gatedSessions = new AuthSessionService(databaseA.client);
    const runTransaction =
      gatedSessions.withSerializableTransaction.bind(gatedSessions);
    gatedSessions.withSerializableTransaction = (async (operation: unknown) => {
      markIssuanceReached();
      await issuanceGate;
      return runTransaction(operation as never);
    }) as typeof gatedSessions.withSerializableTransaction;
    const staleLoginUserService = new UserService(
      databaseA.client,
      gatedSessions,
    );

    const staleLogin = staleLoginUserService
      .login({ username: initial.username, password: PASSWORD })
      .then(
        () => ({ kind: 'accepted' as const }),
        (error: unknown) => ({ kind: 'rejected' as const, error }),
      );
    await issuanceReached;
    await usersB.changePassword(initial.id, {
      currentPassword: PASSWORD,
      newPassword: 'replacement-password-123',
    });
    releaseIssuance();

    const outcome = await staleLogin;
    expect(outcome).toMatchObject({
      kind: 'rejected',
      error: { code: 'AUTH_INVALID_CREDENTIALS' },
    });
    expect(
      await databaseA.client.authSession.count({
        where: {
          userId: initial.id,
          status: 'ACTIVE',
          revokedAt: null,
          expiresAt: { gt: new Date() },
        },
      }),
    ).toBe(0);
  });

  it('/me service data excludes passwords and internal session state', async () => {
    const registered = await register();

    const me = await usersA.getMe(registered.id);

    expect(me).toEqual({
      id: registered.id,
      username: registered.username,
      firstname: 'Ada',
      lastname: 'Runner',
      profilePicturePath: null,
      profilePictureType: null,
      hasPassword: true,
    });
    expect(JSON.stringify(me)).not.toContain('password');
    expect(JSON.stringify(me)).not.toContain('session');
    expect(JSON.stringify(me)).not.toContain('token');
  });
});
