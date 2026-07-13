import { Router } from 'express';
import type { RequestHandler } from 'express';
import { container } from '../config/container.js';
import { UserController } from '../controllers/user.controller.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export interface UserRouteController {
  register: RequestHandler;
  login: RequestHandler;
  logout: RequestHandler;
  refreshToken: RequestHandler;
  updateProfile: RequestHandler;
  changePassword: RequestHandler;
}

export interface UserRouterDependencies {
  controller: UserRouteController;
  authenticate: RequestHandler;
}

/**
 * Builds the user router from explicit HTTP-layer dependencies. Production
 * uses the eagerly resolved dependencies below; tests can inject a real
 * controller and an authentication stub.
 */
export function createUserRouter({
  controller,
  authenticate,
}: UserRouterDependencies): Router {
  const router = Router();

  /**
   * Authentication Routes
   * @route POST /api/users/register
   * @description Register a new user
   * @body {RegisterUserDto} - username, password, firstname (optional), lastname (optional)
   * @returns {Object} User data with access and refresh tokens
   */
  router.post('/register', controller.register);

  /**
   * @route POST /api/users/login
   * @description Authenticate user and get tokens
   * @body {LoginUserDto} - username, password
   * @returns {Object} User data with access and refresh tokens
   */
  router.post('/login', controller.login);

  /**
   * @route POST /api/users/logout
   * @description Logout user and invalidate refresh token
   * @auth Required
   * @returns {Object} Success message
   */
  router.post('/logout', authenticate, controller.logout);

  /**
   * @route POST /api/users/refresh-token
   * @description Get new access token using refresh token
   * @auth Required
   * @body {string} refreshToken
   * @returns {Object} New access and refresh tokens
   */
  router.post('/refresh-token', authenticate, controller.refreshToken);

  /**
   * Profile Management Routes
   * @route PUT /api/users/profile
   * @description Update user profile information
   * @auth Required
   * @body {UpdateProfileDto} - firstname, lastname
   * @returns {Object} Updated user data
   */
  router.put('/profile', authenticate, controller.updateProfile);

  /**
   * @route PUT /api/users/change-password
   * @description Change user password
   * @auth Required
   * @body {ChangePasswordDto} - currentPassword, newPassword
   * @returns {Object} Success message
   */
  router.put('/change-password', authenticate, controller.changePassword);

  return router;
}

const router = createUserRouter({
  controller: container.resolve(UserController),
  authenticate: authMiddleware,
});

export default router;
