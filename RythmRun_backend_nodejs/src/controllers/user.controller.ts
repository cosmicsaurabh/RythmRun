import type { Request, Response } from 'express';
import { inject, injectable } from 'tsyringe';

import {
  AuthApplicationError,
  invalidRefreshError,
} from '../errors/auth.error.js';
import {
  DtoValidationError,
  validateDto,
} from '../middleware/validation.middleware.js';
import {
  ChangePasswordDto,
  LoginUserDto,
  RefreshTokenDto,
  RegisterUserDto,
  UpdateProfileDto,
} from '../models/dto/user.dto.js';
import { UserService } from '../services/user.service.js';

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
}
