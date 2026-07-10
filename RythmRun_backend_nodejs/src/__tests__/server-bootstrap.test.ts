const mockEvents: string[] = [];
const mockRetryPendingDeletes = jest.fn().mockResolvedValue(undefined);
const mockRetryPendingCleanup = jest.fn().mockResolvedValue(undefined);
const mockResolve = jest.fn((token: string) => {
  if (token === 'ActivityImageService') {
    return { retryPendingDeletes: mockRetryPendingDeletes };
  }

  if (token === 'AvatarService') {
    return { retryPendingCleanup: mockRetryPendingCleanup };
  }

  throw new Error(`Unexpected service token: ${token}`);
});
const mockRetryTimer = {
  unref: jest.fn(),
};
let mockRetryCallback: (() => void) | undefined;
const mockServer = {
  on: jest.fn().mockReturnThis(),
};
const mockListen = jest.fn((_port: number, callback: () => void) => {
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

jest.mock('../config/env', () => ({
  loadAndValidateEnvironment: jest.fn(() => {
    mockEvents.push('validate');
  }),
}));

jest.mock('../app', () => {
  mockEvents.push('app-import');
  return {
    __esModule: true,
    createApp: mockCreateApp,
  };
});

jest.mock('../config/container', () => {
  mockEvents.push('container-import');
  return {
    container: {
      resolve: mockResolve,
    },
  };
});

jest.mock('../routes/user.routes', () => mockRouteModule('users'));
jest.mock('../routes/friend.routes', () => mockRouteModule('friends'));
jest.mock('../routes/avatar.routes', () => mockRouteModule('avatar'));
jest.mock('../routes/activity-image.routes', () =>
  mockRouteModule('activity-images'),
);
jest.mock('../routes/activity.routes', () => mockRouteModule('activities'));
jest.mock('../routes/comment.routes', () => mockRouteModule('comments'));
jest.mock('../routes/like.routes', () => mockRouteModule('likes'));

import { startServer } from '../server';

describe('server bootstrap', () => {
  const originalPort = process.env.PORT;
  const originalNodeEnv = process.env.NODE_ENV;

  beforeEach(() => {
    mockEvents.length = 0;
    process.env.PORT = '8091';
    process.env.NODE_ENV = 'production';
    jest.spyOn(console, 'log').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    jest.spyOn(global, 'setInterval').mockImplementation((callback) => {
      mockRetryCallback = callback as () => void;
      return mockRetryTimer as unknown as NodeJS.Timeout;
    });
  });

  afterEach(() => {
    jest.restoreAllMocks();
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
    await startServer();

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
    expect(mockRetryPendingDeletes).toHaveBeenCalledTimes(1);
    expect(mockRetryPendingCleanup).toHaveBeenCalledTimes(1);
    expect(console.error).toHaveBeenCalledWith(
      'Avatar cleanup retry failed (AvatarCleanupError)',
    );
    expect(JSON.stringify((console.error as jest.Mock).mock.calls)).not.toContain(
      sensitiveMessage,
    );
  });
});
