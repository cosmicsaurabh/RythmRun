import 'reflect-metadata';
import { jest } from '@jest/globals';

const mockUserController = {
  register: jest.fn(),
  login: jest.fn(),
  googleAuth: jest.fn(),
  verifyEmail: jest.fn(),
  resendVerification: jest.fn(),
  requestPasswordReset: jest.fn(),
  passwordResetPage: jest.fn(),
  submitPasswordReset: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  me: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
};

jest.unstable_mockModule('../config/container.js', () => ({
  container: {
    resolve: jest.fn(() => mockUserController),
  },
}));

const { createUserRouter, default: userRoutes } = await import(
  '../routes/user.routes.js'
);
const { createPassthroughRateLimiters } = await import(
  '../config/rate-limits.js'
);

interface RouterLayer {
  handle?: unknown;
  route?: {
    path: string;
    stack: RouterLayer[];
  };
}

describe('user routes', () => {
  it('does not expose the retired local profile-picture endpoints', () => {
    const routePaths = (userRoutes as unknown as { stack: RouterLayer[] }).stack
      .map((layer) => layer.route?.path)
      .filter((path): path is string => path !== undefined);

    expect(routePaths).toEqual([
      '/register',
      '/login',
      '/auth/google',
      '/verify-email',
      '/password-reset/request',
      '/password-reset',
      '/password-reset',
      '/logout',
      '/me',
      '/refresh-token',
      '/profile',
      '/change-password',
      '/verify-email/resend',
    ]);
    expect(routePaths).not.toContain('/profile-picture');
    expect(routePaths).not.toContain('/profile-picture/:id');
  });

  it('keeps Google auth and refresh public while protecting the current-user route', () => {
    const authenticate = jest.fn();
    const rateLimits = createPassthroughRateLimiters();
    const router = createUserRouter({
      controller: mockUserController,
      authenticate,
      rateLimits,
    });
    const routeLayers = (router as unknown as { stack: RouterLayer[] }).stack;
    const refreshRoute = routeLayers.find(
      (layer) => layer.route?.path === '/refresh-token',
    )?.route;
    const googleRoute = routeLayers.find(
      (layer) => layer.route?.path === '/auth/google',
    )?.route;
    const meRoute = routeLayers.find(
      (layer) => layer.route?.path === '/me',
    )?.route;

    expect(refreshRoute?.stack.map((layer) => layer.handle)).toEqual([
      mockUserController.refreshToken,
    ]);
    expect(googleRoute?.stack.map((layer) => layer.handle)).toEqual([
      rateLimits.googleExchange,
      mockUserController.googleAuth,
    ]);
    expect(meRoute?.stack.map((layer) => layer.handle)).toEqual([
      authenticate,
      mockUserController.me,
    ]);
  });

  // IP-2.6: a limiter that is silently dropped from a route is invisible in
  // behavioural tests until the endpoint is already being abused, so the wiring
  // itself is asserted here.
  it.each([
    ['/register', 'register', 'register'],
    ['/login', 'login', 'login'],
    ['/auth/google', 'googleExchange', 'googleAuth'],
    ['/password-reset/request', 'passwordResetRequest', 'requestPasswordReset'],
    ['/change-password', 'passwordChange', 'changePassword'],
    ['/verify-email/resend', 'verificationResend', 'resendVerification'],
  ] as const)(
    'places the %s rate limiter before its controller',
    (path, limiterName, controllerName) => {
      const rateLimits = createPassthroughRateLimiters();
      const router = createUserRouter({
        controller: mockUserController,
        authenticate: jest.fn(),
        rateLimits,
      });
      const route = (router as unknown as { stack: RouterLayer[] }).stack.find(
        (layer) => layer.route?.path === path,
      )?.route;
      const handlers = route?.stack.map((layer) => layer.handle) ?? [];

      const limiterIndex = handlers.indexOf(rateLimits[limiterName]);
      const controllerIndex = handlers.indexOf(mockUserController[controllerName]);

      expect(limiterIndex).toBeGreaterThanOrEqual(0);
      expect(controllerIndex).toBeGreaterThan(limiterIndex);
    },
  );

  it('rate-limits the public password-reset submission but not the form render', () => {
    const rateLimits = createPassthroughRateLimiters();
    const router = createUserRouter({
      controller: mockUserController,
      authenticate: jest.fn(),
      rateLimits,
    });
    const resetRoutes = (router as unknown as { stack: RouterLayer[] }).stack
      .filter((layer) => layer.route?.path === '/password-reset')
      .map((layer) => layer.route!.stack.map((inner) => inner.handle));

    expect(resetRoutes).toHaveLength(2);
    expect(resetRoutes[0]).toEqual([mockUserController.passwordResetPage]);
    expect(resetRoutes[1][0]).toBe(rateLimits.passwordResetSubmit);
    expect(resetRoutes[1]).toContain(mockUserController.submitPasswordReset);
  });

  it('runs authentication before the account-scoped limiters', () => {
    const authenticate = jest.fn();
    const rateLimits = createPassthroughRateLimiters();
    const router = createUserRouter({
      controller: mockUserController,
      authenticate,
      rateLimits,
    });
    const routeLayers = (router as unknown as { stack: RouterLayer[] }).stack;

    // The account dimension is req.user.id, so a limiter placed ahead of
    // authentication would key every caller into one shared bucket.
    for (const [path, limiterName] of [
      ['/change-password', 'passwordChange'],
      ['/verify-email/resend', 'verificationResend'],
    ] as const) {
      const handlers =
        routeLayers
          .find((layer) => layer.route?.path === path)
          ?.route?.stack.map((layer) => layer.handle) ?? [];

      expect(handlers.indexOf(authenticate)).toBe(0);
      expect(handlers.indexOf(rateLimits[limiterName])).toBe(1);
    }
  });
});
