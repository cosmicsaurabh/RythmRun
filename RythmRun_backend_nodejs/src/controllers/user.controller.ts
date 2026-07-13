import type { Request, Response } from 'express';
import { UserService } from '../services/user.service.js';
import { RegisterUserDto, LoginUserDto, ChangePasswordDto, UpdateProfileDto } from '../models/dto/user.dto.js';
import { injectable, inject } from "tsyringe";
import { validateDto } from '../middleware/validation.middleware.js';

@injectable()
export class UserController {
    constructor(
        @inject("UserService") private userService: UserService
    ) {}

    register = async (req: Request, res: Response) => {
        try {
            const registerDto = await validateDto(RegisterUserDto, req.body);
            const result = await this.userService.register(registerDto);
            res.status(201).json(result);
        } catch (error: any) {
            res.status(400).json({
                error: 'REGISTRATION_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    login = async (req: Request, res: Response) => {
        try {
            const loginDto = await validateDto(LoginUserDto, req.body);
            const result = await this.userService.login(loginDto);
            res.status(200).json(result);
        } catch (error: any) {
            res.status(401).json({
                error: 'LOGIN_FAILED',
                message: error.message,
                statusCode: 401,
                timestamp: new Date().toISOString()
            });
        }
    };

    logout = async (req: Request, res: Response) => {
        try {
            await this.userService.logout(req.user!.id);
            return res.status(200).json({
                status: 'success',
                message: 'Successfully logged out'
            });
        } catch (error) {
            console.error('Logout error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    refreshToken = async (req: Request, res: Response) => {
        try {
            const result = await this.userService.refreshToken(
                req.user!.id,
                req.body.refreshToken
            );

            return res.status(200).json({
                status: 'success',
                data: result
            });
        } catch (error: any) {
            if (error?.message === 'Invalid refresh token') {
                return res.status(401).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Token refresh error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    changePassword = async (req: Request, res: Response) => {
        try {
            const userId = req.user!.id;
            const changePasswordDto = await validateDto(ChangePasswordDto, req.body);
            await this.userService.changePassword(userId, changePasswordDto);
            res.status(200).json({ 
                message: 'Password changed successfully',
                statusCode: 200,
                timestamp: new Date().toISOString()
            });
        } catch (error: any) {
            console.error('Password change error:', error);
            res.status(400).json({
                error: 'PASSWORD_CHANGE_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    updateProfile = async (req: Request, res: Response) => {
        try {
            const userId = req.user!.id;
            const updateProfileDto = await validateDto(UpdateProfileDto, req.body);
            await this.userService.updateProfile(userId, updateProfileDto);
            res.status(200).json({ message: 'Profile updated successfully' });
        } catch (error: any) {
            res.status(400).json({
                error: 'PROFILE_UPDATE_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };
}
