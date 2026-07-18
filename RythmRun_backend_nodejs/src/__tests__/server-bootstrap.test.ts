import { jest } from '@jest/globals';

const originalSetInterval = global.setInterval;
const originalClearInterval = global.clearInterval;
const mockEvents: string[] = [];
const mockRetryPendingDeletes = jest.fn().mockResolvedValue(undefined);
const mockRetryPendingCleanup = jest.fn().mockResolvedValue(undefined);
const mockPurgeExpiredSessions = jest.fn().mockResolvedValue(0);
const mockPurgeExpiredVerificationTokens = jest.fn().mockResolvedValue(0);
const mockResolve = jest.fn((token: string) => {
  if (token === 'ActivityImageService') {
    return { retryPendingDeletes: mockRetryPendingDeletes };
  }

  if (token === 'AvatarService') {
    return { retryPendingCleanup: mockRetryPendingCleanup };
  }

  if (token === 'AuthSessionService') {
    return { purgeExpiredSessions: mockPurgeExpiredSessions };
  }

  if (token === 'UserService') {
    return {
      purgeExpiredVerificationTokens: mockPurgeExpiredVerificationTokens,
    };
  }

  throw new Error(`Unexpected service token: ${token}`);
});
const mockRetryTimer = {
  unref: jest.fn(),
};
let mockRetryCallback: (() => void) | undefined;
const mockServer = {
  listening: true,
  address: jest.fn(() => ({ address: '127.0.0.1', family: 'IPv4', port: 8091 })),
  once: jest.fn().mockReturnThis(),
  close: jest.fn((callback: (error?: Error) => void) => {
    mockServer.listening = false;
    callback();
    return mockServer;
  }),
};
const mockDatabaseDisconnect = jest.fn().mockResolvedValue(undefined);
const mockListen = jest.fn((_port: number, callback: (error?: Error) => void) => {
  mockEvents.push('listen');
  callback();
  return mockServer;
});
const mockCreateApp = jest.fn(() => ({ listen: mockListen }));
const mockRouter = {};
const mockRouteModule = (name: string) => {
  mockEvents.push(`route-import:${name}`);
  return { __esModule: true, default: mockRouter };
};

jest.unstable_mockModule('../config/env.js', () => ({
  loadAndValidateEnvironment: jest.fn(() => {
    mockEvents.push('validate');
    return {
      DATABASE_URL: 'postgresql://ci:ci@127.0.0.1:5432/ci',
      GOOGLE_SERVER_CLIENT_ID: 'test.apps.googleusercontent.com',
    };
  }),
  validateEmailEnvironment: jest.fn(() => null),
}));

jest.unstable_mockModule('../app.js', () => {
  mockEvents.push('app-import');
  return {
    __esModule: true,
    createApp: mockCreateApp,
  };
});

jest.unstable_mockModule('../config/container.js', () => {
  mockEvents.push('container-import');
  return {
    container: {
      resolve: mockResolve,
    },
    configureContainer: jest.fn(() => ({
      client: {},
      disconnect: mockDatabaseDisconnect,
    })),
  };
});

jest.unstable_mockModule('../routes/user.routes.js', () => mockRouteModule('users'));
jest.unstable_mockModule('../routes/friend.routes.js', () => mockRouteModule('friends'));
jest.unstable_mockModule('../routes/avatar.routes.js', () => mockRouteModule('avatar'));
jest.unstable_mockModule('../routes/activity-image.routes.js', () =>
  mockRouteModule('activity-images'),
);
jest.unstable_mockModule('../routes/activity.routes.js', () => mockRouteModule('activities'));
jest.unstable_mockModule('../routes/comment.routes.js', () => mockRouteModule('comments'));
jest.unstable_mockModule('../routes/like.routes.js', () => mockRouteModule('likes'));

const { startServer, stopServer } = await import('../server.js');

describe('server bootstrap', () => {
  const originalPort = process.env.PORT;
  const originalNodeEnv = process.env.NODE_ENV;

  beforeEach(() => {
    jest.clearAllMocks();
    mockEvents.length = 0;
    mockServer.listening = true;
    process.env.PORT = '8091';
    process.env.NODE_ENV = 'production';
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    global.setInterval = jest.fn((callback) => {
      mockRetryCallback = callback as () => void;
      return mockRetryTimer as unknown as NodeJS.Timeout;
    }) as typeof setInterval;
    global.clearInterval = jest.fn(() => undefined) as typeof clearInterval;
  });

  afterEach(() => {
    jest.restoreAllMocks();
    global.setInterval = originalSetInterval;
    global.clearInterval = originalClearInterval;
    if (originalPort === undefined) {
      delete process.env.PORT;
    } else {
      process.env.PORT = originalPort;
    }

    if (originalNodeEnv === undefined) {
      delete process.env.NODE_ENV;
    } else {
      process.env.NODE_ENV = originalNodeEnv;
    }
  });

  it('validates environment before importing consumers or listening', async () => {
    const server = await startServer();

    expect(mockEvents[0]).toBe('validate');
    expect(mockEvents).toContain('app-import');
    expect(mockEvents).toContain('container-import');
    expect(mockEvents[mockEvents.length - 1]).toBe('listen');
    expect(mockListen).toHaveBeenCalledWith(8091, expect.any(Function));

    const sensitiveMessage = 'storage details that must not be logged';
    const cleanupError = new Error(sensitiveMessage);
    cleanupError.name = 'AvatarCleanupError';
    mockRetryPendingCleanup.mockRejectedValueOnce(cleanupError);

    expect(mockRetryCallback).toBeDefined();
    mockRetryCallback?.();
    await new Promise<void>((resolve) => setImmediate(resolve));

    expect(mockResolve).toHaveBeenCalledWith('ActivityImageService');
    expect(mockResolve).toHaveBeenCalledWith('AvatarService');
    expect(mockResolve).toHaveBeenCalledWith('AuthSessionService');
    expect(mockResolve).toHaveBeenCalledWith('UserService');
    expect(mockRetryPendingDeletes).toHaveBeenCalledTimes(1);
    expect(mockRetryPendingCleanup).toHaveBeenCalledTimes(1);
    expect(mockPurgeExpiredSessions).toHaveBeenCalledTimes(1);
    expect(mockPurgeExpiredVerificationTokens).toHaveBeenCalledTimes(1);
    expect(console.error).toHaveBeenCalledWith(
      'Avatar cleanup retry failed (AvatarCleanupError)',
    );
    expect(JSON.stringify((console.error as jest.Mock).mock.calls)).not.toContain(
      sensitiveMessage,
    );

    await stopServer(server);
    expect(mockDatabaseDisconnect).toHaveBeenCalledTimes(1);
    expect(clearInterval).toHaveBeenCalledTimes(1);
  });

  it('rejects listener startup errors and disconnects the database', async () => {
    const listenError = new Error('address already in use');
    listenError.name = 'ListenError';
    mockListen.mockImplementationOnce((_port, callback) => {
      callback(listenError);
      return mockServer;
    });

    await expect(startServer()).rejects.toBe(listenError);
    expect(mockDatabaseDisconnect).toHaveBeenCalledTimes(1);
    expect(setInterval).not.toHaveBeenCalled();
  });
});
