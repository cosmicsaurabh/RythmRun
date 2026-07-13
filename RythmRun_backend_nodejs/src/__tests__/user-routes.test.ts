import 'reflect-metadata';
import { jest } from '@jest/globals';

const mockUserController = {
  register: jest.fn(),
  login: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
};

jest.unstable_mockModule('../config/container.js', () => ({
  container: {
    resolve: jest.fn(() => mockUserController),
  },
}));

const { default: userRoutes } = await import('../routes/user.routes.js');

interface RouterLayer {
  route?: {
    path: string;
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
      '/logout',
      '/refresh-token',
      '/profile',
      '/change-password',
    ]);
    expect(routePaths).not.toContain('/profile-picture');
    expect(routePaths).not.toContain('/profile-picture/:id');
  });
});
