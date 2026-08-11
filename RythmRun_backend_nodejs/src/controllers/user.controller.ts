import type { Request, Response } from 'express';
import { inject, injectable } from 'tsyringe';

import {
  AuthApplicationError,
  invalidRefreshError,
} from '../errors/auth.error.js';
import { AccountDeletionServiceError } from '../errors/account-deletion.error.js';
import {
  DtoValidationError,
  validateDto,
} from '../middleware/validation.middleware.js';
import {
  ChangePasswordDto,
  DeleteAccountDto,
  GoogleAuthDto,
  LoginUserDto,
  PasswordResetConfirmDto,
  PasswordResetRequestDto,
  RefreshTokenDto,
  RegisterUserDto,
  UpdateProfileDto,
} from '../models/dto/user.dto.js';
import { UserService } from '../services/user.service.js';
import { renderVerifyPage } from '../templates/verify-page.template.js';
import {
  renderResetError,
  renderResetForm,
  renderResetSuccess,
} from '../templates/reset-page.template.js';

interface ErrorResponseOptions {
  validationCode: string;
  unexpectedOperation: string;
}

function sendError(
  res: Response,
  error: unknown,
  options: ErrorResponseOptions,
): Response {
  if (error instanceof AuthApplicationError) {
    return res.status(error.statusCode).json({
      error: error.code,
      message: error.message,
      retryable: error.retryable,
      statusCode: error.statusCode,
      timestamp: new Date().toISOString(),
    });
  }
  if (error instanceof AccountDeletionServiceError) {
    return res.status(error.statusCode).json({
      error: error.code,
      message: error.message,
      statusCode: error.statusCode,
      timestamp: new Date().toISOString(),
    });
  }
  if (error instanceof DtoValidationError) {
    return res.status(400).json({
      error: options.validationCode,
      message: 'Validation failed',
      statusCode: 400,
      timestamp: new Date().toISOString(),
    });
  }

  const category = error instanceof Error ? error.name : 'UnknownError';
  console.error(`${options.unexpectedOperation} failed (${category})`);
  return res.status(500).json({
    error: 'INTERNAL_ERROR',
    message: 'Internal server error',
    statusCode: 500,
    timestamp: new Date().toISOString(),
  });
}

@injectable()
export class UserController {
  constructor(
    @inject('UserService') private readonly userService: UserService,
  ) {}

  register = async (req: Request, res: Response): Promise<void> => {
    try {
      const registerDto = await validateDto(RegisterUserDto, req.body);
      res.status(201).json(await this.userService.register(registerDto));
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'REGISTRATION_FAILED',
        unexpectedOperation: 'Registration',
      });
    }
  };

  login = async (req: Request, res: Response): Promise<void> => {
    try {
      const loginDto = await validateDto(LoginUserDto, req.body);
      res.status(200).json(await this.userService.login(loginDto));
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'LOGIN_FAILED',
        unexpectedOperation: 'Login',
      });
    }
  };

  googleAuth = async (req: Request, res: Response): Promise<void> => {
    try {
      const googleAuthDto = await validateDto(GoogleAuthDto, req.body);
      res.status(200).json(await this.userService.googleLogin(googleAuthDto));
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'GOOGLE_AUTH_FAILED',
        unexpectedOperation: 'Google authentication',
      });
    }
  };

  refreshToken = async (req: Request, res: Response): Promise<void> => {
    try {
      let refreshDto: RefreshTokenDto;
      try {
        refreshDto = await validateDto(RefreshTokenDto, req.body);
      } catch (error: unknown) {
        if (error instanceof DtoValidationError) {
          throw invalidRefreshError();
        }
        throw error;
      }
      res
        .status(200)
        .json(await this.userService.refreshToken(refreshDto.refreshToken));
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'AUTH_REFRESH_INVALID',
        unexpectedOperation: 'Token refresh',
      });
    }
  };

  logout = async (req: Request, res: Response): Promise<void> => {
    try {
      await this.userService.logout(req.user!.id, req.user!.sessionId);
      res.status(200).json({
        status: 'success',
        message: 'Successfully logged out',
      });
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'LOGOUT_FAILED',
        unexpectedOperation: 'Logout',
      });
    }
  };

  verifyEmail = async (req: Request, res: Response): Promise<void> => {
    // Public, human-facing HTML route. Tighten CSP for this static page and
    // strip the Referer so the token in the URL cannot leak to any origin.
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    );
    res.setHeader('Referrer-Policy', 'no-referrer');

    const token =
      typeof req.query.token === 'string' ? req.query.token : '';
    try {
      const result = await this.userService.verifyEmail(token);
      res
        .status(200)
        .type('html')
        .send(
          renderVerifyPage(result === 'already_verified' ? 'already' : 'success'),
        );
    } catch (error: unknown) {
      if (!(error instanceof AuthApplicationError)) {
        const category = error instanceof Error ? error.name : 'UnknownError';
        console.error(`Email verification failed (${category})`);
      }
      const statusCode =
        error instanceof AuthApplicationError ? error.statusCode : 500;
      res.status(statusCode).type('html').send(renderVerifyPage('error'));
    }
  };

  resendVerification = async (req: Request, res: Response): Promise<void> => {
    try {
      await this.userService.resendVerification(req.user!.id);
      res.status(200).json({
        message:
          'If your email is not yet verified, a new verification link has been sent.',
        statusCode: 200,
        timestamp: new Date().toISOString(),
      });
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'VERIFICATION_RESEND_FAILED',
        unexpectedOperation: 'Verification resend',
      });
    }
  };

  requestPasswordReset = async (
    req: Request,
    res: Response,
  ): Promise<void> => {
    try {
      const dto = await validateDto(PasswordResetRequestDto, req.body);
      await this.userService.requestPasswordReset(dto.username);
      // Always generic: the response is identical whether or not an account
      // exists, so it never becomes an account-enumeration oracle.
      res.status(200).json({
        message:
          'If an account exists for that email, a password reset link has been sent.',
        statusCode: 200,
        timestamp: new Date().toISOString(),
      });
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'PASSWORD_RESET_REQUEST_FAILED',
        unexpectedOperation: 'Password reset request',
      });
    }
  };

  passwordResetPage = async (
    req: Request,
    res: Response,
  ): Promise<void> => {
    // Public HTML form opened from the emailed link. The token is validated on
    // submit, not here, so rendering the form is not a token-existence oracle.
    this.applyResetPageHeaders(res);
    const token = typeof req.query.token === 'string' ? req.query.token : '';
    res.status(200).type('html').send(renderResetForm(token));
  };

  submitPasswordReset = async (
    req: Request,
    res: Response,
  ): Promise<void> => {
    this.applyResetPageHeaders(res);
    const rawToken =
      typeof req.body?.token === 'string' ? req.body.token : '';
    try {
      const dto = await validateDto(PasswordResetConfirmDto, req.body);
      await this.userService.resetPassword(dto.token, dto.newPassword);
      res.status(200).type('html').send(renderResetSuccess());
    } catch (error: unknown) {
      if (error instanceof DtoValidationError) {
        // Bad password (e.g. too short): re-render the form to retry, keeping
        // the token so a valid link is not lost.
        res
          .status(400)
          .type('html')
          .send(
            renderResetForm(
              rawToken,
              'Password must be 8–50 characters. Please try again.',
            ),
          );
        return;
      }
      if (!(error instanceof AuthApplicationError)) {
        const category = error instanceof Error ? error.name : 'UnknownError';
        console.error(`Password reset failed (${category})`);
      }
      const statusCode =
        error instanceof AuthApplicationError ? error.statusCode : 500;
      res.status(statusCode).type('html').send(renderResetError());
    }
  };

  // The reset pages render a same-origin form and must not leak the token in
  // the URL via the Referer header; the CSP also permits the form POST target.
  private applyResetPageHeaders(res: Response): void {
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'",
    );
    res.setHeader('Referrer-Policy', 'no-referrer');
  }

  me = async (req: Request, res: Response): Promise<void> => {
    try {
      res.status(200).json(await this.userService.getMe(req.user!.id));
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'PROFILE_FAILED',
        unexpectedOperation: 'Profile read',
      });
    }
  };

  changePassword = async (req: Request, res: Response): Promise<void> => {
    try {
      const changePasswordDto = await validateDto(
        ChangePasswordDto,
        req.body,
      );
      await this.userService.changePassword(req.user!.id, changePasswordDto);
      res.status(200).json({
        message: 'Password changed successfully',
        statusCode: 200,
        timestamp: new Date().toISOString(),
      });
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'PASSWORD_CHANGE_FAILED',
        unexpectedOperation: 'Password change',
      });
    }
  };

  updateProfile = async (req: Request, res: Response): Promise<void> => {
    try {
      const updateProfileDto = await validateDto(UpdateProfileDto, req.body);
      // Return the updated safe user (same shape as /me) so the client can
      // commit visible and cached profile state from one authoritative source.
      res
        .status(200)
        .json(
          await this.userService.updateProfile(req.user!.id, updateProfileDto),
        );
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'PROFILE_UPDATE_FAILED',
        unexpectedOperation: 'Profile update',
      });
    }
  };

  deleteAccount = async (req: Request, res: Response): Promise<void> => {
    try {
      const dto = await validateDto(DeleteAccountDto, req.body);
      await this.userService.deleteAccount(req.user!.id, dto);
      res.status(200).json({
        message: 'Account deleted successfully',
        statusCode: 200,
        timestamp: new Date().toISOString(),
      });
    } catch (error: unknown) {
      sendError(res, error, {
        validationCode: 'ACCOUNT_DELETION_FAILED',
        unexpectedOperation: 'Account deletion',
      });
    }
  };
}

