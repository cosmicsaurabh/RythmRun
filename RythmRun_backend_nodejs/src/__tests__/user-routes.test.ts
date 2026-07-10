import 'reflect-metadata';

const mockUserController = {
  register: jest.fn(),
  login: jest.fn(),
  logout: jest.fn(),
  refreshToken: jest.fn(),
  updateProfile: jest.fn(),
  changePassword: jest.fn(),
};

jest.mock('../config/container', () => ({
  container: {
    resolve: jest.fn(() => mockUserController),
  },
}));

import userRoutes from '../routes/user.routes';

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
