import { Router, urlencoded } from 'express';
import type { RequestHandler } from 'express';
import { container } from '../config/container.js';
import {
  createAuthRateLimiters,
  type AuthRateLimiters,
} from '../config/rate-limits.js';
import { UserController } from '../controllers/user.controller.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export interface UserRouteController {
  register: RequestHandler;
  login: RequestHandler;
  googleAuth: RequestHandler;
  verifyEmail: RequestHandler;
  resendVerification: RequestHandler;
  requestPasswordReset: RequestHandler;
  passwordResetPage: RequestHandler;
  submitPasswordReset: RequestHandler;
  logout: RequestHandler;
  refreshToken: RequestHandler;
  me: RequestHandler;
  updateProfile: RequestHandler;
  changePassword: RequestHandler;
  deleteAccount: RequestHandler;
}

export interface UserRouterDependencies {
  controller: UserRouteController;
  authenticate: RequestHandler;
  /**
   * IP-2.6 request budgets. Defaults to the shipped limits so a caller cannot
   * accidentally mount this router unprotected; tests that are not exercising
   * the budgets pass `createPassthroughRateLimiters()`.
   */
  rateLimits?: AuthRateLimiters;
}

/**
 * Builds the user router from explicit HTTP-layer dependencies. Production
 * uses the eagerly resolved dependencies below; tests can inject a real
 * controller and an authentication stub.
 */
export function createUserRouter({
  controller,
  authenticate,
  rateLimits = createAuthRateLimiters(),
}: UserRouterDependencies): Router {
  const router = Router();

  /**
   * Authentication Routes
   * @route POST /api/users/register
   * @description Register a new user
   * @body {RegisterUserDto} - username, password, firstname (optional), lastname (optional)
   * @returns {Object} User data with access and refresh tokens
   */
  router.post('/register', rateLimits.register, controller.register);

  /**
   * @route POST /api/users/login
   * @description Authenticate user and get tokens
   * @body {LoginUserDto} - username, password
   * @returns {Object} User data with access and refresh tokens
   */
  // Two ceilings: the per-account budget stops guessing one account's
  // password, the address budget stops spraying one password across many.
  router.post(
    '/login',
    rateLimits.login,
    rateLimits.loginAddress,
    controller.login,
  );

  /**
   * @route POST /api/users/auth/google
   * @description Exchange a Google ID token for a RythmRun session
   * @body {GoogleAuthDto} - idToken
   * @returns {Object} User data with access and refresh tokens
   */
  router.post('/auth/google', rateLimits.googleExchange, controller.googleAuth);

  /**
   * @route GET /api/users/verify-email
   * @description Consume an email verification token from a link (public).
   * @query {string} token - the raw verification token
   * @returns {text/html} A human-facing verification result page
   */
  router.get('/verify-email', controller.verifyEmail);

  /**
   * @route POST /api/users/password-reset/request
   * @description Start a password reset (public, generic response, throttled).
   * @body {PasswordResetRequestDto} - username (email)
   */
  router.post(
    '/password-reset/request',
    rateLimits.passwordResetRequest,
    controller.requestPasswordReset,
  );

  /**
   * @route GET /api/users/password-reset
   * @description Render the password-reset form opened from the emailed link.
   * @query {string} token
   * @returns {text/html}
   */
  router.get('/password-reset', controller.passwordResetPage);

  /**
   * @route POST /api/users/password-reset
   * @description Submit the reset form (url-encoded) to set a new password.
   * @body {PasswordResetConfirmDto} - token, newPassword
   * @returns {text/html} Result page
   */
  router.post(
    '/password-reset',
    rateLimits.passwordResetSubmit,
    urlencoded({ extended: false }),
    controller.submitPasswordReset,
  );

  /**
   * @route POST /api/users/logout
   * @description Logout user and invalidate refresh token
   * @auth Required
   * @returns {Object} Success message
   */
  router.post('/logout', authenticate, controller.logout);

  /**
   * @route GET /api/users/me
   * @description Return the authenticated user's safe profile fields
   * @auth Required
   */
  router.get('/me', authenticate, controller.me);

  /**
   * @route POST /api/users/refresh-token
   * @description Get new access token using refresh token
   * @auth Refresh token in the request body
   * @body {string} refreshToken
   * @returns {Object} New access and refresh tokens
   */
  router.post('/refresh-token', controller.refreshToken);

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
  router.put(
    '/change-password',
    authenticate,
    rateLimits.passwordChange,
    controller.changePassword,
  );

  /**
   * @route POST /api/users/verify-email/resend
   * @description Re-send the verification email for the authenticated user.
   * @auth Required
   * @returns {Object} Generic acknowledgement (throttled server-side)
   */
  router.post(
    '/verify-email/resend',
    authenticate,
    rateLimits.verificationResend,
    controller.resendVerification,
  );

  /**
   * @route DELETE /api/users/me
   * @description Delete authenticated user account and all associated data
   * @auth Required
   * @body {DeleteAccountDto} - password or googleIdToken
   */
  router.delete(
    '/me',
    authenticate,
    rateLimits.accountDeletion,
    controller.deleteAccount,
  );

  return router;
}

const router = createUserRouter({
  controller: container.resolve(UserController),
  authenticate: authMiddleware,
});

export default router;
