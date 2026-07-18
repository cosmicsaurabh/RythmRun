import 'reflect-metadata';
import { jest } from '@jest/globals';

const mockUserController = {
  register: jest.fn(),
  login: jest.fn(),
  googleAuth: jest.fn(),
  verifyEmail: jest.fn(),
  resendVerification: jest.fn(),
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
    const router = createUserRouter({
      controller: mockUserController,
      authenticate,
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
      mockUserController.googleAuth,
    ]);
    expect(meRoute?.stack.map((layer) => layer.handle)).toEqual([
      authenticate,
      mockUserController.me,
    ]);
  });
});
